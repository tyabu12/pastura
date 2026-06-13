#!/bin/bash
# Self-test for the consistency-audit detector. No Swift toolchain or network
# needed — exercises the three fixture repos (clean / drift / judgment)
# against audit_docs.py, including the must-NOT-fire regression set and the
# Package.resolved version-vs-revision trap.
#
# usage: bash .claude/skills/consistency-audit/tests/run_tests.sh
# requires: python3, jq
set -eu
cd "$(dirname "$0")"
AUDIT=../scripts/audit_docs.py
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

fail() { echo "FAIL: $1" >&2; exit 1; }
af_len() { echo "$1" | jq '.auto_fixable | length'; }
nj_len() { echo "$1" | jq '.needs_judgment | length'; }

# --- clean fixture: zero findings (doubles as the must-NOT-fire set) --------
OUT=$(python3 "$AUDIT" --repo-root fixtures/clean \
  --package-resolved fixtures/clean/Package.resolved \
  --pbxproj fixtures/clean/pbxproj.txt)
[ "$(af_len "$OUT")" -eq 0 ] || fail "clean: auto_fixable not empty: $(echo "$OUT" | jq -c .auto_fixable)"
[ "$(nj_len "$OUT")" -eq 0 ] || fail "clean: needs_judgment not empty: $(echo "$OUT" | jq -c .needs_judgment)"

# --- drift fixture: three auto_fixable, no judgment -------------------------
OUT=$(python3 "$AUDIT" --repo-root fixtures/drift \
  --package-resolved fixtures/drift/Package.resolved \
  --pbxproj fixtures/drift/pbxproj.txt)
[ "$(af_len "$OUT")" -eq 3 ] || fail "drift: expected 3 auto_fixable, got $(af_len "$OUT")"
[ "$(nj_len "$OUT")" -eq 0 ] || fail "drift: needs_judgment not empty: $(echo "$OUT" | jq -c .needs_judgment)"
# the fixes must come from the resolved "version" (GRDB 7.11.0 / Yams 6.2.2)...
echo "$OUT" | jq -e '.auto_fixable[] | select(.dependency=="GRDB" and .expected=="7.11.0")' >/dev/null \
  || fail "drift: GRDB expected value is not 7.11.0"
echo "$OUT" | jq -e '.auto_fixable[] | select(.dependency=="Yams" and .expected=="6.2.2")' >/dev/null \
  || fail "drift: Yams expected value is not 6.2.2"
# ...never a git "revision": every dependency expected must be a clean semver
# (positive allowlist, so a SHA of any length — not just 12+ hex — fails).
if echo "$OUT" | jq -e '.auto_fixable[] | select(.type=="dependency_version") | select((.expected|test("^[0-9]+\\.[0-9]+\\.[0-9]+$"))|not)' >/dev/null; then
  fail "drift: a dependency expected value is not a clean semver (revision leak?)"
fi

# --- --fix applies the version edits in place, leaving zero drift ----------
cp -R fixtures/drift "$TMP/drift"
python3 "$AUDIT" --repo-root "$TMP/drift" \
  --package-resolved "$TMP/drift/Package.resolved" \
  --pbxproj "$TMP/drift/pbxproj.txt" --fix >/dev/null
grep -qF "| Yams | 6.2.2 |" "$TMP/drift/CLAUDE.md" || fail "--fix: Yams table row not rewritten"
grep -qF "| GRDB | 7.11.0 |" "$TMP/drift/CLAUDE.md" || fail "--fix: GRDB table row not rewritten"
grep -qF "| Min iOS | 17.0 |" "$TMP/drift/CLAUDE.md" || fail "--fix: Min iOS table row not rewritten"
OUT=$(python3 "$AUDIT" --repo-root "$TMP/drift" \
  --package-resolved "$TMP/drift/Package.resolved" \
  --pbxproj "$TMP/drift/pbxproj.txt")
[ "$(af_len "$OUT")" -eq 0 ] || fail "--fix: drift remains after fix: $(echo "$OUT" | jq -c .auto_fixable)"

# --- boundary: --fix splices at the offset, never str.replace -------------
# The stale value also appears inside the non-bounded token `v7.10.0x`, which
# a boundary-unaware replace would corrupt while leaving the real drift.
cp -R fixtures/boundary "$TMP/boundary"
OUT=$(python3 "$AUDIT" --repo-root "$TMP/boundary" \
  --package-resolved "$TMP/boundary/Package.resolved")
[ "$(af_len "$OUT")" -eq 1 ] || fail "boundary: expected 1 auto_fixable, got $(af_len "$OUT")"
python3 "$AUDIT" --repo-root "$TMP/boundary" \
  --package-resolved "$TMP/boundary/Package.resolved" --fix >/dev/null
grep -qF "v7.10.0x" "$TMP/boundary/CLAUDE.md" \
  || fail "boundary: --fix corrupted the non-bounded token v7.10.0x"
grep -qF "version 7.11.0" "$TMP/boundary/CLAUDE.md" \
  || fail "boundary: --fix did not correct the bounded version token"
OUT=$(python3 "$AUDIT" --repo-root "$TMP/boundary" \
  --package-resolved "$TMP/boundary/Package.resolved")
[ "$(af_len "$OUT")" -eq 0 ] || fail "boundary: drift remains after offset fix"

# --- judgment fixture: two dead_link findings, missing sources tolerated ----
# Also the must-NOT-fire negatives: working link, external link, reserved-line
# link, and a fenced link are all present and must stay silent.
OUT=$(python3 "$AUDIT" --repo-root fixtures/judgment)
[ "$(af_len "$OUT")" -eq 0 ] || fail "judgment: auto_fixable should be empty when sources are absent"
[ "$(nj_len "$OUT")" -eq 2 ] || fail "judgment: expected 2 needs_judgment, got $(nj_len "$OUT"): $(echo "$OUT" | jq -c .needs_judgment)"
[ "$(echo "$OUT" | jq '[.needs_judgment[] | select(.type=="dead_link")] | length')" -eq 2 ] \
  || fail "judgment: both findings should be dead_link"
echo "$OUT" | jq -e '.needs_judgment[] | select(.target=="docs/missing-a.md")' >/dev/null \
  || fail "judgment: missing-a.md dead link not found"

echo "ALL TESTS PASSED"
