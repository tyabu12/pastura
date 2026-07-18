#!/usr/bin/env bash
#
# scripts/tests/kmp-gate-isolation-test.sh — perturbation tripwire for the
# ADR-023 decision B′ isolation guard
# (tools/kmp-gate-spike/scripts/check-b-prime-isolation.sh).
#
# CI-wired: the `*-test.sh` naming convention makes this a gate under the
# .github/workflows/ci.yml "Shell gate tests" job ("Run scripts/tests/*-test.sh").
# Pure bash + awk + grep + find — no Swift toolchain, which that ubuntu job does
# not have, so nothing here may invoke `swift build` to validate a manifest.
#
# Why perturbation rather than a "the real files are clean" assertion: the real
# files ARE clean (0 hits today), so a vacuous guard — one whose regex matches
# nothing that could ever appear — passes identically to a working one. Only a
# positive control proves the guard fires. Every case below therefore states
# which lane it stands for, and the NEGATIVE cases matter as much as the
# positive ones: this guard's failure mode of record (#1171) was a false
# POSITIVE on a comment that merely mentioned the forbidden token.
#
# IMPORTANT — this test must never mutate the checkout. The shell-tests job runs
# all scripts/tests/*-test.sh sequentially in ONE shared clone under `bash -e`;
# an in-place edit of Package.swift or project.pbxproj that a mid-test failure
# left behind would poison every later test in the job. All fixtures are built
# in `$TMP` and passed via the guard's --manifest / --pbxproj / --app-dir
# overrides, which exist for exactly this reason.
#
# Scaffold (tempdir + `trap rm EXIT` + `fail=0` accumulator) follows
# scripts/tests/demo-replay-event-coverage-test.sh.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
GUARD="$REPO_ROOT/tools/kmp-gate-spike/scripts/check-b-prime-isolation.sh"

[ -x "$GUARD" ] || {
  echo "FAIL: B' isolation guard missing or not executable at $GUARD" >&2
  exit 1
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail=0

# A clean baseline of each input, so a case perturbs exactly one thing.
CLEAN_MANIFEST="$TMP/clean-Package.swift"
CLEAN_PBXPROJ="$TMP/clean-project.pbxproj"
CLEAN_APPDIR="$TMP/clean-app"

cat >"$CLEAN_MANIFEST" <<'SWIFT'
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "pastura-harness",
  targets: [
    .target(name: "PasturaHarnessKit", path: "tools/harness/Sources/PasturaHarnessKit")
  ]
)
SWIFT

cat >"$CLEAN_PBXPROJ" <<'PBX'
// !$*UTF8*$!
{
	objects = {
		E0BCA4BB2F83E7DF0025BAE6 /* PasturaApp.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = PasturaApp.swift; sourceTree = "<group>"; };
	};
}
PBX

mkdir -p "$CLEAN_APPDIR/Pastura"

# run_case <expect:yes|no|unparseable> <label> <manifest> <pbxproj> <app-dir>
#
# Exit codes are checked EXACTLY, not just for non-zero. The guard exits 1 on a
# violation, 2 on bad inputs (missing file, unknown flag) and 3 when it cannot
# parse the manifest. Accepting "any non-zero" for a positive case would let the
# whole suite go green on a mistyped fixture path or a renamed `--pbxproj` flag
# — the vacuous-guard failure this file's header argues against, reproduced one
# level up. Positives additionally must carry the violation marker, so an
# unrelated error cannot masquerade as a detection.
run_case() {
  local expect="$1" label="$2" manifest="$3" pbxproj="$4" appdir="$5"
  local out rc
  set +e
  out="$("$GUARD" --manifest "$manifest" --pbxproj "$pbxproj" --app-dir "$appdir" 2>&1)"
  rc=$?
  set -e

  case "$expect" in
    yes)
      if [ "$rc" -ne 1 ]; then
        echo "FAIL [$label]: expected a violation (exit 1), got exit $rc" >&2
        echo "  guard output: $out" >&2
        fail=1
        return
      fi
      case "$out" in
        *"decision B' violated"*) ;;
        *)
          echo "FAIL [$label]: exit 1 without a violation message — wrong cause?" >&2
          echo "  guard output: $out" >&2
          fail=1
          return
          ;;
      esac
      # NOTE: annotation-path shape is NOT asserted here. Every fixture above
      # lives under `$TMP`, i.e. outside the repository, so `annotate_path`
      # returns it verbatim and its relativizing branch is never taken — an
      # assertion in this loop would exempt every case it saw and pass no
      # matter what. The in-repo case below is what pins it.
      echo "ok [$label]"
      ;;
    no)
      if [ "$rc" -ne 0 ]; then
        echo "FAIL [$label]: guard fired (exit $rc) on a clean input — false positive" >&2
        echo "  guard output: $out" >&2
        fail=1
      else
        echo "ok [$label]"
      fi
      ;;
    unparseable)
      if [ "$rc" -ne 3 ]; then
        echo "FAIL [$label]: expected fail-closed parse error (exit 3), got exit $rc" >&2
        echo "  guard output: $out" >&2
        fail=1
        return
      fi
      case "$out" in
        *"could not parse"*) echo "ok [$label]" ;;
        *)
          echo "FAIL [$label]: exit 3 without a parse-failure message — wrong cause?" >&2
          echo "  guard output: $out" >&2
          fail=1
          ;;
      esac
      ;;
    *)
      echo "FAIL [$label]: unknown expectation '$expect'" >&2
      fail=1
      ;;
  esac
}

# ---------------------------------------------------------------- negatives --
# The guard must stay silent on all of these.

run_case no "clean baseline" "$CLEAN_MANIFEST" "$CLEAN_PBXPROJ" "$CLEAN_APPDIR"

# The false positive that motivated comment-stripping in the first place: a
# comment EXPLAINING the absence of a binary target.
m="$TMP/n-wholeline-comment.swift"; cp "$CLEAN_MANIFEST" "$m"
echo '// The root deliberately declares no .binaryTarget — see ADR-023 B'"'"'.' >>"$m"
run_case no "whole-line comment naming .binaryTarget" "$m" "$CLEAN_PBXPROJ" "$CLEAN_APPDIR"

# The gap #1171 item 1 names: whole-line stripping alone left this tripping.
m="$TMP/n-trailing-comment.swift"; cp "$CLEAN_MANIFEST" "$m"
echo 'let unrelated = 1  // no .binaryTarget here, and none in tools/kmp-gate-spike' >>"$m"
run_case no "trailing comment naming .binaryTarget + the spike" "$m" "$CLEAN_PBXPROJ" "$CLEAN_APPDIR"

# Block comments span lines, so the stripper carries state across them.
m="$TMP/n-block-comment.swift"; cp "$CLEAN_MANIFEST" "$m"
cat >>"$m" <<'SWIFT'
/*
  Historical note: an earlier draft used .binaryTarget and referenced
  tools/kmp-gate-spike from here. ADR-023 B' rejected that shape.
*/
SWIFT
run_case no "multi-line block comment naming both tokens" "$m" "$CLEAN_PBXPROJ" "$CLEAN_APPDIR"

# ---------------------------------------------------------------- positives --
# The guard must fire on all of these.

m="$TMP/p-binarytarget.swift"; cp "$CLEAN_MANIFEST" "$m"
echo '    .binaryTarget(name: "PasturaShared", path: "Frameworks/PasturaShared.xcframework"),' >>"$m"
run_case yes "root manifest declares .binaryTarget" "$m" "$CLEAN_PBXPROJ" "$CLEAN_APPDIR"

m="$TMP/p-binarytarget-trailing.swift"; cp "$CLEAN_MANIFEST" "$m"
echo '    .binaryTarget(name: "X", path: "X.xcframework"),  // staged by CI' >>"$m"
run_case yes "declaration carrying a trailing comment" "$m" "$CLEAN_PBXPROJ" "$CLEAN_APPDIR"

# THE case that discriminates a quote-aware stripper from a naive `s|//.*||`.
# A naive strip truncates this line at the URL's `//`, deleting the
# `.binaryTarget` that follows it — the gate then passes a real violation.
# This is the false-NEGATIVE risk #1171 item 1 warns tightening would create.
m="$TMP/p-url-then-binarytarget.swift"; cp "$CLEAN_MANIFEST" "$m"
echo '    .package(url: "https://example.com/pkg"), .binaryTarget(name: "Leak", path: "L.xcframework"),' >>"$m"
run_case yes "//-bearing string literal preceding .binaryTarget" "$m" "$CLEAN_PBXPROJ" "$CLEAN_APPDIR"

# ------------------------------------------------------- fail-closed parses --
# The stripper models single-line string literals only. Two independent
# detectors close the resulting fail-open, and each needs its OWN case: an
# unclosed block comment at EOF (`in_block`), and a line ending inside a string
# literal (`lost`). Without the third case below, `lost` could be deleted
# outright and this suite would stay green — verified by mutation.

# The motivating shape: a `"""` block whose interior contains `/*`. The stripper
# reads that `/*` as a real block-comment opener and swallows every later line,
# including the genuine `.binaryTarget` below it — a fail-OPEN.
#
# BOTH detectors trip here: the `"""` opener is three quotes, so line 1 also
# ends mid-string and sets `lost`. `in_block` alone is sufficient (the `*/`
# never arrives), which is exactly why this case cannot serve as `lost`'s
# control — the balanced-`"""` case below is.
m="$TMP/e-multiline-string.swift"; cp "$CLEAN_MANIFEST" "$m"
cat >>"$m" <<'SWIFT'
let doc = """
example /* not a comment
"""
let leak = Package(targets: [ .binaryTarget(name: "X", path: "X.xcframework") ])
SWIFT
run_case unparseable "multi-line string literal containing /*" "$m" "$CLEAN_PBXPROJ" "$CLEAN_APPDIR"

# An unterminated block comment reaches `in_block` the obvious way.
m="$TMP/e-unterminated-block.swift"; cp "$CLEAN_MANIFEST" "$m"
printf '/* opened and never closed\n' >>"$m"
run_case unparseable "unterminated block comment" "$m" "$CLEAN_PBXPROJ" "$CLEAN_APPDIR"

# The `lost` negative control: a well-formed `"""` block with no `/*` inside, so
# `in_block` stays 0 and only the end-of-line-inside-a-string detector can fire.
# A `"""` opener is three quotes, so the line ends with the scanner mid-string.
m="$TMP/e-multiline-balanced.swift"; cp "$CLEAN_MANIFEST" "$m"
printf 'let doc = """\nplain multi-line, no block-comment opener\n"""\n' >>"$m"
run_case unparseable "multi-line string with no /* inside (lost-flag control)" \
  "$m" "$CLEAN_PBXPROJ" "$CLEAN_APPDIR"

m="$TMP/p-spike-reference.swift"; cp "$CLEAN_MANIFEST" "$m"
echo '    .target(name: "Consumer", path: "tools/kmp-gate-spike/Sources/KMPGateSpike"),' >>"$m"
run_case yes "root manifest reaches into tools/kmp-gate-spike" "$m" "$CLEAN_PBXPROJ" "$CLEAN_APPDIR"

# iOS xcodebuild lane, explicit-reference form. Fixture provenance: these lines
# are the shape commit 9f89bc3e wired into this same project. They were
# hand-authored there (its message records "all UUIDs prefixed E0F1A1F1..."),
# NOT emitted by Xcode — but that commit build-verified them (`xcodebuild build`
# SUCCEEDED, framework embedded and codesigned), which is the property the grep
# leans on: Xcode accepted and acted on exactly this text.
p="$TMP/p-pbxproj-xcframework.pbxproj"
sed 's|^	};|	E0F1A1F12001A1F100A1F100 /* PasturaShared.xcframework */ = {isa = PBXFileReference; lastKnownFileType = wrapper.xcframework; name = PasturaShared.xcframework; path = Frameworks/PasturaShared.xcframework; sourceTree = "<group>"; };\n	};|' \
  "$CLEAN_PBXPROJ" >"$p"
run_case yes "pbxproj references an .xcframework" "$CLEAN_MANIFEST" "$p" "$CLEAN_APPDIR"

# iOS xcodebuild lane, synchronized-group form — the path the pbxproj grep
# structurally cannot see, because the sweep leaves no project-file entry.
#
# A real git repo, because check (4) asks `git ls-files`: an UNtracked
# framework is build output on one machine, not a repository state, and must
# not fire. The negative case below pins that distinction — it is the bug this
# test caught, where a `find` walk flagged `Pastura/DerivedData`'s
# `llama.xcframework` and went red locally while staying green on a fresh CI
# checkout.
a="$TMP/p-appdir-sweep"
mkdir -p "$a/Pastura/PasturaShared.xcframework/ios-arm64"
git -C "$a" init -q
git -C "$a" config user.email t@example.com
git -C "$a" config user.name t
echo "binary" >"$a/Pastura/PasturaShared.xcframework/ios-arm64/stub"
git -C "$a" add -A
# Ambient global config must not reach these fixtures: a contributor with
# commit.gpgsign=true, or core.hooksPath pointing at this repo's hooks, would
# otherwise get a spurious failure — or a swiftlint/xcodebuild run inside a
# shell test.
git -C "$a" -c commit.gpgsign=false -c core.hooksPath=/dev/null commit -qm "tracked framework"
run_case yes "tracked framework swept in via PBXFileSystemSynchronizedRootGroup" \
  "$CLEAN_MANIFEST" "$CLEAN_PBXPROJ" "$a"

# The same tree with the framework UNtracked — build output, not a violation.
u="$TMP/n-appdir-untracked"
mkdir -p "$u/Pastura/DerivedData/artifacts/llama.xcframework/ios-arm64"
git -C "$u" init -q
git -C "$u" config user.email t@example.com
git -C "$u" config user.name t
echo "build output" >"$u/Pastura/DerivedData/artifacts/llama.xcframework/ios-arm64/stub"
run_case no "untracked .xcframework in build output" "$CLEAN_MANIFEST" "$CLEAN_PBXPROJ" "$u"

# ------------------------------------------------------- unforced code paths --
# Two behaviours no case above reaches. Both are cheap to pin and one of them is
# the guard's ONLY fail-open, so leaving it unexercised is the shape this file
# exists to argue against.

# Check (4) skips (warns, passes) when the app dir is not in a git work tree.
# `git ls-files` has nothing to say outside a repository, and failing there
# would make the guard unusable on an exported tarball. Deliberate, so pinned.
n="$TMP/n-appdir-not-a-repo"
mkdir -p "$n/Pastura/Vendor.xcframework"
run_case no "app dir outside a git work tree (check 4 skips)" \
  "$CLEAN_MANIFEST" "$CLEAN_PBXPROJ" "$n"

# Input errors must be exit 2 — distinct from a violation (1) and from a parse
# refusal (3). `run_case`'s header claims exact-code checking is what stops a
# mistyped path going green; these make that claim executable.
set +e
out="$("$GUARD" --manifest "$TMP/does-not-exist.swift" --pbxproj "$CLEAN_PBXPROJ" \
  --app-dir "$CLEAN_APPDIR" 2>&1)"; rc=$?
set -e
if [ "$rc" -eq 2 ]; then echo "ok [missing manifest is exit 2]"; else
  echo "FAIL [missing manifest]: expected exit 2, got $rc — $out" >&2; fail=1
fi

set +e
out="$("$GUARD" --bogus-flag 2>&1)"; rc=$?
set -e
if [ "$rc" -eq 2 ]; then echo "ok [unknown argument is exit 2]"; else
  echo "FAIL [unknown argument]: expected exit 2, got $rc — $out" >&2; fail=1
fi

# ------------------------------------------------- annotation anchoring --
# GitHub resolves `::error file=` RELATIVE TO THE REPOSITORY ROOT; an absolute
# path renders as a job-level message with no line linkage, while still LOOKING
# like a normal annotation in the log. So it must be asserted, and it can only
# be asserted on a manifest that actually lives inside the repo — every other
# fixture here is under $TMP, where the relativizing branch is never taken.
#
# The fixture goes in `Pastura/DerivedData/` because that path is gitignored
# (`git check-ignore` confirms), so it is invisible to git and cannot disturb
# the shared checkout the sibling shell tests run against. Removed immediately.
anno_dir="$REPO_ROOT/Pastura/DerivedData/.kmp-gate-anno-fixture"
mkdir -p "$anno_dir"
cp "$CLEAN_MANIFEST" "$anno_dir/Package.swift"
echo '    .binaryTarget(name: "X", path: "X.xcframework"),' >>"$anno_dir/Package.swift"
set +e
out="$("$GUARD" --manifest "$anno_dir/Package.swift" --pbxproj "$CLEAN_PBXPROJ" \
  --app-dir "$CLEAN_APPDIR" 2>&1)"; rc=$?
set -e
rm -rf "$anno_dir"
expected_rel="Pastura/DerivedData/.kmp-gate-anno-fixture/Package.swift"
case "$rc:$out" in
  1:*"::error file=$expected_rel,line="*)
    echo "ok [in-repo annotation is repo-relative with a line number]" ;;
  *)
    echo "FAIL [annotation anchoring]: expected exit 1 and" >&2
    echo "  '::error file=$expected_rel,line=<n>', got exit $rc" >&2
    echo "  guard output: $out" >&2
    fail=1
    ;;
esac

# A stripper that breaks for an unrelated reason must NOT report "could not
# parse" — that message means "this manifest has a shape I don't model", and
# conflating it with "I am broken" would make the two indistinguishable in CI.
# The only guard path with no other coverage.
broken="$TMP/broken-guard.sh"
sed 's/BEGIN { in_block = 0; lost = 0 }/BEGIN { in_block = 0; lost = 0; @@syntax@@ }/' \
  "$GUARD" >"$broken"
chmod +x "$broken"
if ! grep -q '@@syntax@@' "$broken"; then
  echo "FAIL [broken stripper]: mutation did not apply — the anchor moved" >&2
  fail=1
else
  set +e
  out="$("$broken" --manifest "$CLEAN_MANIFEST" --pbxproj "$CLEAN_PBXPROJ" \
    --app-dir "$CLEAN_APPDIR" 2>&1)"; rc=$?
  set -e
  case "$rc:$out" in
    4:*"failed unexpectedly"*) echo "ok [broken stripper is exit 4, not exit 3]" ;;
    *)
      echo "FAIL [broken stripper]: expected exit 4 + 'failed unexpectedly', got exit $rc" >&2
      echo "  guard output: $out" >&2
      fail=1
      ;;
  esac
fi

# ------------------------------------------------------------- the real repo --
# The guard must be green on the real files as they stand. Placed last so a
# perturbation-case bug is not misread as a repo violation.
run_case no "real repository files" \
  "$REPO_ROOT/Package.swift" \
  "$REPO_ROOT/Pastura/Pastura.xcodeproj/project.pbxproj" \
  "$REPO_ROOT/Pastura"

if [ "$fail" -ne 0 ]; then
  echo "kmp-gate-isolation-test: FAIL" >&2
  exit 1
fi
echo "kmp-gate-isolation-test: OK"
