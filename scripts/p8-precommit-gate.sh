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
if git diff --cached --name-only | grep -qE '\.p8$'; then
  {
    echo 'Refusing to commit a *.p8 file — App Store Connect / APNs private'
    echo 'keys must never enter the repo. Store the key outside the tree'
    echo '(fastlane reads ~/.appstoreconnect/private_keys/). See ADR-014 §'
    echo 'Secrets. Unstage it: git restore --staged <file>'
  } >&2
  exit 1
fi
