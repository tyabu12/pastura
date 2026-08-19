#!/usr/bin/env bash
#
# scripts/p8-precommit-gate.sh — Pre-commit gate blocking App Store
# Connect / APNs private keys (*.p8) from ever entering the repo.
#
# Defense-in-depth alongside the `.gitignore` `*.p8` entry: gitignore is
# bypassed by `git add -f` or by a path the ignore rules don't cover,
# whereas this gate inspects the actual staged set and refuses the
# commit. See ADR-014 § Secrets.
#
# A `.p8` in an iOS repo is exclusively an ASC / APNs private key, so a
# hard-fail on any staged `.p8` has effectively zero false-positive
# surface (there is no legitimate in-tree `.p8`).
#
# Tested by scripts/tests/p8-precommit-gate-test.sh.

set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

# Match `.p8` at any path depth — `git diff --cached --name-only` emits
# repo-relative paths, so anchor the regex to the extension, not the
# repo root. A key under keys/ or fastlane/ must still be caught.
#
# Capture the match; never `| grep -q`. `grep -q` exits at its first hit, the
# still-writing producer takes SIGPIPE and returns 141 (in the pre-fix shape
# that producer was `git`; it is `printf` now), and `pipefail` (set above)
# promotes that to the pipeline's status — so a key staged alongside enough
# other paths to outrun the pipe buffer read as "no key" and this gate exited
# 0. Measured: a 91,710-byte staged list with the key sorted first let the key
# through, while the same key on a short list was caught (#1498).
#
# Dropping `-q` is what fixes it, NOT the `STAGED=` capture — re-adding `-q`
# below reinstates the defect on `printf` instead of on `git`. The other gates
# carry a short form of this note; `.claude/rules/ci-workflows.md` § "Rule 3"
# is the canonical account.
#
# `|| [ $? -eq 1 ]` and not `|| true`: exit 1 is grep's real "no match", but
# exit >=2 means the pattern itself broke, and a blanket `|| true` would map
# that back to "no key" — reopening this same silent skip through a different
# door. Letting it fail the assignment under `set -e` refuses the commit
# instead, which is the safe direction for a secret gate.
STAGED="$(git diff --cached --name-only)"
MATCHED="$(printf '%s\n' "$STAGED" | { grep -E '\.p8$' || [ $? -eq 1 ]; })"
if [ -n "$MATCHED" ]; then
  {
    echo 'Refusing to commit a *.p8 file — App Store Connect / APNs private'
    echo 'keys must never enter the repo. Store the key outside the tree'
    echo '(fastlane reads ~/.appstoreconnect/private_keys/). See ADR-014 §'
    echo 'Secrets. Unstage it: git restore --staged <file>'
  } >&2
  exit 1
fi
