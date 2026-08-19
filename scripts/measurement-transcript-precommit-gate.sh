#!/usr/bin/env bash
#
# scripts/measurement-transcript-precommit-gate.sh — Pre-commit gate for the
# measured-contrast transcript check (#1488). Runs
# `scripts/check-measurement-transcripts.py --self-test` then `--check` when the
# staged diff touches a file the check reads, plus the checker itself. Rationale
# for the check: that script's module docstring. CI keeps its own copy.
#
# Note the asymmetry with the fixture's own test arm: the arm fires when the
# PALETTE moves and needs the simulator; this gate fires when a DOC moves away
# from the pins and needs only python3. Neither subsumes the other.
#
# bash 3.2 portable — ships to dev macOS via the pre-commit hook. NO
# mapfile/readarray, declare -A, ${var^^}, or <<< here-strings.

set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

# The checker asserts, in `--self-test`, that every path it reads matches this
# regex — including this file, which it reads for exactly that arm. That arm is
# what holds this list and the checker's `*_PATH` constants together.
TRIGGER='(^docs/design/muted-application-audit\.md$)|(^docs/design/design-system\.md$)|(^docs/decisions/ADR-028\.md$)|(^Pastura/PasturaTests/Views/DesignTokensTests\+MutedTranscript\.swift$)|(^scripts/check-measurement-transcripts\.py$)|(^scripts/measurement-transcript-precommit-gate\.sh$)'

# Two fail-opens this shape avoids; don't "simplify" either away.
# NOT `... | grep -qE`: `-q` exits at the first match, the producer dies on
# SIGPIPE (141), `pipefail` promotes it, and a MATCHING changeset skips. Only
# fires when the staged list exceeds the pipe buffer. Capturing first does not
# help (printf SIGPIPEs identically) — dropping `-q` is what does, since grep
# then consumes all input. Arm: scripts/tests/measurement-transcript-gate-test.sh
# NOT `git … | grep -E … || true`: that swallows a git failure and skips too.
# `STAGED="$(…)"` under `set -e` aborts on it instead.
# The same shape is in 13 sibling gates and is left to one sweep — see #1498.
STAGED="$(git diff --cached --name-only)"
MATCHED="$(printf '%s\n' "$STAGED" | grep -E "$TRIGGER" || true)"
if [ -z "$MATCHED" ]; then
  exit 0
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo 'measurement-transcript gate: python3 not found — install the Xcode' >&2
  echo 'Command Line Tools (xcode-select --install). The gate needs it.' >&2
  exit 1
fi

# --self-test validates the extractors and every anchor on synthetic fixtures;
# --check gates the real tree.
python3 scripts/check-measurement-transcripts.py --self-test
python3 scripts/check-measurement-transcripts.py --check
