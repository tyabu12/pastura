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
echo seed > "$REPO/a.txt"
# `Pastura/` and `shared/models/` must be TRACKED, mirroring the real repo.
# git collapses a wholly-ignored *untracked* directory up to its topmost
# untracked parent, so an untracked `Pastura/` would be reported as `!! Pastura/`
# instead of `!! Pastura/DerivedData/` — and the fixture would then exercise a
# path shape that cannot occur in this repository.
mkdir -p "$REPO/Pastura" "$REPO/shared/models"
echo anchor > "$REPO/Pastura/tracked.txt"
echo anchor > "$REPO/shared/models/tracked.txt"
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

# The aging mutation must be asserted, not assumed — see the header.
assert_aged() {
  local name="$1" wt="$REPO/.claude/worktrees/$1"
  if [ -n "$(find "$wt" -maxdepth 0 -mmin -720 2>/dev/null)" ]; then
    bad "fixture setup: $name was not aged (touch -t had no effect)"
    return 1
  fi
  return 0
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
if [ -n "$(find "$DET" -maxdepth 0 -mmin -720 2>/dev/null)" ]; then
  bad "fixture setup: the detached worktree was not aged, so the (g) case tests nothing"
fi
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
    *"fervent-kepler-6c3aa2 — ignored content that is not build output: keepme.local"*)
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

# (a) a worktree outside .claude/worktrees/
mkdir -p "$REPO/elsewhere"
sgit -C "$REPO" worktree add -q "$REPO/elsewhere/quirky-wing-ab02d1" -b b-outside >/dev/null 2>&1
# Age the git METADATA too, not just the root. Ageing the root alone leaves
# index/HEAD freshly written by `git worktree add`, so condition (f) keeps this
# worktree no matter what (a) does — and the case then passes against a script
# with no containment check at all. Verified by mutation.
age_wt_path "$REPO/elsewhere/quirky-wing-ab02d1"
if [ -n "$(find "$REPO/elsewhere/quirky-wing-ab02d1" -maxdepth 0 -mmin -720 2>/dev/null)" ]; then
  bad "fixture setup: the outside worktree was not aged, so the (a) case tests nothing"
fi
out="$(run_prune)"
if [ -d "$REPO/elsewhere/quirky-wing-ab02d1" ]; then
  ok "(a) worktree outside .claude/worktrees/ is untouched"
else
  bad "(a) worktree outside .claude/worktrees/ was removed"
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
if [ -n "$(find "$VICTIM" -maxdepth 0 -mmin -720 2>/dev/null)" ]; then
  bad "fixture setup: the nested victim was not aged, so the self-gate case tests nothing"
fi

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
rm -rf "$OUTER/.claude"

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
if grep 'git worktree remove' "$SCRIPT" | grep -vE '^[[:space:]]*#' | grep -q -- '--force'; then
  bad "the pruner passes --force to git worktree remove, dissolving git's own dirty/locked refusal"
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

printf '\n%s passed, exit=%s\n' "$pass_count" "$fail"
exit "$fail"
