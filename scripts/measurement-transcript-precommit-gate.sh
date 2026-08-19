#!/usr/bin/env bash
#
# scripts/measurement-transcript-precommit-gate.sh — Pre-commit gate for the
# measured-contrast transcript check (#1488). Runs
# `python3 scripts/check-measurement-transcripts.py --self-test` then `--check`
# only when the staged diff touches a file the check reads, mirroring how the
# other checker-backed sub-gates self-gate on their own inputs.
#
# Why the check exists: `muted-application-audit.md` §3.2 declares itself "a
# transcript rather than a second source", and §3.1's table, ADR-028's four-row
# copy of the wash table and three copies of the twelve-ground span all restate
# figures the fixture computes. None of it was checked — every `#expect` in
# `DesignTokensTests+MutedAsContent` was an inequality, an ordering or a count,
# so that file named no figure to transcribe FROM. #1488 adds the pins (in the sibling
# `DesignTokensTests+MutedTranscript`); this gate is what makes them reach the
# docs.
#
# Trigger scope is every file the checker reads, plus the checker itself — a
# commit touching none of them cannot move any of these figures, so it skips.
# CI keeps its own copy (defense in depth).
#
# Note the asymmetry with the fixture's own test arm: the arm fires when the
# PALETTE moves (a recomputed ratio no longer matches its pin) and needs the
# simulator; this gate fires when a DOC moves away from the pins and needs only
# python3. Neither subsumes the other, and a palette retune reddens both.
#
# bash 3.2 portable — ships to dev macOS via the pre-commit hook. NO
# mapfile/readarray, declare -A, ${var^^}, or <<< here-strings.

set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

# The checker asserts, in `--self-test`, that every path it reads matches this
# regex — including this file, which it reads for exactly that arm. Two lists
# DO exist (this one and the checker's `*_PATH` constants); what keeps them
# together is that arm, not the fact that the regex is written once.
TRIGGER='(^docs/design/muted-application-audit\.md$)|(^docs/design/design-system\.md$)|(^docs/decisions/ADR-028\.md$)|(^Pastura/PasturaTests/Views/DesignTokensTests\+MutedTranscript\.swift$)|(^scripts/check-measurement-transcripts\.py$)|(^scripts/measurement-transcript-precommit-gate\.sh$)'

# NOT `git diff --cached --name-only | grep -qE`, which fails OPEN under the
# `pipefail` above. `-q` makes grep exit at the first match; the producer then
# dies on SIGPIPE (141), `pipefail` promotes that to the pipeline status, and
# the gate skips a changeset that DID match. Needs a staged list bigger than the
# pipe buffer, so it is rare — but it is silent and in the wrong direction.
# Dropping `-q` is what fixes it — capturing first does NOT: `printf "$staged" |
# grep -q` SIGPIPEs identically, with printf as the victim (measured both ways,
# with a no-match control, #1488). Without `-q` grep consumes all input, so
# nothing can die early.
# The capture is still not redundant, so don't "simplify" this back to one
# pipeline: `git … | grep -E … || true` would swallow a git failure and skip,
# which is the same fail-open by another route. `STAGED="$(…)"` under `set -e`
# aborts on it instead.
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

# --self-test validates the extractors and every anchor on synthetic fixtures
# (each anchor arm asserts WHICH anchor fired, not merely that one did);
# --check gates the real tree.
python3 scripts/check-measurement-transcripts.py --self-test
python3 scripts/check-measurement-transcripts.py --check
