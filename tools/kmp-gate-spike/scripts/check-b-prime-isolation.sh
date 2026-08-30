#!/usr/bin/env bash
#
# ADR-023 §6 decision B′, as amended by the Stage-5 rulings (2026-08-30,
# #1633 / #1635 S5-1): the root Package.swift harness build and a dev
# `swift build` acquire NO XCFramework dependency — and the iOS xcodebuild
# lane acquires EXACTLY ONE, the `PasturaSharedEngine` umbrella, restored from
# a content-keyed cache (ruling (a)) with the models-only `PasturaShared`
# export dropped (ruling (b)). Before S5-1 the third clause read "not the iOS
# xcodebuild" either; check (3) below is the inverted form.
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
#   COVERED (3) pbxproj references EXACTLY ONE `.xcframework` basename and it
#                 is `PasturaSharedEngine.xcframework` — the iOS xcodebuild
#                 lane, for a framework added the way Xcode's UI adds one.
#                 Zero means the S5-1 link was lost; any other or additional
#                 name is the ADR-023 §9.7 two-umbrella landmine (a second
#                 K/N runtime linked into the same binary) or an unruled
#                 binary dependency. INVERTED at S5-1 from "declares none".
#   COVERED (4) no TRACKED `*.xcframework` under the app directory — the iOS
#                 lane again, for the path (3) structurally cannot see: the
#                 project uses `PBXFileSystemSynchronizedRootGroup`, so a
#                 framework committed inside a synchronized directory is swept
#                 into the target with NO pbxproj diff at all. Unchanged by
#                 the inversion: the one legitimate umbrella is STAGED
#                 (gitignored, `Pastura/Frameworks/*.xcframework`), never
#                 tracked, so a tracked bundle is still a violation.
#
#   NOT COVERED  an SPM *remote* package that itself declares a `.binaryTarget`.
#                 Resolving one leaves no `.xcframework` text in the pbxproj —
#                 only an `XCSwiftPackageProductDependency` plus an entry in
#                 `Package.resolved` — so no grep here can see it.
#
# That last one is not hypothetical: `llama.swift` is a live instance. Its
# manifest declares `.binaryTarget(url: ".../llama-b10327-xcframework.zip")`, so
# the iOS lane already resolves a prebuilt XCFramework — and
# `grep -c xcframework project.pbxproj` is still 0.
#
# Which is also what B′ actually means, since the invariant as worded reads
# wider than it is: the cost it protects against is ASSEMBLING the KMP
# XCFramework (~6m32s cold) on a per-PR lane, not depending on any binary
# artifact. llama.swift does not violate B′ — it is downloaded, not built.
# Post-S5-1 the iOS lane's umbrella is likewise RESTORED (content-keyed cache;
# the in-lane assembly is the cache-miss fallback, `.github/workflows/ci.yml`),
# so read checks (1)/(2) as "no SwiftPM lane acquires a dependency on the
# KMP-assembled framework" and (3)/(4) as "the iOS lane acquires exactly the
# one ruled umbrella, and only by staging".
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

# Strip Swift comments while respecting single-line string literals.
#
# A naive `s|//.*||` is wrong in a way that fails OPEN: it also truncates at the
# `//` inside a string, so a line such as
#
#     .binaryTarget(name: "X", url: "https://example.com/X.xcframework", …)
#
# loses everything from `https:` onward — and any `binaryTarget` token sitting
# after that point on the same line disappears with it. The gate then passes on
# a real violation. Tracking quote state removes that case.
#
# What it does NOT model: Swift multi-line (`"""`) and raw (`#"…"#`) string
# literals. `in_str` resets at every line boundary, so a `/*` inside a `"""`
# block is read as a real block-comment opener and everything after it is
# swallowed — including a genuine `.binaryTarget` further down the file. Rather
# than pretend to parse Swift, the scanner detects that it has lost the thread
# and exits non-zero: an unclosed block comment at EOF, or a line ending inside
# a string. The caller treats that as a hard failure, so "I could not parse this
# manifest" is fail-CLOSED rather than a silent pass.
#
# `#if` blocks are deliberately unmodelled: a `.binaryTarget` inside one still
# greps, which errs in the safe direction.
strip_swift_comments() {
  awk '
    BEGIN { in_block = 0; lost = 0 }
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
      # A line ending inside a string literal means a multi-line or raw string —
      # the shape this scanner cannot follow.
      if (in_str) { lost = 1 }
      print out
    }
    END { if (in_block || lost) { exit 3 } }
  ' "$1"
}

# GitHub resolves an annotation's `file=` RELATIVE TO THE REPOSITORY ROOT. An
# absolute path matches no tracked file, so the annotation silently degrades to
# a job-level message with no line linkage in the Files-changed view — the
# annotation still renders, which is why this is easy to ship broken. Every
# path here is built from `$REPO_ROOT`, so strip that prefix.
#
# Falls back to the raw path when the prefix does not strip: that is the
# perturbation test invoking the guard with `mktemp` paths, where the output is
# read as plain text anyway.
annotate_path() {
  case "$1" in
    "$REPO_ROOT"/*) printf '%s' "${1#"$REPO_ROOT"/}" ;;
    *) printf '%s' "$1" ;;
  esac
}

# Strip once into a file rather than piping into grep.
#
# `if strip_swift_comments … | grep -n …` fails OPEN under `set -o pipefail`:
# the pipeline reports the RIGHTMOST non-zero status, so a non-zero stripper
# turns a MATCHING grep into a false "no violation" — and would silently
# discard the fail-closed exit above. A bare redirect lets `set -e` catch the
# stripper instead.
STRIPPED="$(mktemp)"
trap 'rm -f "$STRIPPED"' EXIT

# Status 3 is the scanner's own "I lost the thread" signal. Any OTHER non-zero
# is the scanner itself breaking (an awk syntax error, a missing interpreter),
# which is fail-closed too but is a different thing to be told — and if both
# reported the same message, the perturbation test could not tell a correct
# refusal from a broken stripper.
strip_rc=0
strip_swift_comments "$MANIFEST" >"$STRIPPED" || strip_rc=$?

if [ "$strip_rc" -eq 3 ]; then
  echo "::error file=$(annotate_path "$MANIFEST")::ADR-023 decision B' guard" \
       "could not parse the manifest: it contains an unterminated block comment," \
       "or a MULTI-LINE string literal (\"\"\") the scanner does not model." \
       "(A single-line raw string such as #\"…\"# is handled and is not the" \
       "cause.) Failing closed rather than reporting a clean result it cannot" \
       "vouch for. To unblock: rewrite the literal as single-line strings, or" \
       "teach strip_swift_comments in" \
       "tools/kmp-gate-spike/scripts/check-b-prime-isolation.sh to model it and" \
       "add a case to scripts/tests/kmp-gate-isolation-test.sh."
  exit 3
elif [ "$strip_rc" -ne 0 ]; then
  echo "::error file=$(annotate_path "$MANIFEST")::ADR-023 decision B' guard's" \
       "comment stripper failed unexpectedly (exit $strip_rc) — this is a bug in" \
       "the guard, not a verdict on the manifest. Reproduce with 'bash -x" \
       "tools/kmp-gate-spike/scripts/check-b-prime-isolation.sh' and report it" \
       "against #1171."
  exit 4
fi

# fail <path> <line-or-empty> <message>
fail() {
  local loc="file=$(annotate_path "$1")"
  [ -n "$2" ] && loc="$loc,line=$2"
  echo "::error $loc::ADR-023 decision B' violated: $3"
  exit 1
}

# (1) + (2) — the two manifest-borne lanes.
#
# The hits are captured rather than piped so the first line number can go into
# the annotation. The stripper emits exactly one line per input line, so
# `$STRIPPED`'s numbering is the manifest's.
hits="$(grep -n 'binaryTarget' "$STRIPPED" || true)"
if [ -n "$hits" ]; then
  echo "$hits"
  fail "$MANIFEST" "${hits%%:*}" "the root manifest declares a .binaryTarget, so \
every per-PR 'swift build' now requires an assembled XCFramework. Keep the gate \
consumer in tools/kmp-gate-spike/Package.swift."
fi

hits="$(grep -n 'kmp-gate-spike' "$STRIPPED" || true)"
if [ -n "$hits" ]; then
  echo "$hits"
  fail "$MANIFEST" "${hits%%:*}" "the root manifest references \
tools/kmp-gate-spike. Depend on it from nowhere — the gate spike is consumed \
only by its own nested manifest."
fi

# (3) — the iOS xcodebuild lane, explicit-reference form. INVERTED at S5-1:
# the pbxproj must reference exactly one `.xcframework` basename, and it must
# be `PasturaSharedEngine.xcframework`.
#
# NOT comment-stripped, deliberately: Xcode writes its own `/* … */` annotations
# containing the file name (`… /* PasturaSharedEngine.xcframework in Frameworks */ …`),
# so stripping would DISCARD evidence here rather than avoid a false positive.
# The pbxproj has no hand-written prose comments for a stripper to protect.
#
# Fixture provenance for the perturbation test: the entry shape matched here
# was taken from commit 9f89bc3e ("W3 PR-A — XCFramework Local Drop
# integration"), which wired a real `PasturaShared.xcframework` into this same
# project, and is what S5-1 (#1635) restored under the `PasturaSharedEngine`
# name. Those lines were hand-authored (that commit's message records "all
# UUIDs prefixed E0F1A1F1... to avoid collision"), NOT emitted by Xcode — but
# they were build-verified (`xcodebuild build` SUCCEEDED, framework embedded
# and codesigned), which is the property this grep depends on: Xcode accepted
# and acted on exactly this text.
#
# Basename extraction: `-o` over `[A-Za-z0-9_.-]*\.xcframework` stops at `/`,
# so `path = Frameworks/Foo.xcframework` and `/* Foo.xcframework in … */` both
# yield `Foo.xcframework`. `-i` on the extension only: a bundle spelled
# `Foo.XCFramework` on disk would otherwise slip past, and the comparison
# below is exact, so a case-variant of the umbrella name is a *different* name
# and fails closed. The distinct set is compared as a whole rather than
# counted: "exactly one distinct name, equal to the umbrella" is one string
# comparison, and it rejects zero, a rename, and an extra name alike.
#
# `lastKnownFileType = wrapper.xcframework` is Xcode's FILE-TYPE identifier for
# the reference, not a bundle name, and every legitimate entry carries it — so
# that exact phrase is blanked before extraction. Only the phrase: a bundle
# actually named `wrapper.xcframework` would still surface through its `path =`
# and `/* … */` mentions, so the exclusion cannot hide a real second framework.
# `sed` emits one line per input line, so the `grep -n` numbers stay the
# pbxproj's. `|| [ $? -eq 1 ]` keeps grep's "no match" from aborting under
# errexit while a real grep error (exit >= 2) still does.
hits="$(sed 's/lastKnownFileType = wrapper\.xcframework//g' "$PBXPROJ" \
  | { grep -ion '[A-Za-z0-9_.-]*\.xcframework' || [ $? -eq 1 ]; })"
if [ -z "$hits" ]; then
  fail "$PBXPROJ" "" "the Xcode project references no .xcframework, so the \
S5-1 PasturaSharedEngine umbrella link is gone (ADR-023 §6 Stage 5). Restore \
the Frameworks + Embed Frameworks entries, or if the link is being removed on \
purpose, reopen ADR-023 decision B' rather than relaxing this gate."
fi
names="$(printf '%s\n' "$hits" | sed 's/^[0-9]*://' | sort -u)"
if [ "$names" != "PasturaSharedEngine.xcframework" ]; then
  echo "$hits"
  fail "$PBXPROJ" "${hits%%:*}" "the Xcode project references an .xcframework \
other than (or in addition to) PasturaSharedEngine.xcframework, so the iOS \
xcodebuild lane now links a second binary framework — the ADR-023 §9.7 \
two-umbrella landmine if it is a K/N export. Distinct names found: \
$(printf '%s' "$names" | tr '\n' ' '). Remove the reference, or if it is \
genuinely needed, reopen ADR-023 decision B' rather than relaxing this gate."
fi

# (4) — the iOS xcodebuild lane, synchronized-group form.
#
# The check (3) cannot make. `Pastura.xcodeproj` declares three
# `PBXFileSystemSynchronizedRootGroup`s (Pastura / PasturaTests / PasturaUITests),
# and a framework COMMITTED under one of those directories joins the target with
# no pbxproj entry to grep.
#
# TRACKED files only, via `git ls-files` — not `find` over the worktree. A
# worktree walk also sweeps up build output: `Pastura/DerivedData/` holds
# `llama.xcframework` after any local build, and `.build/artifacts/` holds it
# after any `swift build`. Neither is in the repository, so a `find` here is
# green on a fresh CI checkout and red on every developer machine — the worst
# split, since CI would never show it. `.claude/rules/ci-workflows.md`
# § "Rename / namespace-sweep completion gate" reaches the same tracked-only
# call for an adjacent reason — there it is the backslash-escaped-form blind
# spot and `rg` hanging on DerivedData, not this CI-green/local-red split.
if git -C "$APP_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  # No `| head -1`: git takes SIGPIPE when head closes early, and under
  # `set -o pipefail` that aborts the script with a bare 141 — red with no
  # annotation, which reads as infra noise rather than a verdict.
  TRACKED_XCF="$(git -C "$APP_DIR" ls-files -- '*.xcframework' '*.xcframework/*')"
  TRACKED_XCF="${TRACKED_XCF%%$'\n'*}"
  if [ -n "$TRACKED_XCF" ]; then
    # `ls-files` already prints paths relative to APP_DIR, so join them through
    # the repo-relative form of APP_DIR rather than its absolute one — otherwise
    # `annotate_path` cannot strip the prefix and the annotation floats.
    fail "$(annotate_path "$APP_DIR")/$TRACKED_XCF" "" \
      "a tracked .xcframework is committed under $(annotate_path "$APP_DIR"). The \
project uses PBXFileSystemSynchronizedRootGroup, so this is swept into the target \
without any pbxproj reference. Untrack it (git rm --cached) and keep frameworks \
out of the synchronized directories."
  fi
else
  echo "warning: $APP_DIR is not inside a git work tree — skipping the" \
       "tracked-framework check (4)." >&2
fi

echo "B' isolation holds: no XCFramework dependency on the SwiftPM lanes; the iOS lane links exactly PasturaSharedEngine.xcframework."
