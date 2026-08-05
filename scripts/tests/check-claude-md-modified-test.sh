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
# Four sections are covered:
#   - convention nudge: fires when NO agent-instruction file (CLAUDE.md,
#     .claude/rules/, .claude/agents/) changed.
#   - mirror-sync nudge: fires when CLAUDE.md changed inside a MIRRORED section
#     (per the Reference Documents table) AND README/CONTRIBUTING did not.
#   - trim nudge: fires when per-tier ADDED instruction lines cross a threshold.
#   - footprint nudge: fires when an always-loaded file was touched AND the
#     repo-wide always-loaded byte total exceeds the ceiling.
# The convention nudge is mutually exclusive with the other three; those three
# can co-fire, and the hook must then still emit exactly ONE JSON document.
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

```
# fenced comment that looks like a level-1 heading but is inside a fence
```

Post-fence tech note here.

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
  # `-b main` pins the baseline branch name the hook diffs against
  # (`git diff main...HEAD`), independent of the runner's
  # init.defaultBranch — CI ubuntu defaults to `master`, which would leave
  # `main` unresolved and silently break every case. (git 2.28+.)
  git init -q -b main "$d"
  (
    cd "$d"
    git config user.email test@example.com
    git config user.name test
    git config commit.gpgsign false
    write_claude_md "$d"
    mkdir -p .claude/rules .claude/agents Sources
    printf 'rule body\n' > .claude/rules/foo.md
    printf 'agent def body\n' > .claude/agents/reviewer.md
    # A real path-scoped rule: its `paths:` frontmatter must put its added
    # lines in the path-scoped tier, not the always-loaded one.
    cat > .claude/rules/scoped.md <<'SCOPED_RULE'
---
paths:
  - "Sources/**"
---
scoped rule body
SCOPED_RULE
    printf 'let x = 1\n' > Sources/Code.swift
    printf '# README\n\nArchitecture and Tech stack live here.\n' > README.md
    printf '# Contributing\n\nWorkflow and Design principles live here.\n' > CONTRIBUTING.md
    git add -A
    git commit -qm baseline
    git switch -qc feature
  )
}

# Run the hook from inside repo $1, print its stdout, and record exit code
# into the global RC (for the fail-open / exit-0 assertion). Optional $2 sets
# PASTURA_FOOTPRINT_CEILING for that run (fixture repos are far below the
# default ceiling, so the footprint section needs the override to fire).
RC=0
run_hook() {
  local out
  set +e
  out="$( cd "$1" && PASTURA_FOOTPRINT_CEILING="${2:-96000}" bash "$HOOK" )"
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
# assert_single_json LABEL HAYSTACK — the emit contract is ONE JSON object.
# `jq -e 'has(...)'` alone cannot detect a violation: jq streams concatenated
# documents and exits 0 on each, so two docs would pass. Slurping (`-s`) and
# asserting length==1 is what actually reddens on a second document (verified
# against a hand-built two-doc input).
assert_single_json() {
  if ! printf '%s' "$2" | jq -es 'length == 1 and (.[0] | has("hookSpecificOutput"))' >/dev/null 2>&1; then
    echo "FAIL [$1]: expected exactly one JSON object with hookSpecificOutput, got: $2" >&2
    fail=1
  fi
}

CONV="No agent-instruction file"
MIRROR="Reference Documents"
TRIM="Context-economy"
FOOT="Always-loaded instruction footprint"

# --- (a) code-only change → convention nudge -------------------------------
d="$TMP/a"; new_repo "$d"
( cd "$d"; printf 'let y = 2\n' >> Sources/Code.swift; git commit -qam "code" )
out="$(run_hook "$d")"
assert_rc0 a
assert_contains a "$out" "$CONV"
assert_absent a "$out" "$MIRROR"
assert_absent a "$out" "$TRIM"

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
# +11 always-loaded added lines (10 filler + the Tech Stack edit) legitimately
# co-fires the trim nudge here. Asserting both, plus single-JSON, locks in the
# composed-emit contract: sections concatenate, they never emit twice.
assert_contains g "$out" "$TRIM"
assert_single_json g "$out"

# --- (h) ### Git Conventions edit w/o CONTRIBUTING → mirror nudge (CONTRIBUTING) ---
d="$TMP/h"; new_repo "$d"
( cd "$d"; sed -i.bak 's/Branch naming rules./Branch naming updated./' CLAUDE.md; rm -f CLAUDE.md.bak; git commit -qam "gitconv" )
out="$(run_hook "$d")"
assert_rc0 h
assert_contains h "$out" "$MIRROR"
assert_contains h "$out" "CONTRIBUTING.md"
assert_absent h "$out" "README.md"

# --- (i) dual-mirror section (Architecture) w/o either mirror → both named --
d="$TMP/i"; new_repo "$d"
( cd "$d"; sed -i.bak 's/Layer diagram here./Layer diagram v2./' CLAUDE.md; rm -f CLAUDE.md.bak; git commit -qam "arch" )
out="$(run_hook "$d")"
assert_rc0 i
assert_contains i "$out" "$MIRROR"
assert_contains i "$out" "README.md and CONTRIBUTING.md"

# --- (j) dual-mirror w/ ONE mirror synced → nudge only the stale half -------
# Locks in the dual-mirror subtraction: editing Architecture + README (but not
# CONTRIBUTING) must still nudge for the stale CONTRIBUTING.md, not go silent.
d="$TMP/j"; new_repo "$d"
( cd "$d"; sed -i.bak 's/Layer diagram here./Layer diagram v2./' CLAUDE.md; rm -f CLAUDE.md.bak
  printf 'Updated architecture.\n' >> README.md; git commit -qam "arch+readme" )
out="$(run_hook "$d")"
assert_rc0 j
assert_contains j "$out" "$MIRROR"
assert_contains j "$out" "CONTRIBUTING.md"
assert_absent j "$out" "README.md"

# --- (k) edit inside Tech Stack AFTER a fenced `#` line → nudge still fires --
# Proves fence-awareness: the `# ...` line inside the code fence must NOT be
# read as a level-1 heading that prematurely terminates the Tech Stack section.
d="$TMP/k"; new_repo "$d"
( cd "$d"; sed -i.bak 's/Post-fence tech note here./Post-fence tech note updated./' CLAUDE.md; rm -f CLAUDE.md.bak; git commit -qam "postfence" )
out="$(run_hook "$d")"
assert_rc0 k
assert_contains k "$out" "$MIRROR"
assert_contains k "$out" "README.md"

# --- (l) always-loaded growth in a NON-mirrored section → trim nudge only ---
d="$TMP/l"; new_repo "$d"
( cd "$d"
  for i in 1 2 3 4 5 6 7 8 9 10 11 12; do printf -- "- ADR-%03d summary.\n" "$i" >> CLAUDE.md; done
  git commit -qam "adr index growth" )
out="$(run_hook "$d")"
assert_rc0 l
assert_contains l "$out" "$TRIM"
assert_contains l "$out" "+12 always-loaded"
assert_absent l "$out" "$MIRROR"
assert_absent l "$out" "$CONV"
assert_absent l "$out" "$FOOT"
assert_single_json l "$out"

# --- (m) path-scoped rule growth → trim nudge on the path-scoped tier -------
d="$TMP/m"; new_repo "$d"
( cd "$d"
  for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22; do
    printf 'scoped line %d\n' "$i" >> .claude/rules/scoped.md
  done
  git commit -qam "scoped rule growth" )
out="$(run_hook "$d")"
assert_rc0 m
assert_contains m "$out" "$TRIM"
assert_contains m "$out" "+22 path-scoped"
assert_absent m "$out" "$CONV"

# --- (n) below-threshold instruction change → no nudge ---------------------
# foo.md has no `paths:` frontmatter → always-loaded tier, and 3 < 10.
d="$TMP/n"; new_repo "$d"
( cd "$d"
  printf 'extra one\nextra two\nextra three\n' >> .claude/rules/foo.md
  git commit -qam "small rule edit" )
out="$(run_hook "$d")"
assert_rc0 n
assert_empty n "$out"

# --- (o) agents-only growth → trim nudge, convention nudge silenced --------
# Positive control for the widened convention guard: before it included
# `.claude/agents/`, this branch took the convention branch and exited early.
d="$TMP/o"; new_repo "$d"
( cd "$d"
  for i in 1 2 3 4 5 6 7 8 9 10 11 12; do printf 'agent line %d\n' "$i" >> .claude/agents/reviewer.md; done
  git commit -qam "agent growth" )
out="$(run_hook "$d")"
assert_rc0 o
assert_absent o "$out" "$CONV"
assert_contains o "$out" "$TRIM"

# --- (p) footprint nudge (forced ceiling) → footprint only ------------------
d="$TMP/p"; new_repo "$d"
( cd "$d"; sed -i.bak 's/ADR-001 summary./ADR-001 revised./' CLAUDE.md; rm -f CLAUDE.md.bak; git commit -qam "adr" )
out="$(run_hook "$d" 10)"
assert_rc0 p
assert_contains p "$out" "$FOOT"
assert_absent p "$out" "$TRIM"
assert_absent p "$out" "$MIRROR"
assert_single_json p "$out"

if [ "$fail" -eq 0 ]; then
  echo "check-claude-md-modified: all cases passed"
else
  echo "check-claude-md-modified: FAILURES" >&2
  exit 1
fi
