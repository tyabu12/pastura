#!/usr/bin/env bash
#
# ADR-023 §6 decision B′: "No per-PR lane acquires an XCFramework dependency —
# not the iOS xcodebuild, not the root Package.swift harness build, not a dev
# `swift build`."
#
# This is the gate LOGIC. The perturbation tests that exercise it against
# synthetic fixtures + the real files live in
# `scripts/tests/kmp-gate-isolation-test.sh` (the CI "Shell gate tests" job),
# which is why every input path is overridable below: that job runs all shell
# tests in ONE shared checkout, so a test must never mutate the real files.
#
# ## What this covers, and what it does not
#
# Stated explicitly because the previous inline version of this guard read
# broader than it was — the defect #1171 item 1 exists to fix. Do not let this
# list rot; a guard whose stated scope exceeds its real scope is worse than a
# missing one.
#
#   COVERED (1) root manifest declares no `.binaryTarget`   — the harness-build
#                 and dev-`swift build` lanes. `swift build` builds every target
#                 a manifest declares, so a binary target here bills every
#                 iOS-touching PR for an assembled XCFramework.
#   COVERED (2) root manifest does not reference the gate spike — the same two
#                 lanes, via a path dependency rather than a binary one.
#   COVERED (3) pbxproj declares no `.xcframework`          — the iOS xcodebuild
#                 lane, for a framework added the way Xcode's UI adds one.
#   COVERED (4) no `*.xcframework` exists under the app directory — the iOS lane
#                 again, for the path (3) structurally cannot see: the project
#                 uses `PBXFileSystemSynchronizedRootGroup`, so a framework
#                 dropped inside a synchronized directory is swept into the
#                 target with NO pbxproj diff at all.
#
#   NOT COVERED  an SPM *remote* package that itself declares a `.binaryTarget`.
#                 Resolving one leaves no `.xcframework` text in the pbxproj —
#                 only an `XCSwiftPackageProductDependency` plus an entry in
#                 `Package.resolved` — so no grep here can see it. The project
#                 currently resolves Yams, GRDB.swift and llama.swift; adding a
#                 binary-target-bearing package would violate B′ silently. That
#                 is a known hole, not an oversight.
#
# Checks (1) and (2) strip comments from the manifest first: a comment
# EXPLAINING that the root deliberately has no binary target must not trip the
# gate. The stripper is quote-aware on purpose — see `strip_swift_comments`.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$PACKAGE_ROOT/../.." && pwd)"

MANIFEST="$REPO_ROOT/Package.swift"
PBXPROJ="$REPO_ROOT/Pastura/Pastura.xcodeproj/project.pbxproj"
APP_DIR="$REPO_ROOT/Pastura"

usage() {
  cat <<'USAGE'
usage: check-b-prime-isolation.sh [--manifest PATH] [--pbxproj PATH] [--app-dir PATH]

Defaults point at the real files. The overrides exist for
scripts/tests/kmp-gate-isolation-test.sh, which runs the guard against
mktemp copies so it never mutates the shared CI checkout.
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --manifest) MANIFEST="$2"; shift 2 ;;
    --pbxproj)  PBXPROJ="$2";  shift 2 ;;
    --app-dir)  APP_DIR="$2";  shift 2 ;;
    -h|--help)  usage; exit 0 ;;
    *) echo "error: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

for f in "$MANIFEST" "$PBXPROJ"; do
  if [ ! -f "$f" ]; then
    echo "error: expected file is missing: $f" >&2
    exit 2
  fi
done
if [ ! -d "$APP_DIR" ]; then
  echo "error: expected directory is missing: $APP_DIR" >&2
  exit 2
fi

# Strip Swift comments while respecting string literals.
#
# A naive `s|//.*||` is wrong in a way that fails OPEN: it also truncates at the
# `//` inside a string, so a line such as
#
#     .binaryTarget(name: "X", url: "https://example.com/X.xcframework", …)
#
# loses everything from `https:` onward — and any `binaryTarget` token sitting
# after that point on the same line disappears with it. The gate then passes on
# a real violation. Tracking quote state costs ~20 lines and removes the whole
# class. Block comments are tracked across lines for the same reason.
strip_swift_comments() {
  awk '
    BEGIN { in_block = 0 }
    {
      line = $0; out = ""; i = 1; n = length(line); in_str = 0
      while (i <= n) {
        c = substr(line, i, 1); two = substr(line, i, 2)
        if (in_block) {
          if (two == "*/") { in_block = 0; i += 2 } else { i++ }
          continue
        }
        if (in_str) {
          if (c == "\\") { out = out two; i += 2; continue }
          if (c == "\"") { in_str = 0 }
          out = out c; i++; continue
        }
        if (two == "//") { break }
        if (two == "/*") { in_block = 1; i += 2; continue }
        if (c == "\"") { in_str = 1 }
        out = out c; i++
      }
      print out
    }
  ' "$1"
}

fail() {
  # `::error file=…::` renders as a GitHub annotation on the real run; harmless
  # plain text when the perturbation test invokes this with temp paths.
  echo "::error file=$1::ADR-023 decision B' violated: $2"
  exit 1
}

# (1) + (2) — the two manifest-borne lanes.
if strip_swift_comments "$MANIFEST" | grep -n 'binaryTarget'; then
  fail "$MANIFEST" "the root manifest declares a .binaryTarget, so every per-PR \
'swift build' now requires an assembled XCFramework. Keep the gate consumer in \
tools/kmp-gate-spike/Package.swift."
fi

if strip_swift_comments "$MANIFEST" | grep -n 'kmp-gate-spike'; then
  fail "$MANIFEST" "the root manifest references tools/kmp-gate-spike."
fi

# (3) — the iOS xcodebuild lane, explicit-reference form.
#
# NOT comment-stripped, deliberately: Xcode writes its own `/* … */` annotations
# containing the file name (`… /* PasturaShared.xcframework in Frameworks */ …`),
# so stripping would DISCARD evidence here rather than avoid a false positive.
# The pbxproj has no hand-written prose comments for a stripper to protect.
#
# Fixture provenance for the perturbation test: the tokens matched here were
# taken from commit 9f89bc3e ("W3 PR-A — XCFramework Local Drop integration"),
# which wired a real `PasturaShared.xcframework` into this same project. Those
# lines were hand-authored in that commit (its message records "all UUIDs
# prefixed E0F1A1F1... to avoid collision"), NOT emitted by Xcode — but they
# were build-verified there (`xcodebuild build` SUCCEEDED, framework embedded
# and codesigned), which is the property this grep depends on: Xcode accepted
# and acted on exactly this text.
if grep -n 'xcframework' "$PBXPROJ"; then
  fail "$PBXPROJ" "the Xcode project references an .xcframework, so the iOS \
xcodebuild lane now requires an assembled XCFramework."
fi

# (4) — the iOS xcodebuild lane, synchronized-group form.
#
# The check (3) cannot make. `Pastura.xcodeproj` declares three
# `PBXFileSystemSynchronizedRootGroup`s (Pastura / PasturaTests / PasturaUITests),
# and a framework dropped under one of those directories joins the target with
# no pbxproj entry to grep. Cheap `find`, so it runs unconditionally.
FOUND_XCF="$(find "$APP_DIR" -name '*.xcframework' -print -quit 2>/dev/null || true)"
if [ -n "$FOUND_XCF" ]; then
  fail "$FOUND_XCF" "an .xcframework is present under $APP_DIR. The project uses \
PBXFileSystemSynchronizedRootGroup, so this is swept into the target without any \
pbxproj reference."
fi

echo "B' isolation holds: no XCFramework dependency on any per-PR lane."
