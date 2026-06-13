#!/bin/bash
# Tests for sync_digest_pr.py. git runs for real (a temp clone + bare origin),
# so switch / merge --ff-only / status / rev-list / push are exercised with
# true behaviour; only `gh` is stubbed (see fake_bin/gh) since it is the only
# network surface. Invoked by run_tests.sh.
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/../scripts/sync_digest_pr.py"
SEED="$HERE/fixtures/digest_seed.md"
export PATH="$HERE/fake_bin:$PATH"   # fake gh shadows the real one

ROOT=$(mktemp -d)
trap 'rm -rf "$ROOT"' EXIT
fail() { echo "FAIL [$CASE]: $1" >&2; exit 1; }

# Fresh repo (working clone tracking a bare origin), seeded with a committed
# digest on main. Echoes the working-clone path. Uses mktemp per call —
# new_repo runs inside a command-substitution subshell, so a mutable counter
# would not increment across calls and every repo would collide.
new_repo() {
  local W
  W=$(mktemp -d "$ROOT/repoXXXXXX")
  git init -q --bare "$W/origin.git"
  git init -q "$W/repo"
  (
    set -e
    cd "$W/repo"
    git config user.email a@b.c; git config user.name t
    git symbolic-ref HEAD refs/heads/main   # robust vs init.defaultBranch
    mkdir -p data/factory
    cp "$SEED" data/factory/digest.md
    git add -A; git commit -q -m init
    git remote add origin "$W/origin.git"
    git push -q -u origin main
  )
  echo "$W/repo"
}

# Append a line to the digest (simulates /scenario-factory writing a section).
dirty_digest() { echo "- run $(date +%s%N)" >> "$1/data/factory/digest.md"; }

run() { ( cd "$1"; shift; python3 "$SCRIPT" "$@" ); }

# --- prepare: zero open PRs → creates a dated branch --------------------------
CASE="prepare/no-pr"
R=$(new_repo)
OUT=$(FAKE_GH_PR_LIST='[]' run "$R" prepare)
echo "$OUT" | grep -Eq '^factory/digest-[0-9]{8}$' || fail "did not print a dated branch: $OUT"
CUR=$(cd "$R" && git rev-parse --abbrev-ref HEAD)
echo "$CUR" | grep -Eq '^factory/digest-[0-9]{8}$' || fail "not on a factory branch: $CUR"

# --- prepare: dirty tree → abort ---------------------------------------------
CASE="prepare/dirty"
R=$(new_repo); dirty_digest "$R"
if ERR=$(FAKE_GH_PR_LIST='[]' run "$R" prepare 2>&1 >/dev/null); then fail "dirty tree should abort"; fi
echo "$ERR" | grep -q "not clean" || fail "wrong abort reason: $ERR"

# --- prepare: >1 factory PR → single-writer abort ----------------------------
CASE="prepare/multi-pr"
R=$(new_repo)
LIST='[{"number":1,"headRefName":"factory/digest-20260101","isDraft":true},{"number":2,"headRefName":"factory/digest-20260102","isDraft":true}]'
if ERR=$(FAKE_GH_PR_LIST="$LIST" run "$R" prepare 2>&1 >/dev/null); then fail ">1 factory PR should abort"; fi
echo "$ERR" | grep -q "single-writer" || fail "wrong abort reason: $ERR"

# --- prepare: one open PR → switch + fast-forward to remote tip ---------------
CASE="prepare/one-pr-ff"
R=$(new_repo)
B=factory/digest-20260601
(
  cd "$R"
  git switch -q -c "$B" main
  echo "- remote night 1" >> data/factory/digest.md
  git add -A; git commit -q -m n1; git push -q -u origin "$B"
  git switch -q main
  git branch -q -D "$B"           # drop local → prepare must DWIM from origin
)
LIST='[{"number":7,"headRefName":"'"$B"'","isDraft":true}]'
OUT=$(FAKE_GH_PR_LIST="$LIST" run "$R" prepare)
[ "$OUT" = "$B" ] || fail "should print $B, got $OUT"
CUR=$(cd "$R" && git rev-parse --abbrev-ref HEAD); [ "$CUR" = "$B" ] || fail "not switched to $B"
# HEAD must equal the remote tip (ff happened), so the night-1 line is present
grep -q "remote night 1" "$R/data/factory/digest.md" || fail "did not fast-forward to remote tip"

# --- prepare: non-draft factory PR still matched (no second branch) ----------
CASE="prepare/ready-pr"
R=$(new_repo)
B=factory/digest-20260602
( cd "$R"; git switch -q -c "$B" main; echo x >> data/factory/digest.md
  git add -A; git commit -q -m n; git push -q -u origin "$B"; git switch -q main; git branch -q -D "$B" )
LIST='[{"number":8,"headRefName":"'"$B"'","isDraft":false}]'   # ready, not draft
OUT=$(FAKE_GH_PR_LIST="$LIST" run "$R" prepare)
[ "$OUT" = "$B" ] || fail "ready (non-draft) PR must still be matched, got $OUT"

# --- prepare: orphaned unpushed commit → recover (stay on branch) ------------
CASE="prepare/orphan-recover"
R=$(new_repo)
B=factory/digest-20260603
( cd "$R"; git switch -q -c "$B" main; echo orphan >> data/factory/digest.md
  git add -A; git commit -q -m orphan )   # committed, NOT pushed, no PR
OUT=$(FAKE_GH_PR_LIST='[]' run "$R" prepare)
[ "$OUT" = "$B" ] || fail "should recover orphan branch $B, got $OUT"

# --- publish: branch guard rejects main --------------------------------------
CASE="publish/guard-main"
R=$(new_repo)
if ERR=$(run "$R" publish 2>&1 >/dev/null); then fail "publish on main must be refused"; fi
echo "$ERR" | grep -q "refusing to publish" || fail "wrong abort reason: $ERR"

# --- publish: no digest change → no-op, no PR --------------------------------
CASE="publish/noop"
R=$(new_repo); LOG="$ROOT/log_noop"; : > "$LOG"
( cd "$R"; git switch -q -c factory/digest-20260604 main )   # fresh, no commits
OUT=$(FAKE_GH_LOG="$LOG" FAKE_GH_PR_FOR_HEAD='[]' run "$R" publish)
echo "$OUT" | grep -q "no new digest" || fail "should report no-op, got: $OUT"
[ -s "$LOG" ] && fail "no-op publish must not call gh pr create"

# --- publish: digest change, no PR yet → commit, push, create PR -------------
CASE="publish/create"
R=$(new_repo); LOG="$ROOT/log_create"; : > "$LOG"
( cd "$R"; git switch -q -c factory/digest-20260605 main ); dirty_digest "$R"
OUT=$(FAKE_GH_LOG="$LOG" FAKE_GH_PR_FOR_HEAD='[]' run "$R" publish)
grep -q "gh pr create" "$LOG" || fail "should create a Draft PR"
grep -q -- "--draft" "$LOG" || fail "PR must be --draft"
( cd "$R"; git rev-parse --verify -q origin/factory/digest-20260605 >/dev/null ) || fail "branch not pushed"

# --- publish: digest change, PR already open → push, NO create ---------------
CASE="publish/append"
R=$(new_repo); LOG="$ROOT/log_append"; : > "$LOG"
( cd "$R"; git switch -q -c factory/digest-20260606 main ); dirty_digest "$R"
FAKE_GH_LOG="$LOG" FAKE_GH_PR_FOR_HEAD='[{"number":5}]' run "$R" publish >/dev/null
[ -s "$LOG" ] && fail "must NOT create a second PR when one is open"
( cd "$R"; git rev-parse --verify -q origin/factory/digest-20260606 >/dev/null ) || fail "branch not pushed"

echo "sync_digest_pr: ALL TESTS PASSED"
