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
HERE=$(pwd)
AUDIT=../scripts/audit_docs.py
DIGEST=../scripts/append_digest.py
DIGEST_ABS="$HERE/../scripts/append_digest.py"
RESULTS_ABS="$HERE/fixtures/results_sample.json"
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

# --- append_digest.py: append / counts / status rendering -----------------
cp fixtures/digest_seed.md "$TMP/digest.md"
python3 "$DIGEST" --results fixtures/results_sample.json --digest "$TMP/digest.md" >/dev/null
grep -qF "## 2026-06-13 14:00" "$TMP/digest.md" || fail "digest: section heading missing"
grep -qF "Dry-run: auto_fixable 1, needs_judgment 0" "$TMP/digest.md" || fail "digest: counts line missing"
grep -qF "Auto-fix PR: https://github.com/tyabu12/pastura/pull/553" "$TMP/digest.md" || fail "digest: opened-PR line missing"
grep -qF "Issues filed: none" "$TMP/digest.md" || fail "digest: issues line missing"

# append-only: re-applying the same run_id is rejected, never duplicated
if python3 "$DIGEST" --results fixtures/results_sample.json --digest "$TMP/digest.md" 2>/dev/null; then
  fail "digest: duplicate run_id should be rejected"
fi
[ "$(grep -c '## 2026-06-13 14:00' "$TMP/digest.md")" -eq 1 ] || fail "digest: duplicate run_id leaked a second section"

# corrupted digest (no marker) hard-errors instead of blind-appending
printf '# broken, no marker\n' > "$TMP/broken.md"
if python3 "$DIGEST" --results fixtures/results_sample.json --digest "$TMP/broken.md" 2>/dev/null; then
  fail "digest: missing marker should hard-error"
fi

# a status that implies a PR must carry its url (no bare "None" sections)
cat > "$TMP/nopr.json" <<'JSON'
{ "run_id": "2026-06-13 16:00", "auto_fixable": 1, "needs_judgment": 0,
  "auto_fix_status": "opened", "auto_fix_pr": null, "issues": [] }
JSON
if python3 "$DIGEST" --results "$TMP/nopr.json" --digest "$TMP/digest.md" 2>/dev/null; then
  fail "digest: opened status without auto_fix_pr should be rejected"
fi

# skipped-open-audit-pr status names the blocking PR; sections stay newest-first
cat > "$TMP/skip.json" <<'JSON'
{ "run_id": "2026-06-13 15:00", "auto_fixable": 1, "needs_judgment": 0,
  "auto_fix_status": "skipped-open-audit-pr",
  "auto_fix_pr": "https://github.com/tyabu12/pastura/pull/553", "issues": [] }
JSON
python3 "$DIGEST" --results "$TMP/skip.json" --digest "$TMP/digest.md" >/dev/null
grep -qF "skipped — open audit PR https://github.com/tyabu12/pastura/pull/553 still pending" "$TMP/digest.md" \
  || fail "digest: skipped-open-audit-pr status not rendered"
awk '/## 2026-06-13 15:00/{a=NR} /## 2026-06-13 14:00/{b=NR} END{exit !(a && b && a<b)}' "$TMP/digest.md" \
  || fail "digest: sections not newest-first"

# --- resolver refuses an untracked target (safety guard, no --digest) ------
# Exercises resolve_main_digest()'s "must be git-tracked" guard — the
# production-relevant branch for worktree-based scheduled runs.
RR="$TMP/resolver"; mkdir -p "$RR/data/audit"
git -C "$RR" init -q
git -C "$RR" -c user.email=t@example.com -c user.name=t commit -q --allow-empty -m init
printf 'x\n' > "$RR/data/audit/digest.md"   # exists but UNTRACKED
if ERR=$( cd "$RR" && python3 "$DIGEST_ABS" --results "$RESULTS_ABS" 2>&1 >/dev/null ); then
  fail "resolver: must refuse to write an untracked digest target"
fi
echo "$ERR" | grep -q "not tracked" || fail "resolver: expected the 'not tracked' guard, got: $ERR"

# --- preflight clean-tree pathspec excludes the digest (critic Axis 5) ------
# Pins the exact `git status` pathspec SKILL.md Step 0.5 uses, so a digest left
# modified by a prior unattended run does not self-block the next run, while a
# real change still aborts. Proves two consecutive runs need no intervening commit.
TR="$TMP/repo"; mkdir -p "$TR/data/audit"
git -C "$TR" init -q
printf 'seed\n' > "$TR/data/audit/digest.md"; printf 'x\n' > "$TR/other.txt"
git -C "$TR" add -A
git -C "$TR" -c user.email=t@example.com -c user.name=t commit -qm init
printf 'appended by prior run\n' >> "$TR/data/audit/digest.md"   # digest-only change
OUT=$(git -C "$TR" status --porcelain -- . ':(exclude)data/audit/digest.md')
[ -z "$OUT" ] || fail "preflight: a digest-only modification must read as clean (got: $OUT)"
printf 'real edit\n' >> "$TR/other.txt"                          # a non-digest change too
OUT=$(git -C "$TR" status --porcelain -- . ':(exclude)data/audit/digest.md')
[ -n "$OUT" ] || fail "preflight: a non-digest modification must still read as dirty"

echo "ALL TESTS PASSED"
