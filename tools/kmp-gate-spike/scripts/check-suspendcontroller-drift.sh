#!/usr/bin/env bash
#
# Fails if the gate spike's `SuspendController.swift` copy has drifted from the
# real `Pastura/Pastura/LLM/SuspendController.swift`.
#
# The copy exists because SwiftPM rejects a target source path escaping the
# package root (see the copy's own header). Its value as gate evidence rests
# entirely on being byte-identical: ADR-023 §5.2 invariant 3 (lost-wakeup
# safety) is only witnessed if the object under test is the real one. A
# one-sided edit on either file silently downgrades that claim, so this guard
# is what keeps the claim honest.
#
# Everything after the sentinel line must match the real file exactly; the
# header above it is this package's own annotation and is excluded.
set -euo pipefail

SENTINEL='// ---8<--- VERBATIM COPY BELOW ---8<---'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$PACKAGE_ROOT/../.." && pwd)"

REAL="$REPO_ROOT/Pastura/Pastura/LLM/SuspendController.swift"
COPY="$PACKAGE_ROOT/Sources/KMPGateSpike/SuspendController.swift"

for f in "$REAL" "$COPY"; do
  if [ ! -f "$f" ]; then
    echo "error: expected file is missing: $f" >&2
    exit 1
  fi
done

if ! grep -qxF "$SENTINEL" "$COPY"; then
  echo "error: sentinel line not found in $COPY" >&2
  echo "       expected a line reading exactly: $SENTINEL" >&2
  echo "       Without it this guard cannot tell the header from the copy." >&2
  exit 1
fi

# Everything strictly after the sentinel.
# awk with an exact string compare, not sed: the sentinel begins with '//',
# and that '/' terminates a sed address regex (BSD sed: "invalid command
# code /"). That failure mode is quiet in the worst way — extraction yields
# nothing, the diff shows the whole file as removed, and the guard "fails"
# on a perfectly clean copy.
if diff -u "$REAL" <(awk -v s="$SENTINEL" 'found { print } $0 == s { found = 1 }' "$COPY"); then
  echo "SuspendController copy is byte-identical to the real file."
  exit 0
fi

cat >&2 <<'DRIFT'

error: SuspendController drift detected (diff above: real file vs. spike copy).

The spike copy must stay byte-identical below its sentinel. If you changed the
real file, refresh the copy:

  tools/kmp-gate-spike/scripts/refresh-suspendcontroller-copy.sh

If you changed the COPY: don't. Edit the real file instead — the copy is gate
evidence for ADR-023 §5.2 invariant 3, and a hand-edited copy is no longer
evidence for anything.
DRIFT
exit 1
