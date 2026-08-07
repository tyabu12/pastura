#!/usr/bin/env bash
#
# scripts/tests/precommit-gate-classify-test.sh — regression test for
# scripts/precommit-gate-classify.sh (#625).
#
# Feeds synthetic newline-separated staged-path lists on stdin and
# asserts both the emitted gate tokens AND a zero exit code. The exit
# code matters: the classifier runs inside `gates=$(... | classify)` in
# the pre-commit hook under `set -euo pipefail`, so an internal grep's
# exit-1 (no match) must never become the script's exit status — that
# would abort the whole hook.
#
# CI-wired: the `*-test.sh` naming convention makes this a gate under
# .github/workflows/ci.yml ("Run scripts/tests/*-test.sh"). That job runs
# on ubuntu (bash 5+), so it does NOT exercise the classifier's bash-3.2
# behaviour on the dev-macOS pre-commit runtime — run it under /bin/bash
# locally for 3.2 coverage.
#
# Run manually:
#   bash scripts/tests/precommit-gate-classify-test.sh

set -euo pipefail

SCRIPT="$(git rev-parse --show-toplevel)/scripts/precommit-gate-classify.sh"
fail=0

# assert_tokens <label> <stdin-input> <expected-stdout>
assert_tokens() {
  local label="$1" input="$2" expected="$3"
  local out rc
  set +e
  out="$(printf '%s' "$input" | bash "$SCRIPT")"
  rc=$?
  set -e
  if [ "$rc" -ne 0 ]; then
    echo "FAIL [$label]: classifier exited $rc (expected 0)" >&2
    fail=1
  fi
  if [ "$out" != "$expected" ]; then
    echo "FAIL [$label]: got '$out', expected '$expected'" >&2
    fail=1
  fi
}

# --- skip both: every staged path is build-irrelevant ---------------------
assert_tokens "web only"          "web/index.astro"               ""
assert_tokens "docs md only"      "docs/ROADMAP.md"               ""
assert_tokens "github workflow"   ".github/workflows/ci.yml"      ""
assert_tokens "claude rules"      ".claude/rules/navigation.md"   ""
assert_tokens "top-level md"      "README.md"                     ""
assert_tokens "repo-meta dotfile" ".gitignore"                    ""
assert_tokens "empty changeset"   ""                              ""
assert_tokens "multiple safe"     "$(printf 'web/a.css\ndocs/b.md\n.github/x.yml')" ""

# --- build only: build-relevant but non-Swift -----------------------------
assert_tokens "pbxproj only"      "Pastura/Pastura.xcodeproj/project.pbxproj"       "build"
assert_tokens "resource xcstrings" "Pastura/Pastura/Resources/Localizable.xcstrings" "build"
assert_tokens "root Package.resolved" "Package.resolved"          "build"
# Conservative default: an unrecognized path forces the build rather than
# silently skipping it (#625 guardrail — a false skip lands a broken build).
assert_tokens "unknown extension" "random.txt"                    "build"
assert_tokens "path with spaces"  "my notes.txt"                  "build"

# `shared/**` must stay non-SAFE. Two ci.yml drift guards in `harness-build`
# ("Golden JSON drift guard" / "Parity golden drift guard") are gated on
# `ios != false`, which is derived from the `build` token — so these two cases
# are what makes a PR hand-editing ONLY a generated Kotlin file reach them.
# Adding `shared/` to the SAFE denylist would disarm both silently: the guards
# would still pass, having never run.
assert_tokens "shared kotlin (parity golden)" \
  "shared/engine/src/commonTest/kotlin/com/pastura/engine/ParityGolden.kt"  "build"
assert_tokens "shared kotlin (json golden)" \
  "shared/models/src/commonTest/kotlin/com/pastura/models/SwiftGoldenJson.kt" "build"

# --- lint + build: Swift source or the SwiftLint config -------------------
assert_tokens "swift source"      "Pastura/Pastura/Engine/Foo.swift" "lint build"
# A tightened rule in .swiftlint.yml can newly flag unchanged code, so a
# config-only edit must still run the lint gate.
assert_tokens "swiftlint config"  ".swiftlint.yml"                "lint build"
assert_tokens "mixed safe + swift" "$(printf 'docs/a.md\nPastura/Foo.swift')" "lint build"
assert_tokens "mixed safe + build" "$(printf 'web/x.astro\nPastura/x.pbxproj')" "build"

# --- result ---------------------------------------------------------------
if [ "$fail" -eq 0 ]; then
  echo "precommit-gate-classify: all cases passed"
else
  echo "precommit-gate-classify: FAILURES" >&2
  exit 1
fi
