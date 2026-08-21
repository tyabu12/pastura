#!/usr/bin/env bash
#
# scripts/duplicate-basename-gate.sh — Pre-commit + CI gate for duplicate Swift
# base filenames within one build target (#1513). Replaces the manual
# `find … -name '<Name>*.swift'` step `.claude/rules/build-traps.md` used to
# prescribe.
#
# WHAT IT BUYS. The failure is already loud — `Multiple commands produce
# '…/<Name>.stringsdata'` in the app target (SWIFT_EMIT_LOC_STRINGS), swiftc's
# `filename "<Name>.swift" used twice`, duplicate `.o` producers under SwiftPM.
# What it is not is early or complete: the pre-commit `xcodebuild build`
# compiles the app scheme only, so a collision in PasturaTests / PasturaUITests
# / tools/harness / tools/kmp-gate-spike first shows minutes later in CI with
# no rename advice attached. Xcode's PBXFileSystemSynchronizedRootGroup makes
# the app case easy to hit: a new file anywhere under Pastura/Pastura/ joins
# the target automatically, so the clash can be cross-layer.
#
# PER TARGET, NOT REPO-WIDE — load-bearing, not pedantry.
# `Pastura/Pastura/LLM/SuspendController.swift` and
# `tools/kmp-gate-spike/Sources/KMPGateSpike/SuspendController.swift` coexist
# today in different targets and must keep doing so; a repo-wide
# `find | sort | uniq -d` reddens on that pair and on the two `Package.swift`
# manifests. --self-test pins both directions against those real paths.
#
# ONE ROW PER TARGET, NEVER PER DIRECTORY. Subdividing a row keeps coverage
# complete and every population floor satisfied, so nothing below notices —
# while a pair straddling the two halves stops being compared at all.
#
# `.swift` ONLY: Pastura/Pastura/LLM/SafeSampler.swift coexists with
# LLM/SafeSampler/SafeSampler.{h,mm} in the same target and builds fine.
# Comparison is byte-exact, so a `Foo.swift` / `foo.swift` pair is out of scope
# — it cannot exist in a macOS checkout, though it would collide if one landed
# from a case-sensitive filesystem.
#
# `git ls-files`, never `find`: the index is what is about to be committed,
# while a worktree walk also flags an untracked scratch file that will never
# reach a build — red on one machine, green everywhere else. Arm A8 is the
# control, and its fixture has to sit INSIDE a target root or it controls
# nothing (measured: an earlier version planted it under Pastura/DerivedData/
# and stayed green under a `find` mutation). Note the DerivedData hazard in
# `.claude/rules/ci-workflows.md` § "Gate scripts" does not reach this gate at
# all — Pastura/DerivedData is a sibling of every target root, not a
# descendant — so do not re-import that reason.
#
# Modes:
#   (default)    self-gate — check only when the staged diff touches a .swift
#                path or this script. Used by the git pre-commit hook.
#   --check      unconditional. Used by the CI shell-tests job.
#   --self-test  controls. A scanning guard answers "0 duplicates" both when
#                the tree is clean and when its own scan is broken, so the arms
#                cover BOTH halves — the detector, and the population fed to it.
#
# bash 3.2 portable — ships to dev macOS via the pre-commit hook. NO
# mapfile/readarray, declare -A, ${var^^} or <<< here-strings. CI runs ubuntu
# bash 5 and will NOT catch a 3.2 regression.

set -euo pipefail

SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

# One entry per BUILD TARGET. The app and test rows are the Xcode project's
# synchronized root groups; the rest are the `path:` values of the SwiftPM
# targets in Package.swift and tools/kmp-gate-spike/Package.swift. Two SwiftPM
# targets are deliberately absent because the app row is a strict superset of
# each: PasturaCore (`Pastura/Pastura`, sources Models/LLM/Engine) and
# PasturaSafeSampler (`Pastura/Pastura/LLM/SafeSampler`, which holds no .swift
# at all). A target added LATER is caught by unlisted_swift_files, not by
# anyone remembering this list.
DEFAULT_TARGET_ROOTS='Pastura/Pastura
Pastura/PasturaTests
Pastura/PasturaUITests
tools/harness/Sources/PasturaHarnessKit
tools/harness/Sources/pastura-harness
tools/harness/Tests/PasturaHarnessKitTests
tools/kmp-gate-spike/Sources/KMPGateSpike
tools/kmp-gate-spike/Sources/kmp-gate-bench
tools/kmp-gate-spike/Tests/KMPGateSpikeTests'

# TEST HOOK, not a production knob. --self-test needs to perturb the SCAN and
# not just the detector, but an override honoured unconditionally would also
# reach the pre-commit path, where an exported value in someone's shell profile
# could subdivide a row (see ONE ROW PER TARGET above) and silently narrow the
# gate. So it applies only when the self-test asks for it.
TARGET_ROOTS="$DEFAULT_TARGET_ROOTS"
if [ "${PASTURA_DUP_GATE_SELFTEST:-}" = "1" ] && [ -n "${PASTURA_DUP_GATE_ROOTS:-}" ]; then
  TARGET_ROOTS="$PASTURA_DUP_GATE_ROOTS"
fi

# Tracked .swift belonging to no build target: SwiftPM reads the manifests
# itself, and the skill fixtures are inert text a drift test diffs.
NON_TARGET_SWIFT='^Package\.swift$|^tools/kmp-gate-spike/Package\.swift$|^\.claude/skills/scenario-factory/tests/fixtures/[^/]+\.swift$'

TMP="$(mktemp -d)"
# A8 plants a fixture inside the working tree, so it needs removing even if the
# run dies between planting and asserting.
SCOPE_PROBE=""
cleanup() { rm -rf "$TMP"; [ -z "$SCOPE_PROBE" ] || rm -rf "$SCOPE_PROBE"; }
trap cleanup EXIT

# --- primitives -------------------------------------------------------------

# Tracked .swift under one target root. `core.quotepath=false` so a non-ASCII
# path arrives literally instead of octal-escaped and double-quoted, which
# would defeat the basename match in check_tree below.
list_target_files() {
  git -c core.quotepath=false ls-files -- "$1/*.swift"
}

# stdin: newline-separated paths. stdout: each base name occurring more than
# once. Pure text — this is what the detector arms of --self-test exercise.
dup_basenames() {
  sed 's|.*/||' | sort | uniq -d
}

# Tracked .swift covered by no target root and not explicitly excluded.
unlisted_swift_files() {
  git -c core.quotepath=false ls-files -- '*.swift' | sort -u > "$TMP/all"
  : > "$TMP/covered"
  while IFS= read -r r; do
    [ -n "$r" ] || continue
    list_target_files "$r" >> "$TMP/covered"
  done <<TARGETS_EOF
$TARGET_ROOTS
TARGETS_EOF
  sort -u "$TMP/covered" -o "$TMP/covered"
  # Capture, never `| grep -q`, and `|| [ $? -eq 1 ]` rather than `|| true`, so
  # a broken pattern (exit >= 2) aborts instead of reading as "nothing left".
  # `.claude/rules/ci-workflows.md` § "Rule 3".
  comm -23 "$TMP/all" "$TMP/covered" \
    | { grep -Ev "$NON_TARGET_SWIFT" || [ $? -eq 1 ]; }
}

# --- check ------------------------------------------------------------------

check_tree() {
  local rc=0 root files dups name p unlisted
  files="$TMP/files"
  while IFS= read -r root; do
    [ -n "$root" ] || continue
    list_target_files "$root" > "$files"
    # POPULATION FLOOR. A root that lists nothing is a renamed or mistyped
    # path, and it reports "0 duplicates" exactly like a healthy one — the
    # fail-open this gate would otherwise ship.
    if [ ! -s "$files" ]; then
      echo "duplicate-basename gate: target root '$root' matched no tracked .swift file." >&2
      echo "  The scan is broken, not the tree. Fix DEFAULT_TARGET_ROOTS in $SELF." >&2
      rc=1
      continue
    fi
    dups="$(dup_basenames < "$files")"
    [ -n "$dups" ] || continue
    while IFS= read -r name; do
      [ -n "$name" ] || continue
      echo "duplicate-basename gate: '$name' appears more than once in target '$root':" >&2
      # `case`, not `grep`: a leading-slash pattern would drop a repo-root file
      # (root `Package.swift` vs `tools/…/Package.swift`), and a `-E` pattern
      # would misread a `+` in a filename — `SimulationRunnerTests+…` is real.
      while IFS= read -r p; do
        case "$p" in
          */"$name"|"$name") printf '    %s\n' "$p" >&2 ;;
        esac
      done < "$files"
      rc=1
    done <<DUPS_EOF
$dups
DUPS_EOF
  done <<ROOTS_EOF
$TARGET_ROOTS
ROOTS_EOF

  unlisted="$(unlisted_swift_files)"
  if [ -n "$unlisted" ]; then
    echo "duplicate-basename gate: tracked .swift files belong to no scanned target:" >&2
    printf '%s\n' "$unlisted" | sed 's/^/    /' >&2
    echo "  Add the new target's path to DEFAULT_TARGET_ROOTS in $SELF, or list" >&2
    echo "  the file in NON_TARGET_SWIFT if nothing compiles it." >&2
    rc=1
  fi

  if [ "$rc" -ne 0 ]; then
    echo "" >&2
    echo "  Two Swift files sharing a base name in one target fail the build:" >&2
    echo "  \"Multiple commands produce '…/<Name>.stringsdata'\" (app target)," >&2
    echo "  'filename \"<Name>.swift\" used twice' (swiftc), or duplicate .o" >&2
    echo "  producers (SwiftPM). Rename one — and the type too if it clashes." >&2
    echo "  See .claude/rules/build-traps.md." >&2
    return 1
  fi
  echo "duplicate-basename gate: clean."
}

# --- self-test --------------------------------------------------------------

self_test() {
  local fail=0 total=0 out
  bad() { printf 'FAIL: %s\n' "$*" >&2; fail=1; total=$((total + 1)); }
  ok()  { printf '  ok: %s\n' "$*"; total=$((total + 1)); }

  # A1 detector positive control.
  out="$(printf 'a/Foo.swift\nb/Foo.swift\n' | dup_basenames)"
  if [ "$out" = "Foo.swift" ]; then ok "A1 detector flags a same-name pair"
  else bad "A1 expected 'Foo.swift', got '$out'"; fi

  # A2 detector negative control.
  out="$(printf 'a/Foo.swift\nb/Bar.swift\n' | dup_basenames)"
  if [ -z "$out" ]; then ok "A2 detector silent on distinct names"
  else bad "A2 expected empty, got '$out'"; fi

  # A3 class control — the producer variants a sloppier detector would smuggle
  # through: a substring name, and the same name at a different depth.
  out="$(printf 'a/Foo.swift\na/b/c/FooBar.swift\nx/BarFoo.swift\n' | dup_basenames)"
  if [ -z "$out" ]; then ok "A3 substring / depth variants are not duplicates"
  else bad "A3 expected empty, got '$out'"; fi

  # A4 a triple reports its name once, not twice.
  out="$(printf 'a/Foo.swift\nb/Foo.swift\nc/Foo.swift\n' | dup_basenames)"
  if [ "$out" = "Foo.swift" ]; then ok "A4 a triple reports once"
  else bad "A4 expected one line, got '$out'"; fi

  # A5 END-TO-END POSITIVE on real tracked paths: scanning the whole repo as one
  # pseudo-target must flag the two cross-target pairs that legitimately
  # coexist. This is the arm that reddens if the per-target split is ever
  # "simplified" into a repo-wide scan. It also asserts BOTH members of the
  # root-level pair are listed — a report that names a duplicate and prints one
  # path is how a broken path matcher looks.
  if out="$(PASTURA_DUP_GATE_SELFTEST=1 PASTURA_DUP_GATE_ROOTS='.' bash "$SELF" --check 2>&1)"; then
    bad "A5 a repo-wide scan passed — the duplicate path never fires"
  else
    case "$out" in
      *SuspendController.swift*Package.swift*|*Package.swift*SuspendController.swift*) ;;
      *) bad "A5 fired but named neither pair: $out" ;;
    esac
    case "$out" in
      *"    Package.swift"*) ok "A5 repo-wide scan flags both pairs, root-level path included" ;;
      *) bad "A5 omitted the repo-root Package.swift from its own evidence: $out" ;;
    esac
  fi

  # A6 SCAN CONTROL — a root matching nothing must trip the population floor
  # rather than read as "0 duplicates".
  if out="$(PASTURA_DUP_GATE_SELFTEST=1 PASTURA_DUP_GATE_ROOTS='no/such/target' bash "$SELF" --check 2>&1)"; then
    bad "A6 a target root matching no file passed"
  else
    case "$out" in
      *"matched no tracked .swift file"*) ok "A6 empty target root trips the floor" ;;
      *) bad "A6 failed for the wrong reason: $out" ;;
    esac
  fi

  # A7 COVERAGE CONTROL — a healthy but PARTIAL root list must be caught by the
  # unlisted sweep. Without it, dropping a row from DEFAULT_TARGET_ROOTS would
  # silently stop scanning that target while every other arm stayed green.
  if out="$(PASTURA_DUP_GATE_SELFTEST=1 PASTURA_DUP_GATE_ROOTS='Pastura/PasturaUITests' bash "$SELF" --check 2>&1)"; then
    bad "A7 a partial root list passed"
  else
    case "$out" in
      *"belong to no scanned target"*) ok "A7 partial root list caught by the unlisted sweep" ;;
      *) bad "A7 failed for the wrong reason: $out" ;;
    esac
  fi

  # A8 SCOPE CONTROL — the scan reads the INDEX, not the worktree, so two
  # same-named UNTRACKED files must not make the gate red on a name nothing is
  # committing. The fixture must live inside a target root or the arm controls
  # nothing: an earlier version planted it under Pastura/DerivedData/, which no
  # root contains, and stayed green under the `find` mutation it claimed to
  # catch. kmp-gate-spike is the root chosen because it is SwiftPM-only — a
  # fixture under Pastura/Pastura/ would join the Xcode target the moment a
  # concurrent build looked.
  SCOPE_PROBE="tools/kmp-gate-spike/Sources/KMPGateSpike/scope-probe"
  mkdir -p "$SCOPE_PROBE/a" "$SCOPE_PROBE/b"
  : > "$SCOPE_PROBE/a/ScopeProbe.swift"
  : > "$SCOPE_PROBE/b/ScopeProbe.swift"
  if out="$(bash "$SELF" --check 2>&1)"; then
    ok "A8 untracked files are out of scope"
  else
    bad "A8 the scan reached untracked files: $out"
  fi
  rm -rf "$SCOPE_PROBE"
  SCOPE_PROBE=""

  # A9 the override must NOT reach the production path — otherwise an exported
  # value narrows the pre-commit gate. Same narrowing as A7, minus the marker.
  if out="$(PASTURA_DUP_GATE_ROOTS='Pastura/PasturaUITests' bash "$SELF" --check 2>&1)"; then
    ok "A9 override ignored without the self-test marker"
  else
    bad "A9 the override reached the production path: $out"
  fi

  if [ "$fail" -ne 0 ]; then
    echo "duplicate-basename self-test FAILED" >&2
    return 1
  fi
  echo "duplicate-basename self-test: $total/$total passed"
}

# --- modes ------------------------------------------------------------------

case "${1-}" in
  --check)
    check_tree
    ;;
  --self-test)
    self_test
    ;;
  "")
    STAGED="$(git -c core.quotepath=false diff --cached --name-only)"
    MATCHED="$(printf '%s\n' "$STAGED" \
      | { grep -E '(\.swift$)|(^scripts/duplicate-basename-gate\.sh$)' || [ $? -eq 1 ]; })"
    [ -n "$MATCHED" ] || exit 0
    # Editing the gate stages the gate: run its own arms too, or a broken arm
    # is gated by CI alone. `case`, not another grep — Rule 3 again.
    case "$MATCHED" in
      *scripts/duplicate-basename-gate.sh*) self_test ;;
    esac
    check_tree
    ;;
  *)
    echo "usage: $0 [--check|--self-test]" >&2
    exit 2
    ;;
esac
