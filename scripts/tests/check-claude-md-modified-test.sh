#!/usr/bin/env bash
#
# scripts/tests/check-claude-md-modified-test.sh — regression test for
# scripts/hooks/check-claude-md-modified.sh (the `gh pr create` PreToolUse
# nudge).
#
# The hook reasons from live repo state (`git diff main...HEAD` +
# `git show HEAD:CLAUDE.md`), so each case builds a throwaway git repo
# under a tempdir with a `main` baseline and a feature branch, then runs
# the hook from that repo and asserts on its emitted additionalContext.
# Modeled on p8-precommit-gate-test.sh / navigation-map-precommit-gate-test.sh.
#
# Two nudges are covered:
#   - convention nudge: fires when NEITHER CLAUDE.md NOR .claude/rules/ changed.
#   - mirror-sync nudge: fires when CLAUDE.md changed inside a MIRRORED section
#     (per the Reference Documents table) AND README/CONTRIBUTING did not.
# They are mutually exclusive on the CLAUDE.md dimension.
#
# CI-wired via the `*-test.sh` glob (.github/workflows/ci.yml "Shell gate
# tests", ubuntu/bash-5). That runner CANNOT catch a bash-3.2 regression in
# the hook, so before merge also run under the system bash on macOS:
#   /bin/bash scripts/tests/check-claude-md-modified-test.sh
# Normal run:
#   bash scripts/tests/check-claude-md-modified-test.sh

set -euo pipefail

HOOK="$(git rev-parse --show-toplevel)/scripts/hooks/check-claude-md-modified.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail=0

# Canonical CLAUDE.md for the throwaway repos. Contains a representative
# subset of the real mirrored sections plus non-mirrored controls:
#   ## Architecture / ## Tech Stack / ## Directory Structure  (mirrored)
#   ### Git Conventions  (mirrored, level-3, under ## Development Workflow)
#   ### Test Execution   (NON-mirrored sibling of Git Conventions — locks in
#                         level-aware range termination)
#   ## Current Phase / ## ADR Index  (NON-mirrored ##)
write_claude_md() {
  cat > "$1/CLAUDE.md" <<'CLAUDE_MD'
# Pastura

## Current Phase

Phase 2 in progress.

## Architecture

Layer diagram here.

## Tech Stack

| Language | Swift 6.x |
| Min iOS | 18.0 |

## Directory Structure

Directory tree here.

## Development Workflow

### Git Conventions

Branch naming rules.
Commit style rules.

### Test Execution

Run the tests here.

## ADR Index

- ADR-001 summary.
- ADR-002 summary.
CLAUDE_MD
}

# Build a repo on `main` with a full baseline, leaving HEAD on a fresh
# `feature` branch ready for the case-specific edits.
new_repo() {
  local d="$1"
  git init -q "$d"
  (
    cd "$d"
    git config user.email test@example.com
    git config user.name test
    git config commit.gpgsign false
    write_claude_md "$d"
    mkdir -p .claude/rules Sources
    printf 'rule body\n' > .claude/rules/foo.md
    printf 'let x = 1\n' > Sources/Code.swift
    printf '# README\n\nArchitecture and Tech stack live here.\n' > README.md
    printf '# Contributing\n\nWorkflow and Design principles live here.\n' > CONTRIBUTING.md
    git add -A
    git commit -qm baseline
    git switch -qc feature
  )
}

# Run the hook from inside repo $1, print its stdout, and record exit code
# into the global RC (for the fail-open / exit-0 assertion).
RC=0
run_hook() {
  local out
  set +e
  out="$( cd "$1" && bash "$HOOK" )"
  RC=$?
  set -e
  printf '%s' "$out"
}

# assert_contains LABEL HAYSTACK NEEDLE
assert_contains() {
  case "$2" in
    *"$3"*) : ;;
    *) echo "FAIL [$1]: expected to contain: $3" >&2; fail=1 ;;
  esac
}
# assert_absent LABEL HAYSTACK NEEDLE
assert_absent() {
  case "$2" in
    *"$3"*) echo "FAIL [$1]: expected NOT to contain: $3" >&2; fail=1 ;;
    *) : ;;
  esac
}
# assert_empty LABEL HAYSTACK
assert_empty() {
  if [ -n "$2" ]; then echo "FAIL [$1]: expected no nudge, got: $2" >&2; fail=1; fi
}
# assert_rc0 LABEL — the hook must never exit non-zero (fail-open).
assert_rc0() {
  if [ "$RC" -ne 0 ]; then echo "FAIL [$1]: hook exited $RC (must be 0)" >&2; fail=1; fi
}

CONV="Neither CLAUDE.md nor .claude/rules/"
MIRROR="Reference Documents"

# --- (a) code-only change → convention nudge -------------------------------
d="$TMP/a"; new_repo "$d"
( cd "$d"; printf 'let y = 2\n' >> Sources/Code.swift; git commit -qam "code" )
out="$(run_hook "$d")"
assert_rc0 a
assert_contains a "$out" "$CONV"
assert_absent a "$out" "$MIRROR"

# --- (b) non-mirrored CLAUDE.md section only → no nudge --------------------
d="$TMP/b"; new_repo "$d"
( cd "$d"; sed -i.bak 's/ADR-001 summary./ADR-001 revised./' CLAUDE.md; rm -f CLAUDE.md.bak; git commit -qam "adr" )
out="$(run_hook "$d")"
assert_rc0 b
assert_empty b "$out"

# --- (c) mirrored section (Tech Stack) w/o README → mirror nudge (README) --
d="$TMP/c"; new_repo "$d"
( cd "$d"; sed -i.bak 's/Swift 6.x/Swift 6.1/' CLAUDE.md; rm -f CLAUDE.md.bak; git commit -qam "techstack" )
out="$(run_hook "$d")"
assert_rc0 c
assert_contains c "$out" "$MIRROR"
assert_contains c "$out" "README.md"
assert_absent c "$out" "CONTRIBUTING.md"
assert_absent c "$out" "$CONV"

# --- (d) mirrored section + README also changed → no nudge ----------------
d="$TMP/d"; new_repo "$d"
( cd "$d"; sed -i.bak 's/Swift 6.x/Swift 6.1/' CLAUDE.md; rm -f CLAUDE.md.bak
  printf 'Updated tech stack.\n' >> README.md; git commit -qam "techstack+readme" )
out="$(run_hook "$d")"
assert_rc0 d
assert_empty d "$out"

# --- (e) non-mirrored CLAUDE.md section + .claude/rules → no nudge ---------
d="$TMP/e"; new_repo "$d"
( cd "$d"; sed -i.bak 's/ADR-002 summary./ADR-002 revised./' CLAUDE.md; rm -f CLAUDE.md.bak
  printf 'more rule\n' >> .claude/rules/foo.md; git commit -qam "adr+rule" )
out="$(run_hook "$d")"
assert_rc0 e
assert_empty e "$out"

# --- (f) sibling ### Test Execution edit → no nudge (level termination) ----
d="$TMP/f"; new_repo "$d"
( cd "$d"; sed -i.bak 's/Run the tests here./Run the full suite./' CLAUDE.md; rm -f CLAUDE.md.bak; git commit -qam "testexec" )
out="$(run_hook "$d")"
assert_rc0 f
assert_empty f "$out"

# --- (g) early insertion + Tech Stack edit → mirror nudge (HEAD ranges) ----
# A large insertion in ## Current Phase shifts Tech Stack down. Section ranges
# must be computed from HEAD (post-shift) or the Tech Stack hunk would miss.
d="$TMP/g"; new_repo "$d"
( cd "$d"
  # Insert 10 filler lines after the Current Phase line (awk, not sed — BSD
  # sed does not treat `\n` in the replacement as a newline, so a sed-based
  # multiline insert is non-portable across the ubuntu-CI and macOS runs).
  awk '{print} /Phase 2 in progress./{for(i=1;i<=10;i++) print "Filler phase line " i "."}' \
    CLAUDE.md > CLAUDE.md.tmp && mv CLAUDE.md.tmp CLAUDE.md
  sed -i.bak 's/Swift 6.x/Swift 6.1/' CLAUDE.md; rm -f CLAUDE.md.bak
  git commit -qam "shift+techstack" )
out="$(run_hook "$d")"
assert_rc0 g
assert_contains g "$out" "$MIRROR"
assert_contains g "$out" "README.md"

# --- (h) ### Git Conventions edit w/o CONTRIBUTING → mirror nudge (CONTRIBUTING) ---
d="$TMP/h"; new_repo "$d"
( cd "$d"; sed -i.bak 's/Branch naming rules./Branch naming updated./' CLAUDE.md; rm -f CLAUDE.md.bak; git commit -qam "gitconv" )
out="$(run_hook "$d")"
assert_rc0 h
assert_contains h "$out" "$MIRROR"
assert_contains h "$out" "CONTRIBUTING.md"
assert_absent h "$out" "README.md"

if [ "$fail" -eq 0 ]; then
  echo "check-claude-md-modified: all cases passed"
else
  echo "check-claude-md-modified: FAILURES" >&2
  exit 1
fi
