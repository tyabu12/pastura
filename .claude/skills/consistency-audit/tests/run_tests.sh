#!/bin/bash
# Self-test for the consistency-audit detector. No Swift toolchain or network
# needed — exercises the fixture repos (clean / drift / judgment / boundary /
# adr) against audit_docs.py, including the must-NOT-fire regression set, the
# Package.resolved version-vs-revision trap, and the dangling-ADR reserved-set
# / first-cell-keying guards.
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
nj_type_len() { echo "$1" | jq --arg t "$2" '[.needs_judgment[] | select(.type==$t)] | length'; }
# The SKILL's Step 4 cross-run dedup is `gh issue list --search "<target>
# in:title"` — type-blind, so two finding types sharing a target silently
# suppress each other across runs. Asserted per fixture, not just where two
# types happen to fire today.
no_target_collision() {
  local n
  n=$(echo "$1" | jq '[.needs_judgment[] | {t:.type, g:.target}] | group_by(.g)
                      | map(select((map(.t) | unique | length) > 1)) | length')
  [ "$n" -eq 0 ] || fail "$2: $n target(s) shared across finding types (Step 4 dedup is type-blind): $(echo "$1" | jq -c '[.needs_judgment[]|{type,target}]')"
}

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
# dead_link's post-dedup shape must stay exactly {type, target, locations} —
# genericizing dedup_judgment for dangling_adr must not leak the ADR-only
# scalars (adr / confidence / ...) onto a dead_link finding.
echo "$OUT" | jq -e '.needs_judgment[] | select(.type=="dead_link") | select(has("adr") or has("confidence") or has("key") or has("file") or has("line"))' >/dev/null \
  && fail "judgment: dead_link finding leaked a non-dead_link/per-occurrence key" || true
echo "$OUT" | jq -e '[.needs_judgment[] | select(.type=="dead_link") | (has("target") and has("locations"))] | all' >/dev/null \
  || fail "judgment: a dead_link finding is missing target/locations"

# --- adr fixture: dangling ADR flagged; reserved / existing / fenced silent --
# ADR-099 (no file, no reserved row) and ADR-005 (only in the ADR-006 row's
# description — first-cell keying reserves 006, not 005) fire; ADR-006 (reserved
# set), ADR-001 (existing file), ADR-098 (inline marker) and ADR-097 (fenced)
# stay silent.
OUT=$(python3 "$AUDIT" --repo-root fixtures/adr)
[ "$(af_len "$OUT")" -eq 0 ] || fail "adr: auto_fixable should be empty: $(echo "$OUT" | jq -c .auto_fixable)"
DAD_LEN=$(echo "$OUT" | jq '[.needs_judgment[] | select(.type=="dangling_adr")] | length')
[ "$DAD_LEN" -eq 2 ] || fail "adr: expected 2 dangling_adr, got $DAD_LEN: $(echo "$OUT" | jq -c '[.needs_judgment[]|select(.type=="dangling_adr").adr]')"
echo "$OUT" | jq -e '.needs_judgment[] | select(.type=="dangling_adr" and .adr=="ADR-099")' >/dev/null \
  || fail "adr: dangling ADR-099 not flagged"
echo "$OUT" | jq -e '.needs_judgment[] | select(.type=="dangling_adr" and .adr=="ADR-005")' >/dev/null \
  || fail "adr: ADR-005 (first-cell-keying regression) not flagged"
# the must-NOT-fire set: reserved subject, existing file, inline-marked, fenced.
for silent in ADR-006 ADR-001 ADR-098 ADR-097; do
  echo "$OUT" | jq -e ".needs_judgment[] | select(.type==\"dangling_adr\" and .adr==\"$silent\")" >/dev/null \
    && fail "adr: $silent should NOT be flagged" || true
done
# every dangling_adr finding carries the detector-authored judgment scalars +
# a target aliasing the ADR id (Step 4 `<target> in:title` dedup depends on it).
echo "$OUT" | jq -e '[.needs_judgment[] | select(.type=="dangling_adr") | (has("adr") and has("target") and has("confidence") and has("counter_evidence") and has("suggested_action") and (.target==.adr))] | all' >/dev/null \
  || fail "adr: a dangling_adr finding is missing its judgment scalars or target!=adr"
# The reservation canary must stay SILENT here: the ADR-006 row parses, so the
# reserved set is non-empty and shape (a) is gated off — which is what keeps
# ADR-098's legitimate inline "(reserved — not yet written)" mention quiet.
# Without that gate the canary would fire on every inline-marked reference.
[ "$(nj_type_len "$OUT" unparsed_adr_reservation)" -eq 0 ] \
  || fail "adr: unparsed_adr_reservation must stay silent when the row parses: $(echo "$OUT" | jq -c '[.needs_judgment[]|select(.type=="unparsed_adr_reservation")]')"

# --- adr-reservation-reshaped: negative control for the table-row shape -----
# The `adr` fixture above asserts ADR-006 stays SILENT when its reservation is
# a table row — a success case, which passes whether or not load_reserved_adrs
# actually requires that shape. This fixture is the negative control: the same
# reservation in prose (marker + ADR-006, no `|`, no path cell) must NOT be
# absorbed, so ADR-006 fires. Without it the shape requirement is asserted by
# nobody, which is how PR #1310 shipped the regression this fixture reproduces.
OUT=$(python3 "$AUDIT" --repo-root fixtures/adr-reservation-reshaped)
[ "$(af_len "$OUT")" -eq 0 ] || fail "reshaped: auto_fixable should be empty: $(echo "$OUT" | jq -c .auto_fixable)"
RSH_DAD=$(echo "$OUT" | jq '[.needs_judgment[] | select(.type=="dangling_adr")] | length')
[ "$RSH_DAD" -eq 1 ] || fail "reshaped: expected 1 dangling_adr, got $RSH_DAD: $(echo "$OUT" | jq -c '[.needs_judgment[]|select(.type=="dangling_adr").adr]')"
echo "$OUT" | jq -e '.needs_judgment[] | select(.type=="dangling_adr" and .adr=="ADR-006")' >/dev/null \
  || fail "reshaped: ADR-006 must be flagged when its reservation is not in table-row shape"
echo "$OUT" | jq -e '.needs_judgment[] | select(.type=="dangling_adr" and .adr=="ADR-001")' >/dev/null \
  && fail "reshaped: ADR-001 resolves to a file and must NOT be flagged" || true
# ...and the canary that explains the flood fires alongside it, via shape (a):
# a marker line naming a fileless ADR while the reserved set came back empty.
[ "$(nj_type_len "$OUT" unparsed_adr_reservation)" -eq 1 ] \
  || fail "reshaped: expected 1 unparsed_adr_reservation, got $(nj_type_len "$OUT" unparsed_adr_reservation)"
echo "$OUT" | jq -e '.needs_judgment[] | select(.type=="unparsed_adr_reservation" and .adr=="ADR-006" and .shape=="marker-not-in-table-row" and .target=="reservation:ADR-006")' >/dev/null \
  || fail "reshaped: unparsed_adr_reservation missing, mis-shaped, or not namespaced: $(echo "$OUT" | jq -c '[.needs_judgment[]|select(.type=="unparsed_adr_reservation")]')"
no_target_collision "$OUT" "reshaped"

# --- adr-reservation-deleted: the canary's second shape ---------------------
# Next compaction step after `reshaped`: the reservation prose is gone from
# CLAUDE.md entirely, so scanning it for marker words finds nothing. INDEX.md
# still lists the ADR with no file behind it, which shape (b) keys on — no
# empty-reserved-set gate needed, since that combination is unambiguous.
OUT=$(python3 "$AUDIT" --repo-root fixtures/adr-reservation-deleted)
[ "$(af_len "$OUT")" -eq 0 ] || fail "deleted: auto_fixable should be empty: $(echo "$OUT" | jq -c .auto_fixable)"
[ "$(nj_type_len "$OUT" unparsed_adr_reservation)" -eq 1 ] \
  || fail "deleted: expected 1 unparsed_adr_reservation, got $(nj_type_len "$OUT" unparsed_adr_reservation)"
echo "$OUT" | jq -e '.needs_judgment[] | select(.type=="unparsed_adr_reservation" and .adr=="ADR-006" and .shape=="listed-in-index")' >/dev/null \
  || fail "deleted: ADR-006 must fire via the INDEX listing: $(echo "$OUT" | jq -c '[.needs_judgment[]|select(.type=="unparsed_adr_reservation")]')"
echo "$OUT" | jq -e '.needs_judgment[] | select(.type=="unparsed_adr_reservation" and .adr=="ADR-001")' >/dev/null \
  && fail "deleted: ADR-001 is backed by a file and must NOT fire" || true
no_target_collision "$OUT" "deleted"
# every unparsed_adr_reservation carries the pre-authored judgment scalars the
# SKILL's Step 4 uses verbatim, and a namespaced target (never a bare ADR id).
echo "$OUT" | jq -e '[.needs_judgment[] | select(.type=="unparsed_adr_reservation") | (has("adr") and has("shape") and has("confidence") and has("counter_evidence") and has("suggested_action") and (.target == "reservation:" + .adr))] | all' >/dev/null \
  || fail "deleted: an unparsed_adr_reservation finding is missing its judgment scalars or namespaced target"

# --- roster fixture: three-way roster / INDEX / on-disk drift ---------------
# FIRE: 002 (on disk + indexed, never rostered — the "author skipped the
# roster" case), 003 (on disk + rostered, never indexed), 007 (title edited on
# one side), 099 (rostered with no file and no reserved row).
# SILENT: 001 (agrees everywhere), 006 (listed everywhere, no file, reserved
# row present — the same subtraction dangling_adr performs), 016 (its title
# carries an em dash *after* the heading separator; splitting anywhere but the
# first separator corrupts it into a title mismatch).
OUT=$(python3 "$AUDIT" --repo-root fixtures/roster)
[ "$(af_len "$OUT")" -eq 0 ] || fail "roster: auto_fixable should be empty: $(echo "$OUT" | jq -c .auto_fixable)"
[ "$(nj_len "$OUT")" -eq 4 ] || fail "roster: expected 4 findings total, got $(nj_len "$OUT"): $(echo "$OUT" | jq -c '[.needs_judgment[]|{type,target}]')"
[ "$(nj_type_len "$OUT" adr_roster_drift)" -eq 4 ] \
  || fail "roster: all 4 findings should be adr_roster_drift, got $(nj_type_len "$OUT" adr_roster_drift)"
for want in ADR-002 ADR-003 ADR-007 ADR-099; do
  echo "$OUT" | jq -e --arg a "$want" '.needs_judgment[] | select(.type=="adr_roster_drift" and .adr==$a)' >/dev/null \
    || fail "roster: expected a drift finding for $want"
done
for silent in ADR-001 ADR-006 ADR-016; do
  echo "$OUT" | jq -e --arg a "$silent" '.needs_judgment[] | select(.type=="adr_roster_drift" and .adr==$a)' >/dev/null \
    && fail "roster: $silent should NOT be flagged" || true
done
echo "$OUT" | jq -e '.needs_judgment[] | select(.adr=="ADR-002") | .problems | any(test("missing from the CLAUDE.md ADR roster"))' >/dev/null \
  || fail "roster: ADR-002 should report a missing roster entry"
echo "$OUT" | jq -e '.needs_judgment[] | select(.adr=="ADR-003") | .problems | any(test("missing from docs/decisions/INDEX.md"))' >/dev/null \
  || fail "roster: ADR-003 should report a missing INDEX entry"
echo "$OUT" | jq -e '.needs_judgment[] | select(.adr=="ADR-007") | .problems | any(test("byte-identical"))' >/dev/null \
  || fail "roster: ADR-007 should report a title mismatch"
no_target_collision "$OUT" "roster"
# namespaced target + pre-authored judgment scalars, same contract as the
# other detectors whose findings Step 4 files verbatim.
echo "$OUT" | jq -e '[.needs_judgment[] | select(.type=="adr_roster_drift") | (has("problems") and has("confidence") and has("counter_evidence") and has("suggested_action") and (.target == "roster:" + .adr))] | all' >/dev/null \
  || fail "roster: a drift finding is missing its judgment scalars or namespaced target"

# --- roster-shape / index-shape: the two fail-open anchors ------------------
# Each check reads a structure it does not own. If that structure is reshaped,
# silently returning nothing repeats load_reserved_adrs' failure, and comparing
# against the empty parse floods one finding per ADR. Both must report the
# shape change exactly once instead.
OUT=$(python3 "$AUDIT" --repo-root fixtures/roster-shape)
[ "$(nj_len "$OUT")" -eq 1 ] || fail "roster-shape: expected exactly 1 finding (no per-ADR flood), got $(nj_len "$OUT"): $(echo "$OUT" | jq -c '[.needs_judgment[]|.target]')"
echo "$OUT" | jq -e '.needs_judgment[] | select(.type=="adr_roster_drift" and .target=="roster:CLAUDE.md")' >/dev/null \
  || fail "roster-shape: a declared-but-unparseable roster must report the shape change"
OUT=$(python3 "$AUDIT" --repo-root fixtures/index-shape)
[ "$(nj_len "$OUT")" -eq 1 ] || fail "index-shape: expected exactly 1 finding (no per-ADR flood), got $(nj_len "$OUT"): $(echo "$OUT" | jq -c '[.needs_judgment[]|.target]')"
echo "$OUT" | jq -e '.needs_judgment[] | select(.type=="adr_roster_drift" and .target=="roster:docs/decisions/INDEX.md")' >/dev/null \
  || fail "index-shape: an unparseable INDEX heading shape must report once"

# --- mirror fixture: inverted embedded-source-mirror detector --------------
# FIRE on near-complete drifted copies (alpha flush / delta indented-in-list /
# epsilon tilde-fenced-with-backtick-content); SILENT on identical (beta),
# abridged excerpt (gamma), unattributable (zeta / no-id first line), and
# coincidental-id-with-unrelated-content (alpha). Coexistence: dependency_version,
# dead_link, and dangling_adr must still fire around a mirror block in the same
# file (the fence-loop restructure must not disturb them).
OUT=$(python3 "$AUDIT" --repo-root fixtures/mirror \
  --package-resolved fixtures/mirror/Package.resolved)
[ "$(af_len "$OUT")" -eq 1 ] || fail "mirror: expected 1 auto_fixable (Yams), got $(af_len "$OUT")"
echo "$OUT" | jq -e '.auto_fixable[] | select(.dependency=="Yams" and .expected=="6.2.2")' >/dev/null \
  || fail "mirror: dependency_version did not fire beside a mirror block"
[ "$(echo "$OUT" | jq '[.needs_judgment[]|select(.type=="dead_link")]|length')" -eq 1 ] \
  || fail "mirror: dead_link did not fire beside a mirror block"
[ "$(echo "$OUT" | jq '[.needs_judgment[]|select(.type=="dangling_adr")]|length')" -eq 1 ] \
  || fail "mirror: dangling_adr did not fire beside a mirror block"
# This fixture has no CLAUDE.md at all, so the reserved set is empty while an
# ADR reference exists — the literal condition #1309 first proposed. It must
# NOT fire: an empty reserved set is the normal state for a repo that reserves
# nothing, and firing here would flood every such repo.
[ "$(nj_type_len "$OUT" unparsed_adr_reservation)" -eq 0 ] \
  || fail "mirror: unparsed_adr_reservation must not fire on an empty reserved set alone"
# exactly four mirror findings: mirrors.md's three FIRE blocks + coexist's one
MIR=$(echo "$OUT" | jq '[.needs_judgment[]|select(.type=="embedded_source_mirror")]|length')
[ "$MIR" -eq 4 ] || fail "mirror: expected 4 embedded_source_mirror, got $MIR: $(echo "$OUT" | jq -c '[.needs_judgment[]|select(.type=="embedded_source_mirror").target]')"
for want in "docs/mirrors.md::data/alpha.yaml" "docs/mirrors.md::data/delta.yaml" \
            "docs/mirrors.md::data/epsilon.yaml" "docs/coexist.md::data/alpha.yaml"; do
  echo "$OUT" | jq -e --arg t "$want" '.needs_judgment[]|select(.type=="embedded_source_mirror" and .target==$t)' >/dev/null \
    || fail "mirror: expected mirror finding for $want"
done
# the SILENT set must produce no mirror finding
for bad in "beta.yaml" "gamma.yaml" "zeta.yaml"; do
  echo "$OUT" | jq -e --arg b "$bad" '.needs_judgment[]|select(.type=="embedded_source_mirror" and (.target|contains($b)))' >/dev/null \
    && fail "mirror: $bad should be silent (identical / abridged / unattributable)" || true
done
# the coincidental-id block must not add a second location to the alpha finding
ALOC=$(echo "$OUT" | jq '[.needs_judgment[]|select(.type=="embedded_source_mirror" and .target=="docs/mirrors.md::data/alpha.yaml")|.locations|length][0]')
[ "$ALOC" -eq 1 ] || fail "mirror: mirrors.md alpha should have exactly 1 location (coincidental block leaked in?), got $ALOC"
# a mirror finding carries only paths + judgment scalars, never block/source text
# (it becomes a public GitHub issue body) — the allowed key set is closed.
if echo "$OUT" | jq -e '.needs_judgment[]|select(.type=="embedded_source_mirror")|(keys - ["confidence","counter_evidence","locations","source","suggested_action","target","type"])|length>0' >/dev/null; then
  fail "mirror: an embedded_source_mirror finding leaked an unexpected key (content leak?)"
fi
echo "$OUT" | jq -e '[.needs_judgment[]|select(.type=="embedded_source_mirror")|(has("confidence") and has("counter_evidence") and has("suggested_action") and has("source") and (.target==.source|not))]|all' >/dev/null \
  || fail "mirror: a mirror finding is missing its pre-authored judgment scalars"

echo "ALL TESTS PASSED"
