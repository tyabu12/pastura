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
#   e. all of its ignored content is disposable — build output, or a
#      machine-local file that simply regenerates (three lists below)
#   f. nothing in the worktree or its git metadata changed in the last 12h
#   g. HEAD is attached to a branch (a detached HEAD's commits are reachable
#      from no ref, so removal would orphan them)
#
# Plus one KEEP ground outside that list: a worktree whose git directory will
# not resolve is kept outright, because the age check would otherwise fall back
# to the root mtime alone. It is reported as its own reason, and it is checked
# before (g) and (c) — so a locked worktree with a broken linkage reports the
# linkage, not the lock.
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
# argument therefore rests on (c)-(g), not on provenance. Read (b) as "nobody
# named this", not as "a routine made this". Within that set (g) is the only
# member with no git-side backstop underneath it — see below.
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
#   - Age is read from git metadata (index/HEAD/logs/HEAD) as well as the worktree
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
# each KEEP, which is how these lists are tuned: run dry for a few nights, read
# the log, then add only what is provably build output OR provably machine-local
# and regenerable. Widening is what makes a removal unrecoverable, so a blocker
# that dominates the log is a finding about what routine worktrees accumulate,
# not licence to widen reflexively.
#
# That procedure has now run once. Recording what it produced, because the
# previous version of this section predicted the wrong things:
#   - The first blocker was `.claude/probe-instructions-hook.sh`, unanticipated
#     here. It was dead residue from a one-off probe, ignored only through one
#     clone's `.git/info/exclude` — cleaned up at the source rather than
#     allowlisted, because on any other clone it is not ignored at all and
#     condition (d) stops the worktree instead. Prefer that resolution: residue
#     is temporary, an allowlist entry is permanent.
#   - `data/` was predicted and never appeared. `queue-consumer`'s
#     `append_digest.py` resolves its digest to the MAIN checkout via
#     `--git-common-dir`, so a worktree's `data/` stays empty. That is specific
#     to routines resolving that way — `scenario-factory`'s takes `--digest`
#     from its caller — so a factory worktree blocking on `data/` later is
#     expected, not a contradiction.
#
# WHY `.claude/settings.local.json` IS DISPOSABLE — and what that is NOT saying
# Claude Code writes permission grants there, which is why an earlier version of
# this section listed it as deliberately non-disposable. The correction is to
# the inference, not to that fact. The three observed worktree copies measured
# byte-identical to the main checkout's — but that is evidence about three
# instances, while this rule matches on PATH, unconditionally, with no runtime
# content check. A session that grants a permission inside a worktree diverges
# its copy, and this deletes it anyway.
# What licenses the entry is BOUNDED LOSS: worst case, any local settings edit
# made inside a STALE worktree is lost — a permission grant re-prompts, and
# hook wiring / env / plugin enablement there governed only that dead worktree's
# sessions. The main checkout's copy is never a candidate: this script
# self-gates to the main checkout and only ever removes paths under
# `.claude/worktrees/`. Contrast `data/queue/digest.md`, which is
# unrecoverable. Do NOT restate this as "it dies with the worktree anyway" —
# condition (e) exists precisely to stop a worktree dying while it holds
# content, so that reasoning is circular.
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
# the log file instead. Nothing in this repository wires that hook: see the
# "Automated hooks" bullet under CLAUDE.md's "Swift Coding Conventions", which
# directs it to your own untracked .claude/settings.local.json.
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

# Three exact-match lists, never globs, so anything unrecognized fails toward
# KEEP. Which list applies is decided by the trailing slash git puts on
# directories in `--ignored` porcelain output — see is_disposable.
#
# "Never globs" rests on the QUOTING at those match sites, not on the strings
# happening to be plain: `case " $LIST " in *" $entry "*)` interpolates
# untrusted path text into a glob pattern, and only the double quotes keep it
# literal (verified on bash 3.2 with `entry` set to `*` and to a `?`-bearing
# path). Unquoting `$entry`, or moving to an unquoted `[[ == ]]`, silently
# turns an observed filename into a wildcard.
#
# Directories, matched on the final path component, mirroring the bare-pattern
# semantics of .gitignore's own `build/`, `DerivedData/` and `.build/` rules
# (which match at any depth).
DISPOSABLE_COMPONENTS="build DerivedData .build .gradle node_modules PasturaShared.xcframework"
# Files, matched on the full repo-relative path. Deliberately not by basename:
# a copy of this filename somewhere else in the tree is not the same file and
# must keep blocking. See § "WHY .claude/settings.local.json IS DISPOSABLE".
DISPOSABLE_FILES=".claude/settings.local.json"
# Files matched on basename alone, for names that legitimately appear at any
# depth. `.DS_Store` is Finder metadata and is unanchored in .gitignore too, so
# the semantics agree; it cannot hold anything a human would miss.
DISPOSABLE_BASENAMES=".DS_Store"

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
      # A bare digit test is not enough: `0`, `00` and `08` all pass it, and
      # `find -mmin -00` matches nothing — condition (f) would be disabled for
      # the whole run, the exact failure this validation exists to prevent.
      # `10#` normalises the value and stops `08`/`09` reading as bad octal.
      case "${1:-}" in
        *[!0-9]*|"") printf 'prune-stale-worktrees: --age-minutes needs an integer >= 1\n' >&2; exit 0 ;;
      esac
      if [ "$((10#$1))" -lt 1 ]; then
        printf 'prune-stale-worktrees: --age-minutes needs an integer >= 1\n' >&2
        exit 0
      fi
      AGE_MINUTES="$((10#$1))"
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
    # A failed `find` must read as FRESH: every failure mode of this check has
    # to argue for keeping, never for deleting. The (d) and (e) git calls below
    # carry the same return-code handling, for the same reason.
    [ "$rc" -ne 0 ] && return 0
    [ -n "$hit" ] && return 0
  done
  return 1
}

# Is a git-status path such as "Pastura/DerivedData/" or ".claude/skills/.DS_Store"
# disposable? The trailing slash is the ONLY arm selector — git's `--ignored`
# porcelain guarantees it on directories — so a directory that happens to be
# named `.DS_Store/` takes the directory arm and can never reach the basename
# rule below.
is_disposable() {
  local entry="$1" last
  case "$entry" in
    */)
      entry="${entry%/}"
      last="${entry##*/}"
      case " $DISPOSABLE_COMPONENTS " in
        *" $last "*) return 0 ;;
      esac
      return 1
      ;;
  esac

  case " $DISPOSABLE_FILES " in
    *" $entry "*) return 0 ;;
  esac
  last="${entry##*/}"
  case " $DISPOSABLE_BASENAMES " in
    *" $last "*) return 0 ;;
  esac
  return 1
}

# First ignored entry that is not disposable, or empty when there is none.
# Returns 2 when the enumeration itself failed, so the caller cannot read a
# git error as "nothing irreplaceable here". This one matters more than the
# others: `git worktree remove` is blind to ignored files, so (e) has no
# git-side backstop — a swallowed error here destroys exactly the class the
# condition exists to protect. A temp file rather than a pipeline because the
# producer's exit status has to survive, and `$(...)` cannot carry NUL bytes.
blocking_ignored_entry() {
  local wt="$1" tmpfile="$2" line path
  if ! git -C "$wt" --no-optional-locks status --porcelain -z --ignored \
       > "$tmpfile" 2>/dev/null; then
    return 2
  fi
  # Same posture on the read side. Practically unreachable — the write above
  # just succeeded — but an unreadable scratch file would yield an empty loop
  # and hence "nothing irreplaceable", which is the reading this whole function
  # exists to prevent.
  [ -r "$tmpfile" ] || return 2
  while IFS= read -r -d '' line; do
    case "$line" in
      '!! '*) path="${line#!! }" ;;
      *) continue ;;
    esac
    is_disposable "$path" && continue
    printf '%s' "$path"
    return 0
  done < "$tmpfile"
  return 0
}

# --- enumerate ---------------------------------------------------------------

WORKTREE_LIST="$(git worktree list --porcelain 2>/dev/null)" || exit 0
[ -n "$WORKTREE_LIST" ] || exit 0

TMP_LIST="$(mktemp)" || exit 0
TMP_IGNORED="$(mktemp)" || exit 0
trap 'rm -f "$TMP_LIST" "$TMP_IGNORED"' EXIT
printf '%s\n\n' "$WORKTREE_LIST" > "$TMP_LIST"

removed=0
kept=0

evaluate() {
  local wt="$1" locked="$2" detached="$3"
  local name gitdir_raw gitdir fresh blocker blocker_rc status_out

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
    # Falling back to the worktree root alone is the proxy this script exists
    # not to trust — measured days staler than the git metadata. An
    # unresolvable git linkage is the state where caution matters most, so
    # refuse rather than degrade.
    kept=$((kept + 1))
    record_actionable "KEEP  $name — could not resolve its git directory"
    [ "$VERBOSE" -eq 1 ] && say "keep  $name — could not resolve its git directory"
    return 0
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
  if ! status_out="$(git -C "$wt" --no-optional-locks status --porcelain 2>/dev/null)"; then
    kept=$((kept + 1))
    record_actionable "KEEP  $name — git status failed"
    [ "$VERBOSE" -eq 1 ] && say "keep  $name — git status failed"
    return 0
  fi
  if [ -n "$status_out" ]; then
    kept=$((kept + 1))
    record_actionable "KEEP  $name — uncommitted changes"
    [ "$VERBOSE" -eq 1 ] && say "keep  $name — uncommitted changes"
    return 0
  fi

  # (e) no irreplaceable ignored content
  blocker="$(blocking_ignored_entry "$wt" "$TMP_IGNORED")"
  blocker_rc=$?
  if [ "$blocker_rc" -ne 0 ]; then
    kept=$((kept + 1))
    record_actionable "KEEP  $name — could not enumerate ignored content"
    [ "$VERBOSE" -eq 1 ] && say "keep  $name — could not enumerate ignored content"
    return 0
  fi
  if [ -n "$blocker" ]; then
    kept=$((kept + 1))
    record_actionable "KEEP  $name — ignored content that is not disposable: $blocker"
    [ "$VERBOSE" -eq 1 ] && say "keep  $name — ignored content that is not disposable: $blocker"
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

if [ "$VERBOSE" -eq 1 ] && [ $((removed + kept)) -gt 0 ]; then
  if [ "$APPLY" -eq 1 ]; then
    say "-- $removed removed, $kept kept"
  else
    say "-- $removed would be removed, $kept kept"
  fi
fi

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
