#!/usr/bin/env bash
# ui-tour-test.sh — Unit-tests scripts/ui-tour.sh's argument parsing and
# output-directory selection.
#
# Scope is deliberately the pre-simulator prefix only: everything after the
# `sim-dest.sh` source needs a booted simulator and an Xcode build, which the
# Shell-gate CI runner (ubuntu, no Xcode) does not have. The flag parser and
# the OUT_DIR branch are pure shell and are the only part of this script a
# test can reach — before #1338 added `--dark` there was no branch at all.
#
# Runs under bash 3.2 (macOS system bash), per .claude/rules/ci-workflows.md.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/ui-tour.sh"
FAILURES=0

fail() {
  echo "FAIL: $1" >&2
  FAILURES=$((FAILURES + 1))
}

# The parseable prefix ends at the `fi` closing the OUT_DIR branch. Located by
# pattern rather than a pinned line number so an edit above it does not
# silently shift what gets sourced.
PREFIX_END="$(grep -n '^fi$' "$SCRIPT" | head -1 | cut -d: -f1)"
if [ -z "$PREFIX_END" ]; then
  fail "could not locate the OUT_DIR branch terminator in ui-tour.sh"
  exit 1
fi

PREFIX="$(mktemp)"
trap 'rm -f "$PREFIX"' EXIT
head -"$PREFIX_END" "$SCRIPT" > "$PREFIX"

# Guard the harness itself: if the prefix ever stops containing the parser,
# every assertion below would pass vacuously.
if ! grep -q 'APPEARANCE=' "$PREFIX" || ! grep -q 'OUT_DIR=' "$PREFIX"; then
  fail "sourced prefix contains neither APPEARANCE nor OUT_DIR — harness is measuring nothing"
  exit 1
fi

# --- appearance + OUT_DIR selection -----------------------------------------

check_selection() {
  local args="$1" want_appearance="$2" want_suffix="$3" got
  got="$(/bin/bash -c "set -- $args; source '$PREFIX'; echo \"\$APPEARANCE|\$OUT_DIR\"")"
  case "$got" in
    "$want_appearance|"*"$want_suffix")
      echo "  ok: '$args' -> $got"
      ;;
    *)
      fail "'$args' selected '$got' (wanted appearance=$want_appearance, dir ending '$want_suffix')"
      ;;
  esac
}

check_selection ""        light docs/design/screenshots
check_selection "--light" light docs/design/screenshots
check_selection "--dark"  dark  docs/design/screenshots/dark

# Last flag wins, so a wrapper appending a default cannot silently override an
# explicit one earlier on the line.
check_selection "--dark --light" light docs/design/screenshots
check_selection "--light --dark" dark  docs/design/screenshots/dark

# --- unknown argument rejection ---------------------------------------------
#
# Negative control: the real script must exit non-zero on an unknown flag
# BEFORE it touches the simulator, so this runs the actual script, not the
# prefix. A regression that dropped the `*)` arm would reach `sim-dest.sh` and
# either block on the concurrent-session gate or start a build.

if out="$("$SCRIPT" --bogus 2>&1)"; then
  fail "an unknown argument was accepted (expected a non-zero exit)"
else
  case "$out" in
    *"unknown argument"*)
      echo "  ok: unknown argument rejected before any simulator work"
      ;;
    *)
      fail "rejected an unknown argument, but with the wrong message: $out"
      ;;
  esac
fi

if [ "$FAILURES" -eq 0 ]; then
  echo "ui-tour-test.sh: all checks passed"
else
  echo "ui-tour-test.sh: $FAILURES check(s) failed" >&2
  exit 1
fi
