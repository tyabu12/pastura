#!/usr/bin/env bash
#
# scripts/tests/navigation-map-precommit-gate-test.sh — regression test for
# scripts/navigation-map-precommit-gate.sh (#652).
#
# Scope: the TRIGGER DECISION only. The gate's actual work
# (`generate-navigation-map.py --check`) needs the full iOS source tree +
# a committed map, which a throwaway repo lacks — so this test stubs
# `python3` on PATH with a marker-touching shim. A marker after the run
# means the gate FIRED (reached the python3 call); no marker means it
# SKIPPED. The reject/fire cases deliberately place a Swift file in a
# NESTED subdir (App/Sub/, Views/Sub/) to lock in the recursive
# `.*\.swift$` trigger — a single-level `[^/]+` regex (copied from the
# gallery gate) would false-skip these and the test would catch it.
#
# CI-wired: the `*-test.sh` naming convention makes this a gate under
# .github/workflows/ci.yml ("Run scripts/tests/*-test.sh"). That runner is
# ubuntu bash 5+, so it does NOT catch a bash-3.2 regression in the gate
# itself — keep the gate 3.2-clean by hand. Run manually:
#   bash scripts/tests/navigation-map-precommit-gate-test.sh

set -euo pipefail

GATE="$(git rev-parse --show-toplevel)/scripts/navigation-map-precommit-gate.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# A python3 shim that records invocation (so "did the gate fire?" is
# observable) and exits 0 regardless of args. Placed first on PATH.
STUB_BIN="$TMP/bin"
mkdir -p "$STUB_BIN"
cat > "$STUB_BIN/python3" <<'STUB'
#!/usr/bin/env bash
touch "$NAVMAP_GATE_MARKER"
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
    NAVMAP_GATE_MARKER="$marker" PATH="$STUB_BIN:$PATH" bash "$GATE" >/dev/null 2>&1
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

# Fires: nested App/ Swift file (locks recursion).
expect "nested App/ swift fires" \
  "$(run_case app_nested Pastura/Pastura/App/Sub/Foo.swift)" fired
# Fires: nested Views/ Swift file (locks recursion).
expect "nested Views/ swift fires" \
  "$(run_case views_nested Pastura/Pastura/Views/Home/Bar.swift)" fired
# Fires: the screenshot-tour table source.
expect "tour table fires" \
  "$(run_case tour Pastura/PasturaUITests/ScreenshotTourTests.swift)" fired
# Fires: the generator script itself.
expect "generator fires" \
  "$(run_case generator scripts/generate-navigation-map.py)" fired
# Fires: a hand-edit of the output map.
expect "output map fires" \
  "$(run_case outmap docs/design/navigation-map.md)" fired

# Skips: an unrelated Swift file outside the scan dirs.
expect "unrelated swift skips" \
  "$(run_case unrelated_swift Pastura/Pastura/Engine/Foo.swift)" skipped
# Skips: a UITests file that is NOT the tour table.
expect "other uitest skips" \
  "$(run_case other_uitest Pastura/PasturaUITests/OtherTests.swift)" skipped
# Skips: a docs file other than the map.
expect "other doc skips" \
  "$(run_case other_doc docs/ROADMAP.md)" skipped
# Skips: a non-swift file inside a scan dir.
expect "non-swift in scan dir skips" \
  "$(run_case nonswift Pastura/Pastura/Views/Home/notes.txt)" skipped

if [ "$fail" -eq 0 ]; then
  echo "navigation-map-precommit-gate: all cases passed"
else
  echo "navigation-map-precommit-gate: FAILURES" >&2
  exit 1
fi
