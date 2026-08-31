#!/usr/bin/env bash
#
# scripts/kmp/probe-pattern7-isolation.sh — measure the actor isolation of the
# four Kotlin/Native-exported protocols the `App/KMP/` adapters conform to
# (ADR-023 §5 / Stage 5, slice S5-2c — issue #1647).
#
# Usage:
#   scripts/kmp/probe-pattern7-isolation.sh
#
# WHAT THIS PROVES
#   `.claude/rules/swift-isolation.md` Pattern 7: an Obj-C protocol imported
#   *unannotated* may be called by its owner from any thread, so a Swift
#   conformer compiled under `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` must be
#   declared `nonisolated` or it traps at runtime on the `@objc` thunk's
#   executor precondition. The compiler is silent either way — "it built" is not
#   evidence. This script asks the compiler to *print* each requirement's real
#   type, from the staged `PasturaSharedEngine.xcframework`, and gates on the
#   absence of `@MainActor` in the four K/N lines.
#
#   Protocols measured (requirement probed, verbatim from the staged
#   `PasturaSharedEngine.framework/Headers/PasturaSharedEngine.h`,
#   ios-arm64_x86_64-simulator slice, 2026-08-31):
#
#     LLMBackend       - (id<PSEStreamHandle>)generateStreamRequest:(PSEGenerationRequest *)request
#                          callbacks:(id<PSEStreamCallbacks>)callbacks
#                          __attribute__((swift_name("generateStream(request:callbacks:)")));
#     LanguageDetector - (NSString * _Nullable)detectText:(NSString *)text
#                          __attribute__((swift_name("detect(text:)")));
#     EngineLogger     - (void)logLevel:(PSEEngineLogLevel *)level category:(NSString *)category
#                          message:(NSString *)message privacy:(PSEEngineLogPrivacy *)privacy
#                          __attribute__((swift_name("log(level:category:message:privacy:)")));
#     RandomSource     - (uint64_t)nextUInt64 __attribute__((swift_name("nextUInt64()")));
#
#   Kotlin `ULong` exports as a plain `uint64_t` here, i.e. Swift `UInt64` — not
#   a boxed `PSEKotlinULong` — so the probe references `nextUInt64` directly.
#   Re-derive these spellings from the header, not from memory, after any bump.
#
# WHY THE CONTROL LINE IS LOAD-BEARING
#   The probe also references `UIScrollViewDelegate.scrollViewDidScroll`, a
#   known-`@MainActor` requirement. A probe that cannot redden on a genuinely
#   isolated protocol is measuring nothing — header greps "confirm" nonisolated
#   for every protocol, including MainActor ones. If the control line's printed
#   type lacks `@MainActor`, the whole run is void and the script fails.
#
# WHEN TO RE-RUN
#   After a Kotlin/KMP bump regenerates the umbrella header, after any change to
#   these four interfaces in `shared/engine`, and before relying on the
#   `nonisolated` annotation on any `App/KMP/` adapter. A finding that a
#   protocol now imports `@MainActor` is a real result: fix the adapter, do not
#   loosen this gate.
#
#   Deep rationale: `.claude/rules/swift-isolation.md` Pattern 7.
#
# Exit codes:
#   0 — all four K/N protocols import unannotated (conformers must be
#       `nonisolated`), and the control confirmed the probe can redden
#   1 — gate failed: unexpected diagnostics, a missing/extra requirement line,
#       a void control, or a K/N protocol that imports `@MainActor`
#   2 — the staged XCFramework simulator slice is absent
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Overridable so the exit-2 branch can be exercised without touching the staged
# bundle. Not a user-facing knob.
SLICE_DIR="${PASTURA_PROBE_SLICE_DIR:-$REPO_ROOT/Pastura/Frameworks/PasturaSharedEngine.xcframework/ios-arm64_x86_64-simulator}"

if [ ! -d "$SLICE_DIR/PasturaSharedEngine.framework" ]; then
  echo "error: staged simulator slice not found at:" >&2
  echo "  $SLICE_DIR/PasturaSharedEngine.framework" >&2
  echo "remedy: scripts/kmp/assemble-xcframework.sh --if-missing" >&2
  exit 2
fi

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

PROBE="$WORK_DIR/probe.swift"
cat > "$PROBE" <<'SWIFT'
// Throw-away Pattern 7 probe — never added to any target.
// Each `let _: Int = …` is an intentional type error; the compiler prints the
// requirement's real type in the diagnostic, which is the measurement.
import UIKit
import PasturaSharedEngine

nonisolated func probe(
    _ backend: any LLMBackend,
    _ detector: any LanguageDetector,
    _ logger: any EngineLogger,
    _ random: any RandomSource,
    _ control: any UIScrollViewDelegate
) {
    let _: Int = backend.generateStream // REQ:generateStream
    let _: Int = detector.detect // REQ:detect
    let _: Int = logger.log // REQ:log
    let _: Int = random.nextUInt64 // REQ:nextUInt64
    let _: Int = control.scrollViewDidScroll // REQ:scrollViewDidScroll
}
SWIFT

REQUIREMENTS=(generateStream detect log nextUInt64 scrollViewDidScroll)
# The four K/N requirements must print WITHOUT @MainActor; the control MUST
# print with it.
CONTROL_REQ=scrollViewDidScroll

SDK="$(xcrun --sdk iphonesimulator --show-sdk-path)"
OUT="$WORK_DIR/compiler.txt"
set +e
xcrun swiftc -typecheck -swift-version 6 -default-isolation MainActor \
  -target arm64-apple-ios18.0-simulator -sdk "$SDK" \
  -F "$SLICE_DIR" "$PROBE" >"$OUT" 2>&1
set -e

fail() {
  echo "PROBE FAILED: $1" >&2
  echo "--- raw compiler output ---" >&2
  cat "$OUT" >&2
  echo "--- end compiler output ---" >&2
  exit 1
}

total_errors=$(grep -c ": error: " "$OUT" || [ $? -eq 1 ])
convert_errors=$(grep -c ": error: cannot convert value of type " "$OUT" || [ $? -eq 1 ])

[ "$convert_errors" = "5" ] || fail "expected 5 'cannot convert' diagnostics, got $convert_errors"
[ "$total_errors" = "5" ] || fail "expected exactly 5 error diagnostics, got $total_errors (an unexpected diagnostic — import failure or missing member — must not pass)"

verdicts=""
lines=""
for req in "${REQUIREMENTS[@]}"; do
  probe_line=$(grep -n "// REQ:${req}\$" "$PROBE" | cut -d: -f1)
  [ -n "$probe_line" ] || fail "probe.swift has no line marked REQ:${req}"

  diag=$(grep "probe.swift:${probe_line}:" "$OUT" | grep ": error: cannot convert value of type " || [ $? -eq 1 ])
  [ -n "$diag" ] || fail "no 'cannot convert' diagnostic for ${req} (probe.swift line ${probe_line})"
  [ "$(printf '%s\n' "$diag" | wc -l | tr -d ' ')" = "1" ] || fail "more than one diagnostic keyed to ${req}"

  if [ "$req" = "$CONTROL_REQ" ]; then
    case "$diag" in
      *@MainActor*) verdicts="${verdicts}  UIScrollViewDelegate.${req} — @MainActor (control: the probe CAN redden)"$'\n' ;;
      *) fail "control ${req} printed no @MainActor — the probe is measuring nothing" ;;
    esac
  else
    case "$diag" in
      *@MainActor*) fail "${req} imports as @MainActor — a real finding; fix the App/KMP adapter, do not loosen this gate" ;;
      *) verdicts="${verdicts}  ${req} — no @MainActor: imports unannotated ⇒ Swift conformer must be nonisolated"$'\n' ;;
    esac
  fi
  lines="${lines}${diag}"$'\n'
done

echo "Pattern 7 isolation probe — staged slice:"
echo "  $SLICE_DIR"
echo
echo "Measured diagnostics (verbatim):"
printf '%s' "$lines"
echo
echo "Verdicts:"
printf '%s' "$verdicts"
echo
echo "PASS: all four K/N-exported protocols import unannotated."
