#!/bin/bash
# Run xcodebuild test / build with Pastura's standard env + flags pre-applied.
#
# Usage (canonical form — cwd-independent, matches the Bash allowlist):
#   "$(git rev-parse --show-toplevel)/scripts/xcodebuild.sh" test
#   "$(git rev-parse --show-toplevel)/scripts/xcodebuild.sh" test -only-testing PasturaTests/Foo
#   "$(git rev-parse --show-toplevel)/scripts/xcodebuild.sh" test -skip-testing:PasturaUITests
#   "$(git rev-parse --show-toplevel)/scripts/xcodebuild.sh" build
#   "$(git rev-parse --show-toplevel)/scripts/xcodebuild.sh" build --tail 30
#
# Shorter convenience alias for interactive shells:
#   xcb="$(git rev-parse --show-toplevel)/scripts/xcodebuild.sh"
#   "$xcb" test -only-testing PasturaTests/Foo --tail 80
#
# Subcommand maps directly to xcodebuild's; remaining args forward
# verbatim via "$@". xcodebuild honors the last value for repeated
# single-value flags, so caller passthrough wins on duplicates (e.g.
# override the destination: `... test -destination 'platform=iOS Simulator,name=...'`).
#
# Mode-specific behavior:
#
# - `test` uses the UDID-pinned simulator destination from sim-dest.sh
#   and adds `-parallel-testing-enabled NO`. The parallel-OFF flag
#   mirrors the CI workaround for the within-process simulator-clone
#   crash cascade (200+ tests reporting failed at 0.000s on a single
#   clone PID — local Apple Silicon reproduces at ~50% on the full
#   suite). CI applies the same flag inline. Harmless for narrow TDD
#   runs since `@Suite(.serialized)` already orders within-suite tests.
#   Root-cause investigation stays in #189; this wrapper is the
#   symptom-level workaround.
#
# - `build` uses `generic/platform=iOS Simulator` (no UDID) and exports
#   `PASTURA_SKIP_SIM_WAIT=1` BEFORE sourcing sim-dest.sh so the
#   concurrent-session simulator gate is bypassed. Build artifacts are
#   architecturally identical across simulator UDIDs, so booking a
#   specific UDID wastes time and reintroduces gate contention. This
#   matches the pre-commit hook's destination choice. `$DERIVED_DATA`
#   is still populated by sim-dest.sh so build output lands in the
#   worktree-local Pastura/DerivedData/ alongside test runs.
#
# Both subcommands additionally run `sync_xcstrings` BEFORE invoking
# xcodebuild — `xcrun xcstringstool extract --modern-localizable-strings`
# + `sync` against `Pastura/Pastura/Resources/Localizable.xcstrings`.
# Closes the gap where Xcode IDE's Build action auto-extracts new
# `String(localized:)` keys but `xcodebuild build` from CLI does not
# (issue #293). Opt out with `PASTURA_SKIP_XCSTRINGS_SYNC=1` — the
# pre-commit hook in `.claude/settings.json` sets this so it does not
# mutate `Localizable.xcstrings` outside the staging index mid-commit.
# CI bypasses this code path entirely; drift is detected separately by
# the i18n leak audit (#292).
#
# Streams output directly to the terminal — no tee, no log file. Exit
# code is xcodebuild's exit code (preserved through `pipefail` when
# `--tail` is used; `set -x` xtrace is suppressed in `--tail` mode so
# the visible window stays focused on build output).
#
# For context-window-capped output in agent sessions, prefer the
# built-in `--tail N` flag — accepted at any position, consumed before
# forwarding to xcodebuild, last-wins on duplicates:
#
#   "$xcb" build --tail 30
#   "$xcb" test --tail 80
#   "$xcb" test -only-testing PasturaTests/Foo --tail 30
#
# External `| grep` for pattern-filtering still works. Do NOT pipe
# through external `| tail` — it defeats `pipefail`, so a failed
# xcodebuild reports exit 0 to the harness (see memory
# `feedback_xcodebuild_pipefail.md` for the original incident). Use
# the built-in flag instead.
#
#   "$xcb" test  ... 2>&1 | grep -E 'error:|TEST|passed|failed'
#   "$xcb" build ... 2>&1 | grep -E 'error:|warning:|BUILD'

set -euo pipefail

# Resolve repo root once so every subsequent path is absolute. Lets the
# wrapper work correctly from any cwd inside the worktree (e.g., a
# nested Pastura/PasturaTests/ subdirectory) — relative paths like
# `Pastura/Pastura.xcodeproj` would silently break under cwd shifts.
REPO_ROOT=$(git rev-parse --show-toplevel)

if [[ $# -eq 0 ]]; then
  echo 'Usage: "$(git rev-parse --show-toplevel)/scripts/xcodebuild.sh" <test|build> [--tail N] [args...]' >&2
  exit 2
fi

cmd=$1
shift

# Parse wrapper-only `--tail N` / `--tail=N` flags. xcodebuild uses
# single-dash flags (e.g. `-only-testing`), so `--`-prefixed names are
# unambiguously ours. Accepted at any position among the args; the value
# is validated as a positive integer BEFORE `shift 2`, so a missing or
# non-numeric value fails cleanly under `set -u` instead of producing a
# confusing shift-past-end abort. Duplicate `--tail` follows xcodebuild's
# own repeated-flag convention: last value wins.
tail_n=""
forwarded=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --tail)
      if [[ ! "${2-}" =~ ^[1-9][0-9]*$ ]]; then
        echo "--tail requires a positive integer (e.g. --tail 30)" >&2
        exit 2
      fi
      tail_n=$2
      shift 2
      ;;
    --tail=*)
      tail_val=${1#--tail=}
      if [[ ! "$tail_val" =~ ^[1-9][0-9]*$ ]]; then
        echo "--tail= requires a positive integer (e.g. --tail=30)" >&2
        exit 2
      fi
      tail_n=$tail_val
      shift
      ;;
    *)
      forwarded+=("$1")
      shift
      ;;
  esac
done
# Reset positional params to the forwarded args. Empty-array `+`
# expansion mirrors `extra_flags` below — bare `"${arr[@]}"` would trip
# `set -u` on macOS bash 3.2 when forwarded[] is empty.
set -- ${forwarded[@]+"${forwarded[@]}"}

case "$cmd" in
  test)
    extra_flags=(-parallel-testing-enabled NO)
    ;;
  build)
    extra_flags=()
    # build doesn't book a simulator — bypass the sim-dest.sh gate so
    # concurrent test runs from other worktrees don't block us.
    export PASTURA_SKIP_SIM_WAIT=1
    ;;
  *)
    echo "Unknown subcommand: $cmd (expected 'test' or 'build')" >&2
    exit 2
    ;;
esac

# shellcheck source=scripts/sim-dest.sh
source "$REPO_ROOT/scripts/sim-dest.sh"

if [[ "$cmd" == "build" ]]; then
  destination="generic/platform=iOS Simulator"
else
  destination="$DEST"
fi

# Auto-sync Localizable.xcstrings before xcodebuild runs. Xcode IDE's
# Build action extracts `String(localized:)` keys into the catalog
# automatically; `xcodebuild build` from CLI does not (Apple has no
# documented flag to enable it). Without this sync, new keys silently
# fail to land in the catalog after PR #288 i18n Step A-1. See #293.
#
# Behavior:
# - Skipped when `PASTURA_SKIP_XCSTRINGS_SYNC=1` (set by the pre-commit
#   hook in `.claude/settings.json` so commits do not mutate the catalog
#   outside the staging index, and available to translators editing the
#   file directly).
# - No-op if `Localizable.xcstrings` does not exist (e.g., before the
#   catalog is created in a fresh checkout pre-#288).
# - Acquires a `mkdir`-based mutex to make concurrent invocations from
#   the same worktree (e.g., test in one terminal, build in another)
#   non-racing. `mkdir` is atomic on POSIX. Stale-lock reclaim at 60s
#   covers SIGKILL-orphaned holders (sync itself takes ~0.22s on this
#   codebase, so 60s is a safe margin).
# - On failure: writes a sentinel at
#   `Pastura/DerivedData/.xcstrings-sync-failed` with timestamp + the
#   captured stderr, prints a warning, and returns 0. Build/test must
#   not be blocked by tooling failure. The sentinel persists across
#   invocations so a tail-truncated agent session that missed the
#   warning still surfaces it on the next run; cleared on next success.
# - `xcstringstool` is undocumented but stable across Xcode 15.x/16.x
#   for `extract --modern-localizable-strings` + `sync`. Treat as
#   best-effort tooling — if Apple breaks the surface in a future
#   Xcode release, the sentinel + warning catches it without breaking
#   the build.
sync_xcstrings() {
  if [[ "${PASTURA_SKIP_XCSTRINGS_SYNC:-0}" == "1" ]]; then
    return 0
  fi

  local xcstrings="$REPO_ROOT/Pastura/Pastura/Resources/Localizable.xcstrings"
  [[ -f "$xcstrings" ]] || return 0

  local sentinel_dir="$REPO_ROOT/Pastura/DerivedData"
  local sentinel="$sentinel_dir/.xcstrings-sync-failed"
  # Lock lives alongside the sentinel under `Pastura/DerivedData/` so a
  # SIGKILL-orphaned lock dir does not surface in the worktree's `git
  # status` output during the 60s stale-reclaim window — that path is
  # already gitignored.
  local lock="$sentinel_dir/.xcstrings.sync.lock"
  mkdir -p "$sentinel_dir" 2>/dev/null || return 0

  if [[ -f "$sentinel" ]]; then
    {
      echo "warning: previous xcstrings sync failed; details in"
      echo "  $sentinel"
      echo "  retrying now…"
    } >&2
  fi

  # `mkdir` is atomic — wins the race when two processes try simultaneously.
  if ! mkdir "$lock" 2>/dev/null; then
    # `stat -f %m` is BSD/macOS form. The wrapper is macOS-only by design
    # (CI bypasses it — see #189), so this is intentional. On a hypothetical
    # GNU port, swap to `stat -c %Y` or use `find "$lock" -mmin +1`.
    local lock_age
    lock_age=$(( $(date +%s) - $(stat -f %m "$lock" 2>/dev/null || echo 0) ))
    if (( lock_age > 60 )); then
      echo "warning: stale xcstrings sync lock at $lock (age ${lock_age}s); reclaiming" >&2
      rm -rf "$lock"
      mkdir "$lock" 2>/dev/null || return 0
    else
      # Active concurrent sync handles this build's needs.
      return 0
    fi
  fi

  local tmpdir
  tmpdir=$(mktemp -d) || { rm -rf "$lock"; return 0; }
  local extract_log="$tmpdir/extract.log"
  local sync_log="$tmpdir/sync.log"
  local rc=0

  if ! find "$REPO_ROOT/Pastura/Pastura" -name '*.swift' -not -path '*/DerivedData/*' -print0 \
      | xargs -0 xcrun xcstringstool extract --modern-localizable-strings \
        --output-directory "$tmpdir" 2> "$extract_log"; then
    rc=1
  fi

  if [[ "$rc" -eq 0 ]]; then
    # `nullglob` makes the array empty (rather than literal "*.stringsdata")
    # when extract produced no output — defensive against a regressed extract.
    # Assumes the caller has not enabled nullglob globally (the wrapper does
    # not; future maintainers adding nullglob elsewhere should capture/restore
    # via `shopt -p nullglob` if that changes).
    shopt -s nullglob
    local stringsdata=("$tmpdir"/*.stringsdata)
    shopt -u nullglob
    if (( ${#stringsdata[@]} > 0 )); then
      if ! xcrun xcstringstool sync "$xcstrings" --stringsdata "${stringsdata[@]}" \
          2> "$sync_log"; then
        rc=1
      fi
    fi
  fi

  if (( rc != 0 )); then
    # `$sentinel_dir` was already created at entry for the lock; safe to write.
    {
      echo "Last failure: $(date '+%Y-%m-%d %H:%M:%S')"
      if [[ -s "$extract_log" ]]; then
        echo "--- extract stderr ---"
        cat "$extract_log"
      fi
      if [[ -s "$sync_log" ]]; then
        echo "--- sync stderr ---"
        cat "$sync_log"
      fi
    } > "$sentinel" 2>/dev/null || true
    {
      echo "warning: xcstringstool extract+sync failed (continuing build/test)"
      echo "  see $sentinel for details"
    } >&2
  else
    rm -f "$sentinel"
  fi

  rm -rf "$tmpdir" "$lock"
  return 0
}

sync_xcstrings

# Build the xcodebuild command as an array so the two execution paths
# (with / without `--tail`) share a single source of truth.
# `${extra_flags[@]+"${extra_flags[@]}"}` survives `set -u` when the
# array is empty (macOS bash 3.2 quirk: bare `"${arr[@]}"` expansion
# trips `nounset` for zero-length arrays).
xcb_cmd=(
  xcodebuild "$cmd"
  -scheme Pastura
  -project "$REPO_ROOT/Pastura/Pastura.xcodeproj"
  -destination "$destination"
  -derivedDataPath "$DERIVED_DATA"
  ${extra_flags[@]+"${extra_flags[@]}"}
  "$@"
)

if [[ -n "$tail_n" ]]; then
  # Internal `| tail` preserves xcodebuild's exit code via `set -o
  # pipefail` (top of script). We deliberately suppress `set -x` here:
  # its multi-line xtrace would fold into `2>&1` and compete with build
  # output for the visible tail window, pushing real `error:` lines off
  # the bottom — the exact regression `--tail` exists to prevent.
  "${xcb_cmd[@]}" 2>&1 | tail -n "$tail_n"
else
  set -x
  "${xcb_cmd[@]}"
fi
