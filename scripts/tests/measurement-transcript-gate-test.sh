#!/usr/bin/env bash
#
# scripts/tests/measurement-transcript-gate-test.sh — regression test for
# scripts/measurement-transcript-precommit-gate.sh (#1488).
#
# Scope: the TRIGGER DECISION only. This test does NOT restate the gate's
# TRIGGER regex anywhere — the gate script is the single copy of it. This
# test only stages paths in a throwaway repo and observes what the gate
# does, via a python3 PATH stub.
#
# Why the marker, not the exit code: both the fired and skipped arms exit 0
# (the gate's trigger check is `exit 0` on no match, and the stub itself
# exits 0), so an exit-code-based test would pass vacuously on a gate that
# never runs. The marker file — touched only by the stub, only when the
# gate actually invokes python3 — is what makes "ran / did not run"
# observable.
#
# CI-wired: the `*-test.sh` naming convention makes this a gate under
# .github/workflows/ci.yml ("Run scripts/tests/*-test.sh", Shell gate
# tests job — ubuntu, no Xcode/Swift). That runner is bash 5+, so it does
# NOT catch a bash-3.2 regression in the gate itself — keep the gate 3.2
# clean by hand. Run manually:
#   bash scripts/tests/measurement-transcript-gate-test.sh

set -euo pipefail

GATE="$(git rev-parse --show-toplevel)/scripts/measurement-transcript-precommit-gate.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# A python3 shim that records invocation (so "did the gate fire?" is
# observable) and exits 0 regardless of args. Placed first on PATH.
STUB_BIN="$TMP/bin"
mkdir -p "$STUB_BIN"
cat > "$STUB_BIN/python3" <<'STUB'
#!/usr/bin/env bash
touch "$MEASUREMENT_GATE_MARKER"
exit 0
STUB
chmod +x "$STUB_BIN/python3"

fail=0

# Run the gate inside a throwaway repo with a given staged file, with the
# python3 stub on PATH. Echoes "fired" or "skipped" based on the marker.
# Args: <repo-name> <path-to-stage>
run_case() {
  repo="$TMP/$1"
  staged="$2"
  marker="$TMP/$1.marker"
  git init -q "$repo"
  (
    cd "$repo"
    git config user.email test@example.com
    git config user.name test
    mkdir -p "$(dirname "$staged")"
    : > "$staged"
    git add -f "$staged"
    MEASUREMENT_GATE_MARKER="$marker" PATH="$STUB_BIN:$PATH" bash "$GATE" >/dev/null 2>&1
  )
  if [ -f "$marker" ]; then echo "fired"; else echo "skipped"; fi
}

expect() {
  desc="$1"; got="$2"; want="$3"
  if [ "$got" != "$want" ]; then
    echo "FAIL: $desc — expected $want, got $got" >&2
    fail=1
  fi
}

# --- Fires: the five files the checker reads, plus the checker itself. ---
expect "muted-application-audit.md fires" \
  "$(run_case audit docs/design/muted-application-audit.md)" fired
expect "design-system.md fires" \
  "$(run_case designsys docs/design/design-system.md)" fired
expect "ADR-028.md fires" \
  "$(run_case adr028 docs/decisions/ADR-028.md)" fired
expect "DesignTokensTests+MutedAsContent.swift fires" \
  "$(run_case fixture Pastura/PasturaTests/Views/DesignTokensTests+MutedAsContent.swift)" fired
expect "checker script fires" \
  "$(run_case checker scripts/check-measurement-transcripts.py)" fired

# --- Skips: each locks a specific escape in the TRIGGER regex. ---

# Unrelated file entirely.
expect "unrelated README skips" \
  "$(run_case readme README.md)" skipped
# Sibling ADR — the ADR-028 alternative must not swallow neighbors.
expect "sibling ADR-029 skips" \
  "$(run_case adr029 docs/decisions/ADR-029.md)" skipped
# Sibling fixture in the same directory — the +MutedAsContent suffix must
# be exact, not a prefix match.
expect "sibling fixture NightPalette skips" \
  "$(run_case nightpalette Pastura/PasturaTests/Views/DesignTokensTests+NightPalette.swift)" skipped
# The OTHER checker's script — the checker filename must be exact.
expect "other checker script skips" \
  "$(run_case otherchecker scripts/check-mossink-wash-membership.py)" skipped
# Locks the `\.` escape in design-system\.md — an unescaped `.` would match
# any single character here, including the literal `X`.
expect "design-systemXmd locks dot escape, skips" \
  "$(run_case dotescape docs/design/design-systemXmd)" skipped
# Locks the `\+` escape in DesignTokensTests\+MutedAsContent. The `+` must be
# DELETED, not substituted: unescaped, `s+` is ERE one-or-more, so
# `DesignTokensTestsXMutedAsContent` fails to match either way and would be a
# control that cannot redden. With the separator simply gone, an unescaped `+`
# matches (`s+` consumes the single `s`) and an escaped one does not —
# measured both ways.
expect "TestsMutedAsContent locks plus escape, skips" \
  "$(run_case plusescape Pastura/PasturaTests/Views/DesignTokensTestsMutedAsContent.swift)" skipped
# Locks the trailing `$` anchor — without it, a suffixed filename like a
# .bak backup would still match.
expect "muted-application-audit.md.bak locks trailing anchor, skips" \
  "$(run_case trailinganchor docs/design/muted-application-audit.md.bak)" skipped

if [ "$fail" -eq 0 ]; then
  echo "measurement-transcript-gate: all cases passed"
else
  echo "measurement-transcript-gate: FAILURES" >&2
  exit 1
fi
