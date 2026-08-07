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
# suppress each other across runs. Called on every fixture run that yields
# judgment findings, not just the ones where two types fire today.
#
# Scope, stated because a guard narrower than its claim proves nothing: this
# tests EXACT target equality only. GitHub's search also matches on tokens, so
# `reservation:ADR-006` and `ADR-006` can still match each other's titles —
# unavoidable while a target names its ADR, and handled in SKILL.md Step 4 by
# confirming the matched issue before skipping.
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
no_target_collision "$OUT" "judgment"

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
no_target_collision "$OUT" "adr"

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
# other detectors whose findings Step 4 files verbatim. Two shapes: per-ADR
# findings carry `adr` and key off it; the structural ones name the file
# instead, so the target check branches rather than assuming `adr` is present.
echo "$OUT" | jq -e '[.needs_judgment[] | select(.type=="adr_roster_drift") | (has("problems") and has("confidence") and has("counter_evidence") and has("suggested_action") and (if has("adr") then .target == "roster:" + .adr else (.target | startswith("roster:")) end))] | all' >/dev/null \
  || fail "roster: a drift finding is missing its judgment scalars or namespaced target"

# --- the three fail-open anchors: reshape must report ONCE, never flood -----
# Each check reads a structure it does not own. Silently returning nothing
# repeats load_reserved_adrs' failure; comparing against a partial or empty
# parse floods one finding per ADR, at high confidence, because those ADRs
# exist. roster-shape reflows into a bullet list (stops matching the entry
# shape); roster-reflow rewraps across two lines while still matching, with
# the wrap landing after a separator so the continuation carries none;
# index-shape leaves INDEX.md with no parseable heading at all.
for f in roster-shape roster-reflow-head roster-prose index-stub roster-no-index roster-tight-heading; do
  OUT=$(python3 "$AUDIT" --repo-root "fixtures/$f")
  EXPECT=1
  case "$f" in roster-no-index|roster-tight-heading) EXPECT=0 ;; esac
  [ "$(nj_len "$OUT")" -eq "$EXPECT" ] \
    || fail "$f: expected exactly $EXPECT finding(s) (no per-ADR flood), got $(nj_len "$OUT"): $(echo "$OUT" | jq -c '[.needs_judgment[]|{target,problems}]')"
  [ "$EXPECT" -eq 0 ] || echo "$OUT" | jq -e '.needs_judgment[] | select(.type=="adr_roster_drift" and (has("adr")|not))' >/dev/null \
    || fail "$f: the single finding must be structural (no per-ADR claim): $(echo "$OUT" | jq -c '[.needs_judgment[]|{target,problems}]')"
  no_target_collision "$OUT" "$f"
done
# roster-no-index is the only reachable exercise of `backed`'s reserved
# component: everywhere else, a reserved fileless ADR is also in INDEX.md and
# the roster branch defers to the canary on that instead. roster-tight-heading
# is the ATX-boundary control — its roster is one complete line wedged between
# two flush headings, which a blank-line-only paragraph walk reads as a reflow.

# --- degradation: one unreadable structure must not silence the other axis --
# Both were early returns, which hid genuine drift on the axis that did not
# depend on the reshaped structure.
OUT=$(python3 "$AUDIT" --repo-root fixtures/roster-reflow)
echo "$OUT" | jq -e '.needs_judgment[] | select(.target=="roster:CLAUDE.md") | .problems[0] | test("spans 2 lines")' >/dev/null \
  || fail "roster-reflow: a rewrapped roster must report the reflow, measured as a paragraph"
echo "$OUT" | jq -e '.needs_judgment[] | select(.adr=="ADR-003") | .problems | any(test("missing from docs/decisions/INDEX.md"))' >/dev/null \
  || fail "roster-reflow: an unreadable roster must not silence the INDEX-vs-disk axis"
echo "$OUT" | jq -e '.needs_judgment[] | select(.adr=="ADR-003") | .problems | any(test("missing from the CLAUDE.md ADR roster"))' >/dev/null \
  && fail "roster-reflow: the roster axis must stay silent while the roster is unreadable" || true
no_target_collision "$OUT" "roster-reflow"
OUT=$(python3 "$AUDIT" --repo-root fixtures/index-shape)
echo "$OUT" | jq -e '.needs_judgment[] | select(.target=="roster:docs/decisions/INDEX.md")' >/dev/null \
  || fail "index-shape: an unparseable INDEX heading shape must report once"
echo "$OUT" | jq -e '.needs_judgment[] | select(.adr=="ADR-003") | .problems | any(test("missing from the CLAUDE.md ADR roster"))' >/dev/null \
  || fail "index-shape: an unreadable INDEX must not silence the roster-vs-disk axis"
no_target_collision "$OUT" "index-shape"
OUT=$(python3 "$AUDIT" --repo-root fixtures/index-stub)
echo "$OUT" | jq -e '.needs_judgment[] | select(.target=="roster:docs/decisions/INDEX.md")' >/dev/null \
  || fail "index-stub: a placeholder INDEX with no ADR token at all must report once, not flood"

OUT=$(python3 "$AUDIT" --repo-root fixtures/roster-reflow-head)
echo "$OUT" | jq -e '.needs_judgment[] | select(.target=="roster:CLAUDE.md")' >/dev/null \
  || fail "roster-reflow-head: a wrap after the FIRST entry must report the reflow, not flood per ADR"
OUT=$(python3 "$AUDIT" --repo-root fixtures/roster-prose)
echo "$OUT" | jq -e '.needs_judgment[] | select(.target=="roster:CLAUDE.md") | .problems[0] | test("cannot tell a title that wrapped")' >/dev/null \
  || fail "roster-prose: the finding must claim only what is true — the paragraph is unread, not that entries are missing"

# --- roster-both-listed: one omission, one issue ---------------------------
# A fileless ADR in BOTH listings is the shape adr-writing.md §4 produces, and
# unparsed_adr_reservation already reports it with a reservation-specific
# action. adr_roster_drift must defer, or the run files two issues for one
# omission on top of the dangling_adr the canary explains.
OUT=$(python3 "$AUDIT" --repo-root fixtures/roster-both-listed)
[ "$(nj_type_len "$OUT" adr_roster_drift)" -eq 0 ] \
  || fail "roster-both-listed: adr_roster_drift must defer to the canary: $(echo "$OUT" | jq -c '[.needs_judgment[]|{type,target,problems}]')"
[ "$(nj_type_len "$OUT" unparsed_adr_reservation)" -eq 1 ] \
  || fail "roster-both-listed: the canary must still fire"
no_target_collision "$OUT" "roster-both-listed"

# --- untracked ADR draft: not yet required, but it does back a listing ------
# Needs a real git repo, since the tracked/existing split is what `git ls-files`
# answers — no fixture directory can exercise it (they resolve below this
# repo's toplevel, where both sets collapse to the glob). An author mid-draft
# has written the ADR and updated both listings; nothing should fire. Reading
# one set for both questions produced a `high`-confidence "record a reserved
# row" against an ADR being written right then.
G="$TMP/untracked"
mkdir -p "$G/docs/decisions"
# %b, not %s: printf interprets escapes in the format string only, so a \n
# passed as an argument would land in the file as a literal backslash-n.
roster() { printf '# Scratch\n\n### ADR roster\n\n%b\n' "$1" > "$G/CLAUDE.md"; }
index() { printf '# Index\n\n%b\n' "$1" > "$G/docs/decisions/INDEX.md"; }
roster '001 A · 003 C'
index '## ADR-001 — A\n\n## ADR-003 — C'
printf '# ADR-001\n' > "$G/docs/decisions/ADR-001.md"
printf '# ADR-003\n' > "$G/docs/decisions/ADR-003.md"
# Isolate from the developer's global config BEFORE init: init.templateDir is
# consumed at init time (hooks are copied into .git/hooks then), while
# commit.gpgsign and core.hooksPath are read at commit time. Exporting after
# init would neutralize the latter two only. CI's config is clean either way.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
git -C "$G" init -q
git -C "$G" -c user.email=t@e -c user.name=t add -A >/dev/null
git -C "$G" -c user.email=t@e -c user.name=t commit -qm base

# Phase 0 — requirement direction. ADR-002 is written but nothing is committed
# and neither listing mentions it yet. A draft mid-authoring must not be told
# it is missing from two indexes; only landing it makes those entries due.
printf '# ADR-002\n' > "$G/docs/decisions/ADR-002.md"
OUT=$(python3 "$AUDIT" --repo-root "$G")
[ "$(nj_len "$OUT")" -eq 0 ] \
  || fail "untracked: an unlisted untracked draft must not be reported missing, got $(echo "$OUT" | jq -c '[.needs_judgment[]|{type,target,problems}]')"

# Phase 1 — suppression direction. The author has written ADR-002 and added it
# to both listings, but has committed nothing yet. The draft is untracked, so
# it demands no listings; it does back the two entries just added. Answering
# both questions from the tracked set alone produced a high-confidence "record
# a reserved row" against an ADR being written right then.
roster '001 A · 002 B · 003 C'
index '## ADR-001 — A\n\n## ADR-002 — B\n\n## ADR-003 — C'
OUT=$(python3 "$AUDIT" --repo-root "$G")
[ "$(nj_len "$OUT")" -eq 0 ] \
  || fail "untracked: an untracked draft backing its own listings must be silent, got $(echo "$OUT" | jq -c '[.needs_judgment[]|{type,target,confidence}]')"

# Phase 2 — requirement direction, and the negative control proving phase 1's
# silence is scoped rather than blanket: the same ADR, now tracked and in
# neither listing, must report both omissions.
git -C "$G" -c user.email=t@e -c user.name=t add docs/decisions/ADR-002.md >/dev/null
roster '001 A · 003 C'
index '## ADR-001 — A\n\n## ADR-003 — C'
OUT=$(python3 "$AUDIT" --repo-root "$G")
echo "$OUT" | jq -e '.needs_judgment[] | select(.type=="adr_roster_drift" and .adr=="ADR-002") | .problems | (any(test("missing from the CLAUDE.md ADR roster")) and any(test("missing from docs/decisions/INDEX.md")))' >/dev/null \
  || fail "untracked: a tracked ADR absent from both listings must report both: $(echo "$OUT" | jq -c '[.needs_judgment[]|{type,target,problems}]')"
no_target_collision "$OUT" "untracked"

# Phase 3 — tracked but deleted from the worktree. `git ls-files` still lists
# it, so folding the tracked set into "is a file behind this listing" would
# silence both new detectors on the one state that floods dangling_adr — a
# flood with no canary, which is the shape the canary exists for.
roster '001 A · 002 B · 003 C'
index '## ADR-001 — A\n\n## ADR-002 — B\n\n## ADR-003 — C'
rm "$G/docs/decisions/ADR-002.md"
OUT=$(python3 "$AUDIT" --repo-root "$G")
[ "$(nj_type_len "$OUT" unparsed_adr_reservation)" -eq 1 ] \
  || fail "untracked: a tracked-but-deleted ADR must still raise the canary beside its dangling_adr, got $(echo "$OUT" | jq -c '[.needs_judgment[]|{type,target}]')"
no_target_collision "$OUT" "untracked-deleted"

# Phase 4 — the whole directory gone while tracked. Per-ADR canaries would
# double the dangling_adr flood they exist to explain, so past the cap they
# collapse to one structural finding.
rm "$G"/docs/decisions/ADR-00*.md
index '## ADR-001 — A\n\n## ADR-002 — B\n\n## ADR-003 — C\n\n## ADR-004 — D'
OUT=$(python3 "$AUDIT" --repo-root "$G")
[ "$(nj_type_len "$OUT" unparsed_adr_reservation)" -eq 1 ] \
  || fail "untracked: a wiped decisions dir must collapse to one canary, got $(echo "$OUT" | jq -c '[.needs_judgment[]|select(.type=="unparsed_adr_reservation")|.target]')"
echo "$OUT" | jq -e '.needs_judgment[] | select(.type=="unparsed_adr_reservation" and .shape=="many-listed-in-index" and .count==4)' >/dev/null \
  || fail "untracked: the collapsed canary must report the count it stands for: $(echo "$OUT" | jq -c '[.needs_judgment[]|select(.type=="unparsed_adr_reservation")]')"

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
no_target_collision "$OUT" "mirror"

# --- adr_navigation_missing: ten arms, exactly two must fire ---------------
# The fixture is generated, not committed: every must-NOT-fire arm has to clear
# the 600-line gate so it is silent for the rule it tests rather than for its
# size, and ten such ADRs would be ~5500 lines of filler in the repo. The arm
# table in make_nav_fixture.py is the fixture; this block asserts the outcome.
NAVFIX="$TMP/navfix"
MANIFEST=$(python3 make_nav_fixture.py "$NAVFIX")
# The wrong-reason guard. ADR-103 is the one arm deliberately under the gate
# (it tests the gate); every other arm must clear it, or a "must not count"
# arm is passing because it is short.
for adr in ADR-101 ADR-102 ADR-104 ADR-105 ADR-106 ADR-107 ADR-108 ADR-109 ADR-110; do
  n=$(echo "$MANIFEST" | jq --arg a "$adr" '.[$a].total_lines')
  [ "$n" -ge 600 ] || fail "nav: $adr is only $n lines — under the size gate, so its arm would pass for the wrong reason"
done
NL=$(echo "$MANIFEST" | jq '."ADR-103".total_lines')
[ "$NL" -lt 600 ] || fail "nav: ADR-103 must stay under the size gate to test it, got $NL"

OUT=$(python3 "$AUDIT" --repo-root "$NAVFIX")
[ "$(af_len "$OUT")" -eq 0 ] || fail "nav: auto_fixable must stay empty — this detector is needs_judgment only: $(echo "$OUT" | jq -c .auto_fixable)"
# No other detector may fire: a contaminated fixture (e.g. an arm title naming a
# fileless ADR-NNN, which trips dangling_adr) makes the counts below meaningless.
[ "$(nj_len "$OUT")" -eq 2 ] || fail "nav: expected exactly 2 findings, got $(nj_len "$OUT"): $(echo "$OUT" | jq -c '[.needs_judgment[]|{type,target}]')"
[ "$(nj_type_len "$OUT" adr_navigation_missing)" -eq 2 ] || fail "nav: expected 2 adr_navigation_missing, got $(nj_type_len "$OUT" adr_navigation_missing)"
for want in "nav:ADR-101" "nav:ADR-110"; do
  echo "$OUT" | jq -e --arg t "$want" '.needs_judgment[]|select(.type=="adr_navigation_missing" and .target==$t)' >/dev/null \
    || fail "nav: expected a finding targeted $want"
done
# `nav:` namespacing, for the same reason `roster:` carries it — Step 4's
# cross-run dedup matches the target as a title substring and is type-blind.
echo "$OUT" | jq -e '[.needs_judgment[]|select(.type=="adr_navigation_missing")|.target|startswith("nav:")]|all' >/dev/null \
  || fail "nav: a finding target is not namespaced with nav:"
# Pre-authored judgment scalars — SKILL.md Step 4 uses these verbatim.
echo "$OUT" | jq -e '[.needs_judgment[]|select(.type=="adr_navigation_missing")|(has("confidence") and has("counter_evidence") and has("suggested_action") and has("sections") and (.locations|length>0))]|all' >/dev/null \
  || fail "nav: a finding is missing its pre-authored judgment scalars or locations"
# The counter-evidence leans on this count, so it is asserted rather than
# assumed: ADR-110's two sections are both numbered.
NUM=$(echo "$OUT" | jq '[.needs_judgment[]|select(.target=="nav:ADR-110")|.numbered_section_count][0]')
[ "$NUM" -eq 2 ] || fail "nav: ADR-110 should report 2 numbered sections, got $NUM"
# The remedy is a map plus promotion into the body — never deletion.
# `.claude/rules/adr-writing.md` records that amendments are not trimmed away
# later (#1382 declined that on principle), so a generator proposing it would
# be putting an unattended run at odds with a house rule. Asserted as a plain
# positive: the disclaimer must be present, which cannot pass vacuously.
echo "$OUT" | jq -e '[.needs_judgment[]|select(.type=="adr_navigation_missing")|.suggested_action|test("Do NOT delete or trim amendments")]|all' >/dev/null \
  || fail "nav: suggested_action lost its do-not-delete disclaimer"
no_target_collision "$OUT" "nav"

# --- negative controls: each guard has a mutation that flips its arm --------
# Silent arms prove nothing by themselves; this is what demonstrates the guards
# exist. Also asserts every mutation's anchor matched, so a no-op replace cannot
# pass as a verified control.
python3 mutate_nav_guards.py || fail "nav: a guard's negative control did not flip (see above)"

echo "ALL TESTS PASSED"
