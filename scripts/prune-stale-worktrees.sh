#!/usr/bin/env bash
#
# scripts/prune-stale-worktrees.sh — remove stale, unnamed git worktrees left
# behind by unattended Claude Code sessions (#1335).
#
# WHY THIS EXISTS
# `EnterWorktree`'s contract is that on session exit "the user will be prompted
# to keep or remove it". An unattended run — a Claude Desktop local Routine
# such as queue-consumer-nightly — has nobody to answer that prompt, so its
# worktree is kept and residue accumulates one directory per night.
#
# WHAT IT REMOVES (all seven conditions must hold)
#   a. path is under <main-checkout>/.claude/worktrees/
#   b. basename matches ^[a-z]+-[a-z]+-[0-9a-f]{6}$
#   c. the worktree is not `locked`
#   d. `git status --porcelain` is empty
#   e. ignored content is limited to build output (DISPOSABLE_COMPONENTS below)
#   f. nothing in the worktree or its git metadata changed in the last 12h
#   g. HEAD is attached to a branch (a detached HEAD's commits are reachable
#      from no ref, so removal would orphan them)
#
# `git worktree remove` is ALWAYS called without `--force`.
#
# WHAT THE PREDICATE ACTUALLY SELECTS
# Condition (b) selects *unnamed* worktrees, NOT specifically routine-created
# ones: `EnterWorktree` generates a Docker-style random name whenever no `name`
# is passed, and an interactive session can do that too. `/orchestrate` always
# passes a branch-shaped name (which becomes `<type>+<slug>`), and that is what
# separates the two classes — validated across 52 historical worktree names:
# 29/29 random names matched, 0/23 orchestrate names matched. The safety
# argument therefore rests on (c)-(f), not on provenance. Read (b) as "nobody
# named this", not as "a routine made this".
#
# MEASURED SAFETY PROPERTIES (verified against synthetic repos, #1335)
#   - Claude Code LOCKS a worktree for the lifetime of the session living in
#     it, recording the pid in the lock reason:
#       locked claude session chore/prune-stale-worktrees (pid 47010 start ...)
#     So condition (c) is not a passive tie-breaker — it is the harness's own
#     liveness signal, and it is what actually protects a live interactive
#     session. A routine's leftovers are unlocked because the routine's session
#     has ended, which is exactly the class this script targets. Known
#     limitation, in the safe direction: a crashed session can leave a stale
#     lock, and that worktree is then never pruned. The dry-run log names
#     `locked` as the reason, so it is diagnosable rather than silent.
#   - Removing a BRANCH-ATTACHED worktree does not delete its branch: a branch
#     carrying an unpushed commit kept its ref, SHA and full content afterwards.
#   - A DETACHED-HEAD worktree is the exception, and it is why condition (g)
#     exists. Measured: a clean, detached worktree carrying a fresh commit is
#     removed without `--force`, and afterwards that commit is reachable from
#     ZERO refs and ZERO reflogs — only `git fsck --unreachable` finds it, until
#     gc prunes it for good. A crashed session left mid-rebase or on a detached
#     HEAD is exactly that shape: unlocked, clean, and aged. So do not restate
#     the property above as "committed work is safe by construction"; it is safe
#     only because (g) refuses the detached case outright.
#   - Without `--force`, git itself refuses a dirty or a locked worktree
#     ("contains modified or untracked files"). So (c) and (d) are defense in
#     depth, not the only guard — a bug in either still cannot destroy
#     uncommitted work.
#   - Both of those guards are blind to gitignored content, which is exactly
#     why (e) exists: `data/queue/digest.md` and `docs/code-health/ledger.md`
#     are gitignored, locally irreplaceable, and leave `git status --porcelain`
#     completely empty.
#
# TWO TRAPS THIS SCRIPT ENCODES (both measured, both silent if got wrong)
#   - `git status` WRITES the worktree's index, bumping its mtime to now.
#     Unhandled, that makes every surviving candidate look freshly active on
#     the next run and defers it forever — the check would quietly never fire.
#     Hence `--no-optional-locks` on every status call, measured to leave the
#     index mtime untouched. Do not drop that flag.
#   - Age is read from git metadata (index/HEAD/logs) as well as the worktree
#     root, because a directory's mtime only moves when entries in that
#     directory itself change. Work under Pastura/Pastura/Views/ never touches
#     the root — measured 9-20 days staler than the git index on a real
#     worktree, which would have aged a live worktree into deletion range.
#
# AGE THRESHOLD
# 12h. The two nightly routines fire ~2h apart (~01:37 and ~03:37), so the
# threshold must exceed the largest plausible overlap of a still-running
# earlier session when the later one starts; 12h leaves ~6x margin while still
# collecting the previous night's residue at ~24h age. Do not "tidy" this down
# to an hour.
#
# TUNING THE DISPOSABLE SET
# Anything ignored-but-not-disposable blocks removal (safe direction: residue
# stays, nothing is lost). The dry-run log names the exact blocking entry for
# each KEEP, which is how this set is meant to be tuned: run dry for a few
# nights, read the log, then add only what is provably build output.
# Two entries to expect FIRST in that log, both deliberately not disposable:
#   - `.claude/settings.local.json` — Claude Code writes permission grants
#     there, so a session that granted anything leaves one behind.
#   - `data/` — the repository tracks no file under it at all, so git collapses
#     the whole directory to a single `!! data/` entry the moment a routine
#     writes its digest there.
# If either turns out to dominate the log, that is a finding about what a
# routine worktree actually accumulates, not a reason to widen the set
# reflexively: widening it is what makes a removal unrecoverable.
#
# USAGE
#   scripts/prune-stale-worktrees.sh              # dry run (default)
#   scripts/prune-stale-worktrees.sh --apply      # actually remove
#   scripts/prune-stale-worktrees.sh --verbose    # explain every decision
#   scripts/prune-stale-worktrees.sh --quiet      # never write stdout
#   scripts/prune-stale-worktrees.sh --log FILE   # override the decision log
#   scripts/prune-stale-worktrees.sh --age-minutes N   # test lever only
#
# stdout defaults to on when it is a TTY and off otherwise, because the wired
# caller is a `SessionStart` hook whose stdout is a context-injection channel —
# printing there would cost every session, every turn. Decisions always go to
# the log file instead. Nothing in this repository wires that hook: see
# CLAUDE.md § "Automated hooks", which directs it to your own untracked
# .claude/settings.local.json.
#
# This script exits 0 on every non-fatal path for the same reason: a
# SessionStart hook that exits non-zero surfaces an error on every session for
# as long as the cause persists. `set -e` is deliberately NOT used; failures
# are handled at each call site.
#
# Self-gates to the MAIN checkout (`--git-dir` == `--git-common-dir`, both
# resolved) so a session running inside a worktree can never try to remove its
# own working directory.
#
# PORTABILITY: bash 3.2, and BSD/GNU userland both — this script targets macOS
# while its regression test (scripts/tests/prune-stale-worktrees-test.sh) runs
# on ubuntu-latest in CI. So: no `stat`, no `date -d` / `date -v`, no
# mapfile/readarray, no `declare -A`, no `${var^^}`, no `<<<` here-strings.
# Age comparisons use `find -mmin`, which behaves identically on both.

set -uo pipefail

AGE_MINUTES=720
APPLY=0
VERBOSE=0
QUIET=0
LOG_FILE=""

# Exact final-path-component match, mirroring the bare-pattern semantics of
# .gitignore's own `build/`, `DerivedData/` and `.build/` rules (which match at
# any depth). Exact rather than glob so a new, unrecognized artifact directory
# fails toward KEEP.
DISPOSABLE_COMPONENTS="build DerivedData .build .gradle node_modules PasturaShared.xcframework"

while [ $# -gt 0 ]; do
  case "$1" in
    --apply) APPLY=1 ;;
    --verbose) VERBOSE=1 ;;
    --quiet) QUIET=1 ;;
    --log)
      shift
      case "${1:-}" in
        ""|-*) printf 'prune-stale-worktrees: --log needs a path\n' >&2; exit 0 ;;
      esac
      LOG_FILE="$1"
      ;;
    --age-minutes)
      shift
      # Must be a plain integer: `find -mmin -<garbage>` errors, is_fresh then
      # reports "not fresh", and the age guard silently disappears for every
      # candidate in the run. Fail closed instead.
      case "${1:-}" in
        *[!0-9]*|"") printf 'prune-stale-worktrees: --age-minutes needs an integer\n' >&2; exit 0 ;;
      esac
      AGE_MINUTES="$1"
      ;;
    -h|--help)
      # Print the header block only, and stop at its end rather than at a line
      # number that drifts as the code below grows.
      awk 'NR > 1 { if (!/^#/) exit; sub(/^# ?/, ""); print }' "$0"
      exit 0
      ;;
    *)
      printf 'prune-stale-worktrees: ignoring unknown argument: %s\n' "$1" >&2
      ;;
  esac
  shift
done

# --- self-gate: main checkout only ------------------------------------------
# In the main checkout `--git-dir` and `--git-common-dir` resolve to the same
# directory; inside a linked worktree the former is .git/worktrees/<id>. Both
# are resolved with `pwd -P` first because git returns a bare `.git` from the
# top level but an absolute path from a subdirectory, and because macOS
# temporary paths are symlinks (/var -> /private/var) while `git worktree list`
# reports resolved paths.
resolve_dir() {
  [ -d "$1" ] || return 1
  ( cd "$1" 2>/dev/null && pwd -P ) || return 1
}

GIT_DIR_RAW="$(git rev-parse --git-dir 2>/dev/null)" || exit 0
GIT_COMMON_RAW="$(git rev-parse --git-common-dir 2>/dev/null)" || exit 0
GIT_DIR_ABS="$(resolve_dir "$GIT_DIR_RAW")" || exit 0
GIT_COMMON_ABS="$(resolve_dir "$GIT_COMMON_RAW")" || exit 0
[ "$GIT_DIR_ABS" = "$GIT_COMMON_ABS" ] || exit 0

TOPLEVEL_RAW="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
TOPLEVEL="$(resolve_dir "$TOPLEVEL_RAW")" || exit 0
WORKTREE_BASE="$TOPLEVEL/.claude/worktrees"

[ -n "$LOG_FILE" ] || LOG_FILE="$TOPLEVEL/data/worktree-prune.log"

# --- helpers -----------------------------------------------------------------

say() {
  [ "$QUIET" -eq 1 ] && return 0
  if [ "$VERBOSE" -eq 1 ] || [ -t 1 ]; then
    printf '%s\n' "$1"
  fi
  return 0
}

log_lines=""
# An age-based KEEP is the expected steady state — a live worktree is simply
# young. Logging it on every session start would bury the entries a human
# actually reads, so the log is written only when something ACTIONABLE happened:
# a removal, a would-be removal, or a KEEP whose cause needs a human (locked,
# dirty, unrecognized ignored content, git refusing).
actionable=0
record() {
  log_lines="${log_lines}$1
"
  return 0
}
record_actionable() {
  actionable=$((actionable + 1))
  record "$1"
  return 0
}

# Modified within AGE_MINUTES? `find -mmin -N` is the one age primitive that
# behaves identically under BSD and GNU find.
is_fresh() {
  local p hit rc
  for p in "$@"; do
    [ -e "$p" ] || continue
    hit="$(find "$p" -maxdepth 0 -mmin "-${AGE_MINUTES}" 2>/dev/null)"
    rc=$?
    # A failed `find` must read as FRESH. Treating it as "not fresh" would make
    # every failure mode of this check argue for deletion — the opposite of the
    # posture everywhere else in this script.
    [ "$rc" -ne 0 ] && return 0
    [ -n "$hit" ] && return 0
  done
  return 1
}

# A git-status path such as "Pastura/DerivedData/" is disposable when it is a
# directory whose final component is in DISPOSABLE_COMPONENTS.
is_disposable() {
  local entry="$1" last
  case "$entry" in
    */) entry="${entry%/}" ;;
    *) return 1 ;;
  esac
  last="${entry##*/}"
  case " $DISPOSABLE_COMPONENTS " in
    *" $last "*) return 0 ;;
  esac
  return 1
}

# First ignored entry that is not build output, or empty when there is none.
blocking_ignored_entry() {
  local wt="$1" line path
  while IFS= read -r -d '' line; do
    case "$line" in
      '!! '*) path="${line#!! }" ;;
      *) continue ;;
    esac
    is_disposable "$path" && continue
    printf '%s' "$path"
    return 0
  done < <(git -C "$wt" --no-optional-locks status --porcelain -z --ignored 2>/dev/null)
  return 0
}

# --- enumerate ---------------------------------------------------------------

WORKTREE_LIST="$(git worktree list --porcelain 2>/dev/null)" || exit 0
[ -n "$WORKTREE_LIST" ] || exit 0

TMP_LIST="$(mktemp)" || exit 0
trap 'rm -f "$TMP_LIST"' EXIT
printf '%s\n\n' "$WORKTREE_LIST" > "$TMP_LIST"

removed=0
kept=0

evaluate() {
  local wt="$1" locked="$2" detached="$3"
  local name gitdir_raw gitdir fresh blocker status_out

  # (a) under the worktree base directory
  case "$wt" in
    "$WORKTREE_BASE"/*) : ;;
    *) return 0 ;;
  esac

  name="${wt##*/}"

  # (b) unnamed (Docker-style auto-generated) worktrees only
  printf '%s' "$name" | grep -Eq '^[a-z]+-[a-z]+-[0-9a-f]{6}$' || {
    [ "$VERBOSE" -eq 1 ] && say "keep  $name — named worktree (not auto-generated)"
    return 0
  }

  [ -d "$wt" ] || return 0

  # (f) age FIRST: every later check runs git against the worktree, and git
  # commands can touch its metadata. Reading age afterwards would measure this
  # script's own footprint instead of the session's.
  gitdir_raw="$(git -C "$wt" rev-parse --git-dir 2>/dev/null)"
  gitdir="$(resolve_dir "${gitdir_raw:-/nonexistent}")" || gitdir=""
  fresh=0
  if [ -n "$gitdir" ]; then
    # logs/HEAD, not logs/: appending to an existing reflog does not change the
    # containing directory's mtime, so the directory would under-report activity.
    is_fresh "$wt" "$gitdir/index" "$gitdir/HEAD" "$gitdir/logs/HEAD" && fresh=1
  else
    is_fresh "$wt" && fresh=1
  fi
  if [ "$fresh" -eq 1 ]; then
    kept=$((kept + 1))
    record "KEEP  $name — active within the last ${AGE_MINUTES}m"
    [ "$VERBOSE" -eq 1 ] && say "keep  $name — active within the last ${AGE_MINUTES}m"
    return 0
  fi

  # (g) detached HEAD — its commits belong to no ref, so removing the worktree
  # orphans them. git does NOT refuse this on its own (measured: removed without
  # --force, 0 refs and 0 reflogs afterwards), so unlike (c) and (d) this guard
  # has no backstop underneath it.
  if [ "$detached" -eq 1 ]; then
    kept=$((kept + 1))
    record_actionable "KEEP  $name — detached HEAD (commits would be orphaned)"
    [ "$VERBOSE" -eq 1 ] && say "keep  $name — detached HEAD (commits would be orphaned)"
    return 0
  fi

  # (c) locked
  if [ "$locked" -eq 1 ]; then
    kept=$((kept + 1))
    record_actionable "KEEP  $name — locked"
    [ "$VERBOSE" -eq 1 ] && say "keep  $name — locked"
    return 0
  fi

  # (d) clean working tree
  status_out="$(git -C "$wt" --no-optional-locks status --porcelain 2>/dev/null)"
  if [ -n "$status_out" ]; then
    kept=$((kept + 1))
    record_actionable "KEEP  $name — uncommitted changes"
    [ "$VERBOSE" -eq 1 ] && say "keep  $name — uncommitted changes"
    return 0
  fi

  # (e) no irreplaceable ignored content
  blocker="$(blocking_ignored_entry "$wt")"
  if [ -n "$blocker" ]; then
    kept=$((kept + 1))
    record_actionable "KEEP  $name — ignored content that is not build output: $blocker"
    [ "$VERBOSE" -eq 1 ] && say "keep  $name — ignored content that is not build output: $blocker"
    return 0
  fi

  if [ "$APPLY" -eq 1 ]; then
    # Never --force: git's own refusal on a dirty or locked worktree is the
    # backstop behind conditions (c) and (d).
    if git worktree remove "$wt" 2>/dev/null; then
      removed=$((removed + 1))
      record_actionable "REMOVED  $name"
      say "removed $name"
    else
      kept=$((kept + 1))
      record_actionable "KEEP  $name — git refused removal"
      say "keep  $name — git refused removal"
    fi
  else
    removed=$((removed + 1))
    record_actionable "WOULD-REMOVE  $name"
    say "would remove $name"
  fi
  return 0
}

current=""
locked=0
detached=0
while IFS= read -r line; do
  case "$line" in
    "worktree "*)
      current="${line#worktree }"
      locked=0
      detached=0
      ;;
    "locked"|"locked "*)
      locked=1
      ;;
    "detached")
      detached=1
      ;;
    "")
      if [ -n "$current" ]; then
        evaluate "$current" "$locked" "$detached"
      fi
      current=""
      locked=0
      detached=0
      ;;
  esac
done < "$TMP_LIST"

# --- log ---------------------------------------------------------------------
# Written only when a candidate was actually considered, so an idle run leaves
# no trace at all.
if [ "$actionable" -gt 0 ] && [ -n "$log_lines" ]; then
  log_dir="${LOG_FILE%/*}"
  if [ "$log_dir" != "$LOG_FILE" ]; then
    mkdir -p "$log_dir" 2>/dev/null || true
  fi
  mode="dry-run"
  [ "$APPLY" -eq 1 ] && mode="apply"
  {
    # Plain `date` only — its FORMAT is POSIX; it is the arithmetic flags
    # (`-d` GNU / `-v` BSD) that diverge and are banned here.
    printf '## %s (%s)\n' "$(date '+%Y-%m-%d %H:%M')" "$mode"
    printf '%s' "$log_lines"
    printf '\n'
  } >> "$LOG_FILE" 2>/dev/null || true
fi

exit 0
