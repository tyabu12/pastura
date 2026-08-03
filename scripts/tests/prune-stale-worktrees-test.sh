#!/usr/bin/env bash
#
# scripts/tests/prune-stale-worktrees-test.sh — regression test for
# scripts/prune-stale-worktrees.sh (#1335).
#
# WHY EACH CASE IS A NEGATIVE CONTROL
# A janitor's success case proves almost nothing: a script that removes
# everything and a script that applies the predicate correctly both pass "the
# stale worktree was removed". What distinguishes them is whether each KEEP
# condition can be made to fire ON ITS OWN. So every case below holds all other
# conditions at their removable values and flips exactly one, and asserts on
# WHICH reason the script reported — not merely that the directory survived.
# A case that survives for the wrong reason is a false pass.
#
# The aging fixtures use a fixed literal stamp (`touch -t 200001010000`) rather
# than date arithmetic, because `date -d` (GNU) and `date -v` (BSD) do not
# co-exist and this test runs on ubuntu-latest while the script under test
# targets macOS. `assert_aged` verifies the stamp actually took effect: a
# `touch` that silently failed would age nothing, and every case would then
# pass for the wrong reason.
#
# Scaffold (tempdir + `trap rm EXIT` + `fail=0` accumulator) and the synthetic
# git-config hardening follow scripts/tests/kmp-gate-isolation-test.sh.
#
# bash 3.2 portable — no mapfile/readarray, declare -A, ${var^^}, <<< strings.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd -P)"
SCRIPT="$ROOT/scripts/prune-stale-worktrees.sh"

fail=0
pass_count=0
# Decremented by any branch that legitimately skips a case; see the check at
# the end of the file.
EXPECTED_PASSES=26

ok() {
  pass_count=$((pass_count + 1))
  printf '  ok   %s\n' "$1"
}

bad() {
  fail=1
  printf '  FAIL %s\n' "$1"
}

# `git` in a synthetic repo: ambient user config, signing and hooks must not
# leak in or the fixtures behave differently per developer machine.
sgit() {
  git -c commit.gpgsign=false -c core.hooksPath=/dev/null \
      -c user.email=test@example.com -c user.name=test "$@"
}

TMP="$(mktemp -d)" || exit 1
trap 'rm -rf "$TMP"' EXIT
REPO="$(cd "$TMP" && pwd -P)/repo"

# --- fixture repository -------------------------------------------------------
mkdir -p "$REPO"
sgit init -q -b main "$REPO"
printf 'DerivedData/\nbuild/\n.gradle/\nnode_modules/\nkeepme.local\n' > "$REPO/.gitignore"
# Ignore patterns the FILE arm is tested against. `*.bak` and the nested/`data/`
# paths are ignored on purpose: an entry that is merely untracked would be
# stopped by condition (d) and the case would silently be testing (d) instead
# of the file arm.
printf '.claude/settings.local.json\n.DS_Store\n*.bak\nsub/.claude/settings.local.json\ndata/queue/digest.md\n' >> "$REPO/.gitignore"
echo seed > "$REPO/a.txt"
# Every directory an ignored entry sits under must be TRACKED, mirroring the
# real repo. git collapses a wholly-ignored *untracked* directory up to its
# topmost untracked parent, so an untracked `Pastura/` would be reported as
# `!! Pastura/` instead of `!! Pastura/DerivedData/` — and the fixture would
# then exercise a path shape that cannot occur in this repository. The same
# applies to `.claude/`, `sub/.claude/` and `data/queue/`: without an anchor
# there, every file-arm case below would pass by construction because
# is_disposable would never see the path it is supposed to match.
mkdir -p "$REPO/Pastura" "$REPO/shared/models" "$REPO/.claude/rules" "$REPO/.claude/skills" "$REPO/sub/.claude" "$REPO/data/queue"
echo anchor > "$REPO/Pastura/tracked.txt"
echo anchor > "$REPO/shared/models/tracked.txt"
echo anchor > "$REPO/.claude/rules/anchor.md"
# `.claude/skills/` needs its own anchor: the real repo tracks skill files
# there, so a `.DS_Store` inside it is reported at full path. Anchoring only
# `.claude/` leaves `skills/` untracked and git collapses it to
# `!! .claude/skills/` — a shape this repository cannot produce. The
# precondition assertion in the file-arm cases is what caught that.
echo anchor > "$REPO/.claude/skills/anchor.md"
echo anchor > "$REPO/sub/.claude/anchor.md"
echo anchor > "$REPO/data/queue/anchor.md"
sgit -C "$REPO" add -A
sgit -C "$REPO" commit -qm "init"
mkdir -p "$REPO/.claude/worktrees"

# Create a worktree and age it into removable range.
# $1 = directory name under .claude/worktrees/
make_wt() {
  local name="$1" wt="$REPO/.claude/worktrees/$1"
  sgit -C "$REPO" worktree add -q "$wt" -b "b-$1" >/dev/null 2>&1 || return 1
  age_wt "$name"
}

age_wt() {
  age_wt_path "$REPO/.claude/worktrees/$1"
}

# Push every mtime the script reads back to the year 2000.
age_wt_path() {
  local wt="$1" gitdir
  gitdir="$(sgit -C "$wt" rev-parse --git-dir 2>/dev/null)"
  touch -t 200001010000 "$wt" 2>/dev/null
  if [ -n "$gitdir" ]; then
    [ -e "$gitdir/index" ] && touch -t 200001010000 "$gitdir/index" 2>/dev/null
    [ -e "$gitdir/HEAD" ] && touch -t 200001010000 "$gitdir/HEAD" 2>/dev/null
    [ -e "$gitdir/logs" ] && touch -t 200001010000 "$gitdir/logs" 2>/dev/null
    [ -e "$gitdir/logs/HEAD" ] && touch -t 200001010000 "$gitdir/logs/HEAD" 2>/dev/null
  fi
  return 0
}

# The aging mutation must be asserted, not assumed — see the header. It checks
# every path is_fresh reads, not just the root: a silently-failed `touch -t` on
# $gitdir/index would otherwise leave the fixture fresh while the assertion
# passed, which is precisely how the (a) control shipped as a false pass.
assert_aged_path() {
  local wt="$1" label="$2" gitdir p
  gitdir="$(sgit -C "$wt" rev-parse --git-dir 2>/dev/null)"
  for p in "$wt" "$gitdir/index" "$gitdir/HEAD" "$gitdir/logs/HEAD"; do
    case "$p" in /index|/HEAD|/logs/HEAD) continue ;; esac
    [ -e "$p" ] || continue
    if [ -n "$(find "$p" -maxdepth 0 -mmin -720 2>/dev/null)" ]; then
      bad "fixture setup: $label — $p was not aged (touch -t had no effect)"
      return 1
    fi
  done
  return 0
}

assert_aged() {
  assert_aged_path "$REPO/.claude/worktrees/$1" "$1"
}

exists() { [ -d "$REPO/.claude/worktrees/$1" ]; }

# Run the pruner from the main checkout and capture its verbose decisions.
run_prune() {
  ( cd "$REPO" && bash "$SCRIPT" --apply --verbose --log "$TMP/prune.log" 2>&1 )
}

# --- positive control ---------------------------------------------------------
# Establishes that the pruner CAN remove. Without this, every negative control
# below would pass against a script that never removes anything.
printf '== positive control ==\n'
make_wt "adoring-jepsen-80fef5"
AJ="$REPO/.claude/worktrees/adoring-jepsen-80fef5"
# Carry an unpushed commit through the removal. This is the script header's
# central safety claim, and its sibling claim about detached HEADs turned out to
# be false — so pin this one rather than trusting a one-off measurement.
echo carried > "$AJ/carried.txt"
sgit -C "$AJ" add -A
sgit -C "$AJ" commit -qm "unpushed work that must survive removal"
AJ_SHA="$(sgit -C "$AJ" rev-parse HEAD)"
age_wt_path "$AJ"
assert_aged "adoring-jepsen-80fef5"
out="$(run_prune)"
if exists "adoring-jepsen-80fef5"; then
  bad "clean, aged, unnamed worktree should have been removed — got: $out"
else
  ok "clean + aged + unnamed worktree is removed"
fi
if [ "$(sgit -C "$REPO" rev-parse b-adoring-jepsen-80fef5 2>/dev/null)" = "$AJ_SHA" ]; then
  ok "the removed worktree's branch and its unpushed commit survive"
else
  bad "removal destroyed the branch's unpushed commit ($AJ_SHA)"
fi

# --- negative controls --------------------------------------------------------
# Each flips exactly one condition and asserts on the reported REASON.
printf '== negative controls ==\n'

# (b) orchestrate-named worktree
make_wt "feat+some-feature"
assert_aged "feat+some-feature"
out="$(run_prune)"
if exists "feat+some-feature"; then
  case "$out" in
    *"feat+some-feature — named worktree"*) ok "(b) orchestrate-named worktree is kept, as a named worktree" ;;
    *) bad "(b) kept for the wrong reason — got: $out" ;;
  esac
else
  bad "(b) orchestrate-named worktree was removed"
fi
sgit -C "$REPO" worktree remove --force "$REPO/.claude/worktrees/feat+some-feature" 2>/dev/null

# (f) too recently active
make_wt "busy-ellis-301009"
touch "$REPO/.claude/worktrees/busy-ellis-301009"
out="$(run_prune)"
if exists "busy-ellis-301009"; then
  case "$out" in
    *"busy-ellis-301009 — active within"*) ok "(f) recently-touched worktree is kept, as recently active" ;;
    *) bad "(f) kept for the wrong reason — got: $out" ;;
  esac
else
  bad "(f) recently-touched worktree was removed"
fi
sgit -C "$REPO" worktree remove --force "$REPO/.claude/worktrees/busy-ellis-301009" 2>/dev/null

# (f) old root directory but fresh git metadata — the mtime-proxy trap
make_wt "cool-jennings-0ff7d6"
CJ_GITDIR="$(sgit -C "$REPO/.claude/worktrees/cool-jennings-0ff7d6" rev-parse --git-dir 2>/dev/null)"
touch -t 200001010000 "$REPO/.claude/worktrees/cool-jennings-0ff7d6"
touch "$CJ_GITDIR/index"
out="$(run_prune)"
if exists "cool-jennings-0ff7d6"; then
  case "$out" in
    *"cool-jennings-0ff7d6 — active within"*) ok "(f) old root + fresh git index is kept (root mtime alone would have deleted it)" ;;
    *) bad "(f) kept for the wrong reason — got: $out" ;;
  esac
else
  bad "(f) old root + fresh git index was removed — the age check is reading the root only"
fi
sgit -C "$REPO" worktree remove --force "$REPO/.claude/worktrees/cool-jennings-0ff7d6" 2>/dev/null

# (c) locked
make_wt "dreamy-swirles-0d6c1c"
sgit -C "$REPO" worktree lock "$REPO/.claude/worktrees/dreamy-swirles-0d6c1c"
assert_aged "dreamy-swirles-0d6c1c"
out="$(run_prune)"
if exists "dreamy-swirles-0d6c1c"; then
  case "$out" in
    *"dreamy-swirles-0d6c1c — locked"*) ok "(c) locked worktree is kept, as locked" ;;
    *) bad "(c) kept for the wrong reason — got: $out" ;;
  esac
else
  bad "(c) locked worktree was removed"
fi
sgit -C "$REPO" worktree unlock "$REPO/.claude/worktrees/dreamy-swirles-0d6c1c" 2>/dev/null
sgit -C "$REPO" worktree remove --force "$REPO/.claude/worktrees/dreamy-swirles-0d6c1c" 2>/dev/null

# (g) detached HEAD. Unlike (c) and (d) this guard has NO backstop: measured,
# git removes a clean detached worktree without --force and the commit is then
# reachable from zero refs and zero reflogs. So the assertion is not just "kept"
# — it re-resolves the object afterwards to prove nothing was orphaned.
DET="$REPO/.claude/worktrees/laughing-shtern-427042"
sgit -C "$REPO" worktree add -q --detach "$DET" >/dev/null 2>&1
echo detached-work > "$DET/orphan-me.txt"
sgit -C "$DET" add -A
sgit -C "$DET" commit -qm "commit reachable from no branch"
DET_SHA="$(sgit -C "$DET" rev-parse HEAD)"
age_wt_path "$DET"
assert_aged_path "$DET" "detached worktree ((g) case)"
if [ -n "$(sgit -C "$DET" --no-optional-locks status --porcelain)" ]; then
  bad "(g) precondition broken: fixture is not clean, so the case tests (d) not (g)"
fi
out="$(run_prune)"
if [ ! -d "$DET" ]; then
  bad "(g) detached-HEAD worktree was removed — commit $DET_SHA is now reachable from no ref"
else
  case "$out" in
    *"laughing-shtern-427042 — detached HEAD"*)
      if [ "$(sgit -C "$REPO" cat-file -t "$DET_SHA" 2>/dev/null)" = "commit" ]; then
        ok "(g) detached-HEAD worktree is kept, and its unreferenced commit is intact"
      else
        bad "(g) kept, but the detached commit $DET_SHA is gone"
      fi
      ;;
    *) bad "(g) kept for the wrong reason — got: $out" ;;
  esac
fi
sgit -C "$REPO" worktree remove --force "$DET" 2>/dev/null

# --- git-failure paths --------------------------------------------------------
# The script must not read a FAILED git call as the removable answer. Both
# states below are real: a corrupted worktree link and an unreadable index are
# what a crashed session or a half-finished disk operation actually leaves.
# Only the chmod arm needs a non-root uid; the corrupted-link arm is a plain
# text write. The uid guard therefore wraps that arm alone — wrapping both
# would silently drop the ONLY coverage of the gitdir early-return whenever
# this runs as root.

# Unresolvable git directory. Without a guard the age check would silently
# degrade to the worktree root's mtime — the proxy measured days stale.
BROKEN="$REPO/.claude/worktrees/relaxed-davinci-aa7c27"
make_wt "relaxed-davinci-aa7c27"
printf 'gitdir: /nonexistent/path\n' > "$BROKEN/.git"
out="$(run_prune)"
if [ ! -d "$BROKEN" ]; then
  bad "a worktree with an unresolvable git directory was removed"
else
  case "$out" in
    *"relaxed-davinci-aa7c27 — could not resolve its git directory"*)
      ok "an unresolvable git directory keeps the worktree, rather than falling back to root mtime" ;;
    *) bad "unresolvable git directory kept for the wrong reason — got: $out" ;;
  esac
fi
rm -rf "$BROKEN"
sgit -C "$REPO" worktree prune 2>/dev/null

if [ "$(id -u)" -eq 0 ]; then
  printf '  skip running as root: chmod cannot make the index unreadable\n'
  EXPECTED_PASSES=$((EXPECTED_PASSES - 1))
else
  # A failing `git status` must not read as "clean". Verified constructible:
  # with the index unreadable, `rev-parse --git-dir` still exits 0 while
  # `status` exits 128, which isolates this branch from the one above.
  UNREAD="$REPO/.claude/worktrees/wizardly-almeida-2dbfda"
  make_wt "wizardly-almeida-2dbfda"
  assert_aged "wizardly-almeida-2dbfda"
  UA_GITDIR="$(sgit -C "$UNREAD" rev-parse --git-dir 2>/dev/null)"
  chmod 000 "$UA_GITDIR/index"
  if sgit -C "$UNREAD" --no-optional-locks status --porcelain >/dev/null 2>&1; then
    bad "fixture setup: git status still succeeds with an unreadable index, so this case tests nothing"
  fi
  out="$(run_prune)"
  chmod 644 "$UA_GITDIR/index" 2>/dev/null
  if [ ! -d "$UNREAD" ]; then
    bad "a worktree whose git status FAILED was removed — a failed check read as clean"
  else
    case "$out" in
      *"wizardly-almeida-2dbfda — git status failed"*)
        ok "a failing git status keeps the worktree, rather than reading as clean" ;;
      *) bad "failing git status kept for the wrong reason — got: $out" ;;
    esac
  fi
  sgit -C "$REPO" worktree remove --force "$UNREAD" 2>/dev/null
fi

# NOTE on the three failure-path guards above — they back each other up, which
# mutation makes visible rather than obvious. Removing the (d) return-code check
# still keeps the unreadable-index fixture, via (e)'s enumeration-failure guard;
# removing the gitdir guard still keeps the corrupted-link fixture, via (d)'s.
# Both fixtures redden either way, so each case constrains the layer as a whole
# rather than one specific arm — the reason its assertion reads "kept for the
# wrong reason" instead of accepting any KEEP. What is NOT separately
# constructible is a state that reaches (e) with only the ignored-enumeration
# broken: it runs the same `git status` family as (d), which is checked first.
# That branch is exercised only through the (d) mutation above; stating the
# limit beats a case that would silently be re-testing (d). The limit is about
# the GIT arm specifically: blocking_ignored_entry also returns 2 when its
# redirect to the scratch file fails (unwritable TMPDIR, ENOSPC), which has no
# (d) counterpart and IS independently reachable — that arm is uncovered here.

# (d) uncommitted change
make_wt "epic-grothendieck-0b8abc"
echo dirty >> "$REPO/.claude/worktrees/epic-grothendieck-0b8abc/a.txt"
age_wt "epic-grothendieck-0b8abc"
assert_aged "epic-grothendieck-0b8abc"
# This case is also the observable for --no-optional-locks: it is aged, so it
# reaches the status call, and a plain `git status` there would rewrite the
# worktree index — making the worktree look freshly active on every subsequent
# run and deferring it forever. Capture the index mtime across the call.
EG_GITDIR="$(sgit -C "$REPO/.claude/worktrees/epic-grothendieck-0b8abc" rev-parse --git-dir 2>/dev/null)"
out="$(run_prune)"
if [ -n "$(find "$EG_GITDIR/index" -maxdepth 0 -mmin -720 2>/dev/null)" ]; then
  bad "the status call rewrote the worktree index — --no-optional-locks was dropped, so the age guard would never fire again"
else
  ok "status calls leave the worktree index mtime untouched (--no-optional-locks)"
fi
if exists "epic-grothendieck-0b8abc"; then
  case "$out" in
    *"epic-grothendieck-0b8abc — uncommitted changes"*) ok "(d) dirty worktree is kept, as dirty" ;;
    *) bad "(d) kept for the wrong reason — got: $out" ;;
  esac
else
  bad "(d) dirty worktree was removed"
fi
sgit -C "$REPO" worktree remove --force "$REPO/.claude/worktrees/epic-grothendieck-0b8abc" 2>/dev/null

# (e) ignored content that is NOT build output — the class git itself cannot see
make_wt "fervent-kepler-6c3aa2"
echo irreplaceable > "$REPO/.claude/worktrees/fervent-kepler-6c3aa2/keepme.local"
age_wt "fervent-kepler-6c3aa2"
assert_aged "fervent-kepler-6c3aa2"
# Precondition: git considers this worktree clean, i.e. neither git's own
# refusal nor condition (d) would have saved it. Without this the case could
# pass while testing nothing new.
if [ -n "$(sgit -C "$REPO/.claude/worktrees/fervent-kepler-6c3aa2" --no-optional-locks status --porcelain)" ]; then
  bad "(e) precondition broken: fixture is not clean, so the case tests (d) not (e)"
fi
out="$(run_prune)"
if exists "fervent-kepler-6c3aa2"; then
  case "$out" in
    *"fervent-kepler-6c3aa2 — ignored content that is not disposable: keepme.local"*)
      ok "(e) irreplaceable ignored file is kept, and the blocking entry is named" ;;
    *) bad "(e) kept for the wrong reason — got: $out" ;;
  esac
else
  bad "(e) worktree holding an irreplaceable ignored file was removed"
fi
sgit -C "$REPO" worktree remove --force "$REPO/.claude/worktrees/fervent-kepler-6c3aa2" 2>/dev/null

# (e) build output alone must NOT block — otherwise the pruner never fires in
# practice, since every real worktree carries DerivedData/.
make_wt "goofy-hypatia-62c51e"
mkdir -p "$REPO/.claude/worktrees/goofy-hypatia-62c51e/Pastura/DerivedData/Build"
echo x > "$REPO/.claude/worktrees/goofy-hypatia-62c51e/Pastura/DerivedData/Build/big.bin"
mkdir -p "$REPO/.claude/worktrees/goofy-hypatia-62c51e/shared/models/build"
echo x > "$REPO/.claude/worktrees/goofy-hypatia-62c51e/shared/models/build/out.jar"
age_wt "goofy-hypatia-62c51e"
assert_aged "goofy-hypatia-62c51e"
out="$(run_prune)"
if exists "goofy-hypatia-62c51e"; then
  bad "(e) build output alone blocked removal — the pruner would never fire on a real worktree: $out"
else
  ok "(e) nested build output alone does not block removal"
fi

# --- file arm ------------------------------------------------------------------
# Machine-local files that regenerate are disposable; everything else still
# blocks. Each case asserts FIRST that the exact entry string reached the
# pruner: git collapses a wholly-ignored untracked directory up to its topmost
# untracked parent, and a collapsed entry never reaches is_disposable at all, so
# without that precondition every case here would pass by construction.
printf '== file arm ==\n'

# Reads the `-z` stream, which is what blocking_ignored_entry consumes. The
# non-`-z` form C-quotes paths containing spaces or specials, so asserting
# against it would be checking a different string than the pruner sees.
assert_ignored_entry() {
  local wt="$1" want="$2" got
  got="$(sgit -C "$wt" --no-optional-locks status --porcelain -z --ignored | tr '\0' '\n' | sed -n 's/^!! //p' | tr '\n' ' ')"
  case " $got " in
    *" $want "*) return 0 ;;
  esac
  bad "fixture setup: git reported [$got], not '$want' — this case never reaches is_disposable"
  return 1
}

# P1 / P2 — positive controls, one per list. Kept separate so a mutation that
# drops ONE list is reported by a case that names it; a single fixture holding
# both reddens either way but cannot say which list broke.
make_wt "jovial-allen-fb692b"
JA="$REPO/.claude/worktrees/jovial-allen-fb692b"
printf '{}\n' > "$JA/.claude/settings.local.json"
age_wt_path "$JA"
assert_aged "jovial-allen-fb692b"
assert_ignored_entry "$JA" ".claude/settings.local.json"
out="$(run_prune)"
if exists "jovial-allen-fb692b"; then
  bad "(P1) a worktree holding only DISPOSABLE_FILES content was kept — got: $out"
else
  ok "(P1) an exact-path machine-local file does not block removal"
fi

make_wt "sleepy-mahavira-e64867"
SM="$REPO/.claude/worktrees/sleepy-mahavira-e64867"
mkdir -p "$SM/.claude/skills"
printf 'finder junk\n' > "$SM/.claude/skills/.DS_Store"
age_wt_path "$SM"
assert_aged "sleepy-mahavira-e64867"
assert_ignored_entry "$SM" ".claude/skills/.DS_Store"
out="$(run_prune)"
if exists "sleepy-mahavira-e64867"; then
  bad "(P2) a worktree holding only DISPOSABLE_BASENAMES content was kept — got: $out"
else
  ok "(P2) a basename-matched file does not block removal"
fi

# N1 — near-miss name. Reddens if any prefix/suffix globbing creeps in.
make_wt "silly-zhukovsky-d58f0f"
LS="$REPO/.claude/worktrees/silly-zhukovsky-d58f0f"
printf 'not the real thing\n' > "$LS/.claude/settings.local.json.bak"
age_wt_path "$LS"
assert_ignored_entry "$LS" ".claude/settings.local.json.bak"
out="$(run_prune)"
if ! exists "silly-zhukovsky-d58f0f"; then
  bad "(N1) a near-miss filename was treated as disposable"
else
  case "$out" in
    *"silly-zhukovsky-d58f0f — ignored content that is not disposable: .claude/settings.local.json.bak"*)
      ok "(N1) a near-miss filename still blocks, and is named" ;;
    *) bad "(N1) kept for the wrong reason — got: $out" ;;
  esac
fi
sgit -C "$REPO" worktree remove --force "$LS" 2>/dev/null

# N2 — same basename, different directory. Reddens if the full-path entry is
# matched by basename.
make_wt "musing-feistel-75f689"
MF="$REPO/.claude/worktrees/musing-feistel-75f689"
printf '{}\n' > "$MF/sub/.claude/settings.local.json"
age_wt_path "$MF"
assert_ignored_entry "$MF" "sub/.claude/settings.local.json"
out="$(run_prune)"
if ! exists "musing-feistel-75f689"; then
  bad "(N2) a copy at a different path was treated as disposable — the full-path entry is being matched by basename"
else
  case "$out" in
    *"musing-feistel-75f689 — ignored content that is not disposable: sub/.claude/settings.local.json"*)
      ok "(N2) the same basename elsewhere still blocks" ;;
    *) bad "(N2) kept for the wrong reason — got: $out" ;;
  esac
fi
sgit -C "$REPO" worktree remove --force "$MF" 2>/dev/null

# N3 — a DIRECTORY named .DS_Store. Reddens if the file arm leaks past the
# trailing-slash selector and reaches the basename rule.
make_wt "nice-booth-cc6294"
NB="$REPO/.claude/worktrees/nice-booth-cc6294"
mkdir -p "$NB/.DS_Store"
printf 'payload\n' > "$NB/.DS_Store/inside.txt"
age_wt_path "$NB"
assert_ignored_entry "$NB" ".DS_Store/"
out="$(run_prune)"
if ! exists "nice-booth-cc6294"; then
  bad "(N3) a DIRECTORY named .DS_Store was treated as disposable — the basename rule is reachable from the directory arm"
else
  case "$out" in
    *"nice-booth-cc6294 — ignored content that is not disposable: .DS_Store/"*)
      ok "(N3) a directory named .DS_Store still blocks" ;;
    *) bad "(N3) kept for the wrong reason — got: $out" ;;
  esac
fi
sgit -C "$REPO" worktree remove --force "$NB" 2>/dev/null

# N4 — the widening must not disable (e) wholesale. Holds every allowed entry
# PLUS one irreplaceable file, and requires that irreplaceable one to be named:
# this is the control for the "allowing one entry just promotes the next"
# ordering the change is built on.
make_wt "pensive-montalcini-9c660f"
PM="$REPO/.claude/worktrees/pensive-montalcini-9c660f"
printf '{}\n' > "$PM/.claude/settings.local.json"
mkdir -p "$PM/.claude/skills"
printf 'finder junk\n' > "$PM/.claude/skills/.DS_Store"
printf 'irreplaceable local journal\n' > "$PM/data/queue/digest.md"
age_wt_path "$PM"
assert_ignored_entry "$PM" "data/queue/digest.md"
out="$(run_prune)"
if ! exists "pensive-montalcini-9c660f"; then
  bad "(N4) a worktree holding data/queue/digest.md was removed — widening the set disabled condition (e)"
else
  case "$out" in
    *"pensive-montalcini-9c660f — ignored content that is not disposable: data/queue/digest.md"*)
      ok "(N4) disposable entries are skipped and the irreplaceable one still blocks, by name" ;;
    *) bad "(N4) kept for the wrong reason — got: $out" ;;
  esac
fi
sgit -C "$REPO" worktree remove --force "$PM" 2>/dev/null

# (a) a worktree outside .claude/worktrees/
mkdir -p "$REPO/elsewhere"
sgit -C "$REPO" worktree add -q "$REPO/elsewhere/quirky-wing-ab02d1" -b b-outside >/dev/null 2>&1
# Age the git METADATA too, not just the root. Ageing the root alone leaves
# index/HEAD freshly written by `git worktree add`, so condition (f) keeps this
# worktree no matter what (a) does — and the case then passes against a script
# with no containment check at all. Verified by mutation.
age_wt_path "$REPO/elsewhere/quirky-wing-ab02d1"
assert_aged_path "$REPO/elsewhere/quirky-wing-ab02d1" "outside worktree ((a) case)"
out="$(run_prune)"
if [ ! -d "$REPO/elsewhere/quirky-wing-ab02d1" ]; then
  bad "(a) worktree outside .claude/worktrees/ was removed"
elif printf '%s' "$out" | grep -q 'quirky-wing-ab02d1'; then
  # Condition (a) returns before any record is written, so the worktree must
  # not appear in verbose output at all. Without this the case would pass on
  # a script that merely kept it for some other reason — the shape that let
  # the original version of this case survive deleting (a) outright.
  bad "(a) outside worktree was evaluated rather than skipped by the path check — got: $out"
else
  ok "(a) worktree outside .claude/worktrees/ is never evaluated"
fi

# --- self-gate ----------------------------------------------------------------
printf '== self-gate ==\n'
make_wt "hungry-goldberg-68b651"
assert_aged "hungry-goldberg-68b651"
OUTER="$REPO/.claude/worktrees/hungry-goldberg-68b651"
VICTIM="$OUTER/.claude/worktrees/nested-victim-a1b2c3"

# The NESTED worktree is what makes this control able to redden, and it is not
# decoration. Without it, `--show-toplevel` from inside a worktree already
# points condition (a) at that worktree's own (empty) .claude/worktrees/, so
# deleting the self-gate outright would change nothing observable here and the
# case would pass against a script that has no self-gate at all — verified by
# mutation. `git worktree add` permits this nesting even though EnterWorktree
# refuses it, so the script must not rely on the harness being polite.
mkdir -p "$OUTER/.claude/worktrees"
sgit -C "$REPO" worktree add -q "$VICTIM" -b b-nested >/dev/null 2>&1
age_wt_path "$VICTIM"
assert_aged_path "$VICTIM" "nested victim (self-gate case)"

# Invoke the pruner with a worktree as cwd. It must no-op rather than start
# removing the nested worktree — or itself.
out="$( cd "$OUTER" && bash "$SCRIPT" --apply --verbose --log "$TMP/prune-self.log" 2>&1 )"
if [ ! -d "$VICTIM" ]; then
  bad "self-gate: the script removed a worktree while running from inside one"
elif ! exists "hungry-goldberg-68b651"; then
  bad "self-gate: script removed the worktree it was invoked from"
elif [ -n "$out" ]; then
  bad "self-gate: script produced output from inside a worktree: $out"
else
  ok "self-gate: from inside a worktree the script is silent and removes nothing, even a prunable nested worktree"
fi

# Remove the nested worktree before the later cases: from the main checkout it
# sits under .claude/worktrees/ too, so it would otherwise be a live candidate
# and contaminate the idle-run assertion below.
sgit -C "$REPO" worktree remove --force "$VICTIM" 2>/dev/null
# Only the directory this case created. `.claude/` also holds the fixture's
# TRACKED anchors, so removing it wholesale leaves this worktree permanently
# dirty — after which the idle-log assertion below survives only because
# condition (f) short-circuits before (d), an ordering dependency the comment
# there does not describe and which would invert if evaluate() were reordered.
rm -rf "$OUTER/.claude/worktrees"

# --- dry-run default ----------------------------------------------------------
# Its own fixture: hungry-goldberg is reserved for the idle case below, and the
# two need opposite ages.
printf '== dry-run default ==\n'
make_wt "jolly-wright-63b7e9"
assert_aged "jolly-wright-63b7e9"
out="$( cd "$REPO" && bash "$SCRIPT" --verbose --log "$TMP/prune-dry.log" 2>&1 )"
if exists "jolly-wright-63b7e9"; then
  case "$out" in
    *"would remove jolly-wright-63b7e9"*) ok "without --apply the script only reports, and says so" ;;
    *) bad "dry run did not report the candidate — got: $out" ;;
  esac
else
  bad "dry run removed a worktree — --apply is not gating removal"
fi

# --- log file -----------------------------------------------------------------
printf '== decision log ==\n'
if [ -s "$TMP/prune-dry.log" ]; then
  case "$(cat "$TMP/prune-dry.log")" in
    *"WOULD-REMOVE  jolly-wright-63b7e9"*) ok "the dry-run decision is written to the log" ;;
    *) bad "log written but missing the decision: $(cat "$TMP/prune-dry.log")" ;;
  esac
else
  bad "no decision log was written"
fi
sgit -C "$REPO" worktree remove --force "$REPO/.claude/worktrees/jolly-wright-63b7e9" 2>/dev/null

# A run with nothing ACTIONABLE must leave no trace. At this point the only
# remaining candidate is hungry-goldberg-68b651, kept purely because it is
# young — the steady state on a machine with a live session. The log is read by
# a human, so appending that on every session start would bury the entries that
# matter.
touch "$REPO/.claude/worktrees/hungry-goldberg-68b651"
if [ -z "$(find "$REPO/.claude/worktrees/hungry-goldberg-68b651" -maxdepth 0 -mmin -720 2>/dev/null)" ]; then
  bad "fixture setup: hungry-goldberg-68b651 was not freshened, so the idle case tests nothing"
fi
( cd "$REPO" && bash "$SCRIPT" --apply --quiet --log "$TMP/prune-idle.log" >/dev/null 2>&1 )
if [ -e "$TMP/prune-idle.log" ]; then
  bad "an idle run wrote to the log: $(cat "$TMP/prune-idle.log")"
else
  ok "an idle run writes nothing to the log"
fi

# --- invariants ---------------------------------------------------------------
printf '== invariants ==\n'
# Passing --force would dissolve the backstop conditions (c) and (d) rest on:
# git's own refusal to remove a dirty or locked worktree. This is a TEXTUAL
# check deliberately — behaviourally it is unobservable while (c)/(d) work,
# since they return before a removal is ever attempted. Verified by mutation:
# adding --force to the removal leaves every behavioural case green.
# Comment lines are filtered first: the header's own sentence "`git worktree
# remove` is ALWAYS called without `--force`" contains both tokens, so an
# unfiltered grep fires on the documentation of the very invariant it checks.
NONCOMMENT="$(grep -vE '^[[:space:]]*#' "$SCRIPT")"
if ! printf '%s\n' "$NONCOMMENT" | grep -q 'git worktree remove'; then
  # Positive control. Without it the guard reports success on a script whose
  # removal call vanished entirely — verified: the pipeline simply finds
  # nothing and the else-branch fires.
  bad "no removal call outside comments — this invariant guard has nothing to check"
elif printf '%s\n' "$NONCOMMENT" | grep -q -- '--force'; then
  bad "the pruner passes --force, dissolving git's own dirty/locked refusal"
else
  ok "the pruner never passes --force to git worktree remove"
fi

# --- exec bit -----------------------------------------------------------------
printf '== packaging ==\n'
if [ -x "$SCRIPT" ]; then
  ok "the script is executable"
else
  bad "the script is missing its exec bit"
fi

# A skipped case lowers pass_count, and a lower-but-consistent number reads as
# fine — the blind spot subagent-usage.md §2 describes. Pin the expected total
# so a case that silently stops running FAILS instead of just counting less.
if [ "$pass_count" -ne "$EXPECTED_PASSES" ]; then
  bad "expected $EXPECTED_PASSES passing cases, counted $pass_count — a case stopped running"
fi

printf '\n%s passed (expected %s), exit=%s\n' "$pass_count" "$EXPECTED_PASSES" "$fail"
exit "$fail"
