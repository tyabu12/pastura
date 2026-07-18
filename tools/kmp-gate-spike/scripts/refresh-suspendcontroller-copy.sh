#!/usr/bin/env bash
#
# Refreshes the gate spike's verbatim `SuspendController.swift` copy from the
# real `Pastura/Pastura/LLM/SuspendController.swift`, preserving this package's
# annotation header above the sentinel.
#
# Run this after changing the real file; then commit both.
set -euo pipefail

SENTINEL='// ---8<--- VERBATIM COPY BELOW ---8<---'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$PACKAGE_ROOT/../.." && pwd)"

REAL="$REPO_ROOT/Pastura/Pastura/LLM/SuspendController.swift"
COPY="$PACKAGE_ROOT/Sources/KMPGateSpike/SuspendController.swift"

if [ ! -f "$REAL" ]; then
  echo "error: real file is missing: $REAL" >&2
  exit 1
fi
if ! grep -qxF "$SENTINEL" "$COPY"; then
  echo "error: sentinel line not found in $COPY — refusing to overwrite." >&2
  exit 1
fi

TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

# Header = everything up to and including the sentinel.
awk -v s="$SENTINEL" '{ print } $0 == s { exit }' "$COPY" >"$TMP"
cat "$REAL" >>"$TMP"
mv "$TMP" "$COPY"
trap - EXIT

echo "Refreshed $COPY from $REAL."
"$SCRIPT_DIR/check-suspendcontroller-drift.sh"
