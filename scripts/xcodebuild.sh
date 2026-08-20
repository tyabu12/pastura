#!/bin/bash
# Run xcodebuild test / build with Pastura's standard env + flags pre-applied.
#
# Usage (run from the repository root — matches the Bash allowlist):
#   scripts/xcodebuild.sh test
#   scripts/xcodebuild.sh test -only-testing PasturaTests/Foo
#   scripts/xcodebuild.sh test -skip-testing:PasturaUITests
#   scripts/xcodebuild.sh build
#   scripts/xcodebuild.sh build --tail 30
#
# The wrapper resolves REPO_ROOT internally, so running from a
# subdirectory still produces correct paths — but agent-issued
# invocations must use the cwd-relative form above to match the
# allowlist (`Bash(scripts/xcodebuild.sh*)`); a `$()`-bearing form
# triggers an approval dialog regardless of the allowlist
# (anthropics/claude-code#31373).
#
# Caller passthrough / flag override:
#
# Subcommand maps directly to xcodebuild's; remaining args forward
# verbatim via "$@". The wrapper supplies `-scheme`, `-project`,
# `-derivedDataPath` and `-destination` itself, and re-passing any of them is
# now REJECTED up front rather than documented — see the guard above
# `case "$cmd"`, which carries the reason per flag. The one exception is
# `-destination` on `build`, still accepted so the device compile-check recipe
# works: `scripts/xcodebuild.sh build -destination 'generic/platform=iOS'
# CODE_SIGNING_ALLOWED=NO`. To pin a single simulator for `test`, export
# PASTURA_SIM_NAME.
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
#   scripts/xcodebuild.sh build --tail 30
#   scripts/xcodebuild.sh test --tail 80
#   scripts/xcodebuild.sh test -only-testing PasturaTests/Foo --tail 30
#
# External `| grep` for pattern-filtering still works. Do NOT pipe
# through external `| tail` — it defeats `pipefail`, so a failed
# xcodebuild reports exit 0 to the harness. Use the built-in flag
# instead.
#
#   scripts/xcodebuild.sh test  ... 2>&1 | grep -E 'error:|TEST|passed|failed'
#   scripts/xcodebuild.sh build ... 2>&1 | grep -E 'error:|warning:|BUILD'

set -euo pipefail

# Resolve repo root once so every subsequent path is absolute. Lets the
# wrapper work correctly from any cwd inside the worktree (e.g., a
# nested Pastura/PasturaTests/ subdirectory) — relative paths like
# `Pastura/Pastura.xcodeproj` would silently break under cwd shifts.
REPO_ROOT=$(git rev-parse --show-toplevel)

if [[ $# -eq 0 ]]; then
  echo 'Usage: scripts/xcodebuild.sh <test|build> [--tail N] [args...]' >&2
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

# Reject flags the wrapper already supplies, BEFORE anything slow runs: below
# this point `test` sources sim-dest.sh, whose gate polls up to 900 s, so a
# rejection placed later costs a quarter-hour before printing one line.
#
# Arms are per-flag because xcodebuild's own handling differs. It rejects a
# repeated `-scheme` / `-project` / `-derivedDataPath` itself, but between the
# xtrace and a full usage page, which reads like a wrapper bug.
#
# The `=`-joined form is the one worth a guard: xcodebuild takes it, exits 0, and
# DROPS the flag. Measured on Xcode 26.6 for `-derivedDataPath=` alone and pinned
# by no test here, so re-run the pair on a new Xcode rather than trusting this:
# `-showBuildSettings … -derivedDataPath=/tmp/x` reports BUILD_DIR under
# ~/Library/…/DerivedData, the space-separated control /tmp/x/Build/Products.
# For the three above the drop is merely inert — the wrapper supplies its own
# value anyway; `-destination=` is where inert turns dangerous, see its arm below.
#
# A second bare `-destination` is ADDITIVE, so `test` would run on both devices
# with either failure aborting; `build` keeps accepting the space form for the
# device compile-check recipe.
for _arg in "$@"; do
  case "$_arg" in
    -scheme|-project|-derivedDataPath)
      echo "$_arg is supplied by this wrapper — drop it (xcodebuild accepts it only once)." >&2
      exit 2
      ;;
    -scheme=*|-project=*|-derivedDataPath=*)
      echo "${_arg%%=*} takes a SPACE-separated value; the \`=\` form is silently ignored." >&2
      echo "  It is also supplied by this wrapper already — drop the flag." >&2
      exit 2
      ;;
    -destination=*)
      # Rejected for BOTH subcommands, unlike the bare form below. The `=` shape
      # is dropped here too, and `build` is where it bites: the documented device
      # compile-check recipe IS a `build -destination …`, so an `=` there silently
      # loses the device slice, builds the simulator one, and still prints
      # `** BUILD SUCCEEDED **` — the exact false green that recipe exists to
      # prevent.
      echo "-destination takes a SPACE-separated value; the \`=\` form is silently dropped." >&2
      echo "  On \`build\` that loses the device slice while still printing BUILD SUCCEEDED." >&2
      exit 2
      ;;
    -destination)
      if [[ "$cmd" == "test" ]]; then
        echo "-destination is additive for \`test\`: xcodebuild would run the suite on the" >&2
        echo "  wrapper's simulator AND yours, and a failure on either aborts the run." >&2
        echo "  To pin ONE simulator:  export PASTURA_SIM_NAME=\"iPhone 17 Pro Max\"" >&2
        exit 2
      fi
      ;;
  esac
done

case "$cmd" in
  test)
    extra_flags=(-parallel-testing-enabled NO)
    # Integration suites (Ollama, llama.cpp) gate on an env var read by the TEST
    # RUNNER, and a runner is a separate process that does NOT inherit what was
    # exported here — the suite skips while xcodebuild still prints
    # `** TEST SUCCEEDED **`. Nothing else says so, hence this line. The scheme's
    # LaunchAction > EnvironmentVariables is the surface that works.
    #
    # ADVISORY, not a gate: `|| [ $? -eq 1 ]` keeps grep's no-match (exit 1,
    # the common case) from aborting under errexit while still letting a real
    # grep error (exit >= 2) abort. A gate would want the opposite — a broken
    # pattern there must never read as "nothing found". Capture, never
    # `grep -q`: an early-exiting reader under `pipefail` turns a match into a
    # failure. `env` lists exported variables only, which is exactly the set
    # that could have been meant for the runner.
    _integration_vars="$(env | { grep -E '^[A-Za-z_][A-Za-z0-9_]*_INTEGRATION=' || [ $? -eq 1 ]; })"
    if [[ -n "$_integration_vars" ]]; then
      {
        echo "warning: *_INTEGRATION set in this shell, but CLI env vars do NOT reach the"
        echo "  test runner — the suite will skip and still report TEST SUCCEEDED."
        printf '%s\n' "$_integration_vars" | sed 's/^/    /'
        echo "  Enable it in the scheme instead (LaunchAction > EnvironmentVariables)."
      } >&2
    fi
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

# Resolve SPM dependencies up front when this DerivedData has none. A fresh
# worktree gets an empty Pastura/DerivedData/, and the first xcodebuild there
# dies at package resolution — which the pre-commit hook then reports as
# `Build failed. Fix compile errors before committing.`, sending the reader
# after a compile error that does not exist.
#
# The predicate is "nothing was ever resolved into this DerivedData", not "the
# state file is missing": a FAILED resolve still writes workspace-state.json with
# no `"identity"` anywhere, so keying on existence would skip the retry of the
# very case this exists for (measured in #1503 — that failure happened here, with
# the file already present). It does NOT cover a resolution that is stale or
# PARTIAL rather than absent (a `Package.resolved` bump, a moved revision, some
# but not all of this tree's dependencies resolving): an identity is present in
# all of those, the pre-flight stays quiet, and the build fails as it does today
# — widen it only with a case that reproduces. Cost: a grep over one small file
# on a warm tree; ~23 s once on a cold one, which the build was going to spend on
# resolution anyway.
#
# Rot direction, should Apple stop emitting `"identity"`: every invocation
# resolves. That is the loud failure (~23 s per TDD cycle, and the stderr line
# below prints every time) rather than the silent one, which is the right way
# round. Its only CI consumer is `.github/workflows/codeql.yml`, which is
# cron-only — so a regression here surfaces on an unwatched nightly, not on a PR.
_spm_state="$DERIVED_DATA/SourcePackages/workspace-state.json"
_spm_resolved=""
if [[ -f "$_spm_state" ]]; then
  # `|| [ $? -eq 1 ]` because errexit is in force: grep's exit 1 is the "no
  # identities, resolve now" answer, not a failure. It stays narrower than
  # `|| true` so a real grep error (exit >= 2) still aborts rather than being
  # read as "unresolved". No pipeline here, so the SIGPIPE hazard behind the
  # `_integration_vars` capture (the `env | grep` one, earlier in this file) does
  # NOT apply — don't generalize this site into a rule about pipefail.
  _spm_resolved="$({ grep '"identity"' "$_spm_state" || [ $? -eq 1 ]; })"
fi
if [[ -z "$_spm_resolved" ]]; then
  echo "pre-flight: no resolved SPM packages in $DERIVED_DATA — resolving first." >&2
  # Explicit `if !` rather than a bare call: errexit is in force here, and a
  # resolve failure must stay advisory. Letting the build run anyway keeps this
  # from adding a failure path of its own — and the build's own error is what
  # the operator needs to see, now with the real cause named above it.
  if ! xcodebuild -resolvePackageDependencies \
      -project "$REPO_ROOT/Pastura/Pastura.xcodeproj" \
      -scheme Pastura \
      -derivedDataPath "$DERIVED_DATA" \
      -quiet; then
    {
      echo "warning: -resolvePackageDependencies failed."
      echo "  If the build below dies at 'Could not resolve package dependencies',"
      echo "  that is a DEPENDENCY RESOLUTION failure, not a compile error."
    } >&2
  fi
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
