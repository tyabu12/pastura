#!/usr/bin/env bash
#
# scripts/kmp/assemble-xcframework.sh — assemble the `PasturaSharedEngine`
# XCFramework from `shared/engine` and stage it where a Swift consumer can
# resolve it (ADR-023 §6 Stage 5, slice S5-1 — issue #1635).
#
# Usage:
#   scripts/kmp/assemble-xcframework.sh [--config debug|release] [--dest <dir>]
#                                       [--if-missing] [-h|--help]
#
#   --config   debug (default) or release. Selects the Gradle task infix and
#              the `shared/engine/build/XCFrameworks/<config>/` source path.
#   --dest     directory to stage into (default: `Pastura/Frameworks` under the
#              repo root). The staged bundle is always named
#              `PasturaSharedEngine.xcframework`.
#   --if-missing  the wrapper-facing form (ADR-023 §6 (a) names this flag): passes
#              `--quiet` to Gradle and drops the trailing size line, so an
#              UP-TO-DATE run prints only the two `==>` progress lines. It does
#              NOT skip Gradle when the bundle already exists — see "no mtime
#              short-circuit" below.
#
# Exit codes:
#   0 — success (assembled, or already UP-TO-DATE); also the no-op when
#       `shared/engine/build.gradle.kts` is absent from the checked-out ref
#   1 — missing tool (JDK 17+ / gradlew)
#   2 — Gradle assemble failed
#   3 — copy / atomic-rename failed
#  64 — unknown flag (usage error, EX_USAGE)
#
# WHY ONE SCRIPT, AND WHY `--dest` SURVIVES ONE CONSUMER
#   ADR-023 §6 ruling (b) settled on a *single* umbrella: `PasturaSharedEngine`
#   re-exports `shared/models`, and the models-only `PasturaShared` export is
#   dropped rather than retargeted. Since S5-5 retired the Stage-2 gate spike
#   there is also a single CONSUMER — the iOS app — so `--dest` has one
#   caller-visible default and no second staging site. It stays a flag because
#   the alternative, a second script for any future consumer, is what the
#   original two-consumer note argued against: two scripts assembling the same
#   umbrella drift on a Gradle task rename, a moved output path, or a JDK-probe
#   fix applied to one and not the other, and the failure mode is a stale
#   staged framework that still links.
#
# WHY DEBUG IS THE DEFAULT
#   Mirrors the per-PR choice in `.github/workflows/ci.yml` (the
#   `…EngineDebugXCFramework` step): K/N release links run full LLVM
#   optimization and dominate the cost, while the `export` / API-dependency
#   errors this assembly exists to catch fire identically on debug. The
#   both-config assembly runs nightly, off the critical path.
#
# WHY `--if-missing` DOES NOT SHORT-CIRCUIT ON THE FILESYSTEM
#   An earlier draft (spike branch, W3 PR-A) checked `Info.plist` mtime plus a
#   `git diff` over `shared/`, and both leaked silent-stale scenarios: a
#   post-`git pull` stale `Info.plist`, and a new `.kt` file invisible to a
#   two-file mtime check. Gradle's own UP-TO-DATE check is the authoritative
#   fast path, so this script always invokes Gradle and lets it decide.
#
#   Measured warm no-op for the *engine* umbrella (2026-08-30, local
#   `--no-daemon` run, second of two back-to-back invocations): ~7s wall
#   (Gradle reports `BUILD SUCCESSFUL in 7s`, 4 of 24 tasks executed — the
#   umbrella-assembly task itself is not UP-TO-DATE-able — plus the 76 MB copy).
#   The spike-era header's "~1-2s" was the models-only umbrella with a warm
#   Gradle daemon — do not carry that number forward.
#
# JDK 17 IS AN iOS-BUILD PREREQUISITE
#   Once PR-B of #1635 wires `--if-missing` into `scripts/xcodebuild.sh`, an
#   iOS build cannot complete without a JDK 17+ toolchain. This script says so
#   explicitly and exits 1 — it must never fail silently (ADR-023 §6 (a),
#   "dev iOS lane").
#
# Atomic staging: the Gradle output is copied to a sibling temp directory, the
# old bundle is moved aside, and the new one is `mv`'d into place (same
# filesystem ⇒ each rename is atomic). The trap is restore-aware: on any exit,
# signal included, it puts the aside copy back if the destination is missing,
# so an abort leaves either the previous bundle or the new one — never a
# half-copied `.xcframework`, and never a deleted destination. The temp and
# aside names end in `.xcframework` so the `Pastura/Frameworks/*.xcframework`
# gitignore glob covers an aborted run. Copy-then-swap rather than a bare `mv`
# from the build dir keeps the staged copy independent of Gradle's
# rebuild-then-delete cycle.

set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: scripts/kmp/assemble-xcframework.sh [options]

  --config debug|release   build configuration (default: debug)
  --dest <dir>             staging directory (default: <repo>/Pastura/Frameworks)
  --if-missing             quiet mode (Gradle --quiet, no size line); still runs
                           Gradle and relies on its UP-TO-DATE fast path
  -h, --help               show this help

Exit codes: 0 ok · 1 missing tool · 2 Gradle failure · 3 copy/rename failure · 64 usage
USAGE
}

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

CONFIG="debug"
DEST_DIR=""
IF_MISSING=0

while [ $# -gt 0 ]; do
  case "$1" in
    --config)
      [ $# -ge 2 ] || { echo "error: --config requires an argument" >&2; usage >&2; exit 64; }
      CONFIG="$2"
      shift 2
      ;;
    --config=*) CONFIG="${1#--config=}"; shift ;;
    --dest)
      [ $# -ge 2 ] || { echo "error: --dest requires an argument" >&2; usage >&2; exit 64; }
      DEST_DIR="$2"
      shift 2
      ;;
    --dest=*) DEST_DIR="${1#--dest=}"; shift ;;
    --if-missing) IF_MISSING=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *)
      echo "error: unknown argument '$1'" >&2
      usage >&2
      exit 64
      ;;
  esac
done

case "$CONFIG" in
  debug) GRADLE_TASK=":shared:engine:assemblePasturaSharedEngineDebugXCFramework" ;;
  release) GRADLE_TASK=":shared:engine:assemblePasturaSharedEngineReleaseXCFramework" ;;
  *)
    echo "error: unknown configuration '$CONFIG' (expected 'debug' or 'release')" >&2
    usage >&2
    exit 64
    ;;
esac

DEST_DIR="${DEST_DIR:-$REPO_ROOT/Pastura/Frameworks}"
DEST="$DEST_DIR/PasturaSharedEngine.xcframework"
SOURCE="$REPO_ROOT/shared/engine/build/XCFrameworks/$CONFIG/PasturaSharedEngine.xcframework"

# Branch-switch guard: the pre-commit hook and `scripts/xcodebuild.sh` call this
# unconditionally once wired, but a ref without `shared/engine/` (an old branch,
# a bisect) has no Gradle task to run. No-op exit 0 rather than a Gradle "task
# not found" — consistent with how `scripts/xcodebuild.sh` skips a missing
# xcstrings sync.
if [ ! -f "$REPO_ROOT/shared/engine/build.gradle.kts" ]; then
  echo "==> shared/engine/build.gradle.kts absent on this ref — nothing to assemble."
  exit 0
fi

# JDK probe. Gradle needs JDK 17+; `shared/engine/build.gradle.kts` pins
# `jvmTarget` to 17 (bytecode only), so any LTS at or above 17 works. CI uses
# `actions/setup-java` 17 for parity.
if ! command -v java >/dev/null 2>&1; then
  echo "error: java not found — JDK 17+ is required to build the KMP umbrella." >&2
  echo "       Install: brew install --cask temurin@17" >&2
  exit 1
fi

# `java -version` writes to stderr, as `openjdk version "17.0.x" ...`,
# `openjdk version "21" ...`, or legacy `java version "1.8.0_x"`. Two traps:
# (1) macOS ships a `/usr/bin/java` stub that satisfies `command -v` but exits
#     1 with "Unable to locate a Java Runtime" — under `pipefail` that status
#     would abort the script before the diagnostic below, so the status is
#     neutralized with `|| true` and the raw output is kept for the message.
# (2) `JAVA_TOOL_OPTIONS` / `_JAVA_OPTIONS` prepend a "Picked up ..." line, so
#     the version line is selected by content, not by position.
JAVA_RAW="$(java -version 2>&1 || true)"
JAVA_VERSION="$(printf '%s\n' "$JAVA_RAW" | grep -m1 -E 'version "' | sed -E 's/.*version "([0-9]+)(\.[0-9]+)?.*/\1/' || true)"
if [ "${JAVA_VERSION:-}" = "1" ]; then
  # Legacy `1.8.0_x` scheme: report the JDK the user actually has.
  JAVA_VERSION="$(printf '%s\n' "$JAVA_RAW" | grep -m1 -E 'version "' | sed -E 's/.*version "1\.([0-9]+).*/\1/' || true)"
fi
if ! [[ "${JAVA_VERSION:-}" =~ ^[0-9]+$ ]] || [ "$JAVA_VERSION" -lt 17 ]; then
  echo "error: JDK 17 or newer required, found JDK ${JAVA_VERSION:-unknown}." >&2
  echo "       java -version said: $(printf '%s\n' "$JAVA_RAW" | head -1)" >&2
  echo "       Install: brew install --cask temurin@17" >&2
  echo "       Or set JAVA_HOME: export JAVA_HOME=\$(/usr/libexec/java_home -v 17)" >&2
  exit 1
fi

if [ ! -x "$REPO_ROOT/gradlew" ]; then
  echo "error: gradlew not found or not executable at $REPO_ROOT/gradlew" >&2
  exit 1
fi

GRADLE_FLAGS=(--no-daemon)
[ "$IF_MISSING" -eq 1 ] && GRADLE_FLAGS+=(--quiet)

echo "==> Assembling $GRADLE_TASK"
if ! (cd "$REPO_ROOT" && ./gradlew "$GRADLE_TASK" "${GRADLE_FLAGS[@]}"); then
  echo "error: Gradle assemble failed. Re-run with --stacktrace for diagnostics:" >&2
  echo "       ./gradlew $GRADLE_TASK --no-daemon --stacktrace" >&2
  exit 2
fi

if [ ! -d "$SOURCE" ]; then
  echo "error: Gradle reported success but '$SOURCE' is missing." >&2
  echo "       The XCFramework output path may have moved — check" >&2
  echo "       shared/engine/build.gradle.kts and update this script." >&2
  exit 3
fi

echo "==> Staging into $DEST"
mkdir -p "$DEST_DIR"
TEMP_DEST="$DEST_DIR/.PasturaSharedEngine.tmp.$$.xcframework"
ASIDE="$DEST_DIR/.PasturaSharedEngine.old.$$.xcframework"
# Restore-aware cleanup. Between "move aside" and "rename into place" the aside
# copy is the ONLY previous bundle, so the handler must put it back before
# deleting anything; if that restore itself fails, the aside is left in place
# and named, never removed. INT/TERM re-raise the conventional exit codes.
cleanup_staging() {
  rm -rf "$TEMP_DEST"
  if [ -e "$ASIDE" ]; then
    if [ ! -e "$DEST" ]; then
      if ! mv "$ASIDE" "$DEST"; then
        echo "error: could not restore the previous bundle — it is at $ASIDE" >&2
        return 0
      fi
    fi
    rm -rf "$ASIDE"
  fi
}
trap 'cleanup_staging' EXIT
trap 'cleanup_staging; trap - EXIT; exit 130' INT
trap 'cleanup_staging; trap - EXIT; exit 143' TERM

rm -rf "$TEMP_DEST" "$ASIDE"
cp -R "$SOURCE" "$TEMP_DEST" || { echo "error: copy failed" >&2; exit 3; }
if [ -e "$DEST" ]; then
  mv "$DEST" "$ASIDE" || { echo "error: could not move the previous bundle aside" >&2; exit 3; }
fi
if ! mv "$TEMP_DEST" "$DEST"; then
  echo "error: atomic rename failed — restoring the previous bundle" >&2
  exit 3
fi
rm -rf "$ASIDE"
trap - EXIT INT TERM

if [ "$IF_MISSING" -eq 1 ]; then
  exit 0
fi

SIZE="$(du -sh "$DEST" 2>/dev/null | cut -f1)"
echo "==> Done. PasturaSharedEngine.xcframework ready at $DEST (${SIZE:-unknown})"
