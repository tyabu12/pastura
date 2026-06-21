#!/bin/bash
# Self-test for the scenario-refine helper scripts. No Swift toolchain or
# model needed — exercises inventory selection (rotation / category resolution
# / ja-en tiering) and audit-journal appending (date idempotency / baseline
# delta / failed-run exclusion) against fixtures.
#
# usage: bash .claude/skills/scenario-refine/tests/run_tests.sh
set -eu
cd "$(dirname "$0")"
SCRIPTS=../scripts
INV=fixtures/inv
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

fail() { echo "FAIL: $1" >&2; exit 1; }

sel() { # run select_inventory.py against the fixture inventory
  python3 "$SCRIPTS/select_inventory.py" \
    --presets-dir "$INV/presets" \
    --gallery-dir "$INV/gallery" \
    --gallery-json "$INV/gallery/gallery.json" \
    "$@"
}

# --- select_inventory.py: category / 4th-axis resolution --------------------
J=$(sel --count 99 --journal fixtures/journal_seed.md)
axis() { echo "$J" | jq -r --arg id "$1" '.[] | select(.id==$id) | .payoff_axis'; }
cat_of() { echo "$J" | jq -r --arg id "$1" '.[] | select(.id==$id) | .category'; }

[ "$(cat_of bokete)" = "creative" ] || fail "bokete category != creative"
[ "$(axis bokete)" = "humor" ] || fail "bokete axis != humor"
[ "$(cat_of word_wolf)" = "game_theory" ] || fail "word_wolf category != game_theory"
[ "$(axis word_wolf)" = "strategic_tension" ] || fail "word_wolf axis != strategic_tension"
[ "$(cat_of asch_conformity_v1)" = "social_psychology" ] || fail "asch category"
[ "$(axis asch_conformity_v1)" = "phenomenon_visible" ] || fail "asch axis"
[ "$(cat_of trolley_dilemma_v1)" = "ethics" ] || fail "trolley category"
[ "$(axis trolley_dilemma_v1)" = "moral_divergence" ] || fail "trolley axis"
# experimental category is not in CATEGORY_AXIS → generic fallback, no KeyError
[ "$(cat_of weird_experimental_v1)" = "experimental" ] || fail "experimental category"
[ "$(axis weird_experimental_v1)" = "overall_engagement" ] || fail "experimental fallback axis"

# --- select_inventory.py: rotation (least-recently-evaluated first) ---------
# word_wolf was evaluated 2026-06-20 in the seed; everything else is new.
WW_DATE=$(echo "$J" | jq -r '.[] | select(.id=="word_wolf") | .last_evaluated')
[ "$WW_DATE" = "2026-06-20" ] || fail "word_wolf last_evaluated should be 2026-06-20, got $WW_DATE"
FIRST_DATE=$(echo "$J" | jq -r '.[0].last_evaluated')
[ "$FIRST_DATE" = "null" ] || fail "first selected should be never-evaluated (null), got $FIRST_DATE"
# the evaluated scenario must not outrank a never-evaluated one
WW_POS=$(echo "$J" | jq -r 'to_entries | .[] | select(.value.id=="word_wolf") | .key')
[ "$WW_POS" -gt 0 ] || fail "evaluated word_wolf should not be ranked first"

# --- select_inventory.py: model keying -------------------------------------
# A different model has never evaluated anything → word_wolf reads as new.
JM=$(sel --count 99 --journal fixtures/journal_seed.md --model other-model)
WW_OTHER=$(echo "$JM" | jq -r '.[] | select(.id=="word_wolf") | .last_evaluated')
[ "$WW_OTHER" = "null" ] || fail "model-mismatch should null out last_evaluated, got $WW_OTHER"

# --- select_inventory.py: ja primary before en sampling --------------------
# 5 ja/non-en primaries + 1 en (bokete_en). count=5 must exclude the en sibling.
J5=$(sel --count 5 --journal fixtures/journal_seed.md)
echo "$J5" | jq -e '[.[].id] | index("bokete_en") | not' >/dev/null \
  || fail "en sibling selected before primaries exhausted (count=5)"
echo "$J5" | jq -e 'length == 5' >/dev/null || fail "count=5 should select 5"
# count=6 reaches into the en tier
J6=$(sel --count 6 --journal fixtures/journal_seed.md)
echo "$J6" | jq -e '[.[].id] | index("bokete_en")' >/dev/null \
  || fail "en sibling should be reached at count=6"

# --- select_inventory.py: --only explicit pick (skips rotation/count) ------
JO=$(sel --count 1 --journal fixtures/journal_seed.md --only "bokete,word_wolf")
echo "$JO" | jq -e 'length == 2' >/dev/null || fail "--only should return exactly the 2 named (ignoring count)"
echo "$JO" | jq -e '[.[].id] | sort == ["bokete","word_wolf"]' >/dev/null \
  || fail "--only returned the wrong ids"

# --- select_inventory.py: empty / absent journal (first-run path) -----------
JE=$(sel --count 99 --journal "$TMP/does_not_exist.md")
echo "$JE" | jq -e 'all(.last_evaluated == null)' >/dev/null \
  || fail "absent journal should leave every last_evaluated null"
echo "$JE" | jq -e 'length >= 6' >/dev/null || fail "absent journal should still enumerate inventory"

# --- append_audit.py: section render + baseline delta ----------------------
cp fixtures/journal_seed.md "$TMP/journal.md"
python3 "$SCRIPTS/append_audit.py" \
  --results fixtures/results_sample.json --journal "$TMP/journal.md" >/dev/null
grep -q "^## 2026-06-21$" "$TMP/journal.md" || fail "audit: section heading missing"

# regression: word_wolf prior total 16 (2026-06-20) → new 12 → Δ-4, flagged ⚠️
WW_ROW=$(grep '^| word_wolf ' "$TMP/journal.md")
echo "$WW_ROW" | grep -q -- "-4" || fail "audit: word_wolf regression delta -4 missing"
echo "$WW_ROW" | grep -q "⚠️" || fail "audit: regression ⚠️ flag missing"

# A/B candidate: bokete__v2 total 20 vs same-run baseline bokete 18 → vs base +2
CAND_ROW=$(grep '^| bokete__v2 ' "$TMP/journal.md")
echo "$CAND_ROW" | grep -q "vs base +2" || fail "audit: A/B delta 'vs base +2' missing"
echo "$CAND_ROW" | grep -q "✅" || fail "audit: A/B win ✅ missing"

# bokete itself has no prior baseline → Δ em-dash, not a number. Field 10
# (split on " | ") is the Δ cell; reverting the "if base is None: return –"
# arm would make this a spurious number and fail here.
BK_ROW=$(grep '^| bokete ' "$TMP/journal.md")
BK_DELTA=$(echo "$BK_ROW" | awk -F' \\| ' '{print $10}')
[ "$BK_DELTA" = "–" ] || fail "audit: no-prior-baseline Δ must be em-dash, got '$BK_DELTA'"

# failed run: no scores, Δ em-dash, error surfaced in comment
DET_ROW=$(grep '^| detective_scene_v1 ' "$TMP/journal.md")
echo "$DET_ROW" | grep -q "failed" || fail "audit: failed status missing"
echo "$DET_ROW" | grep -q "#253" || fail "audit: failed error not surfaced in comment"

# machine-readable comment present; pipe escaped in human comment cell
grep -q "audit-data:" "$TMP/journal.md" || fail "audit: data comment missing"
echo "$WW_ROW" | grep -q '噛み合わせ \\| が弱い' || fail "audit: pipe not escaped in comment"

# failed run excluded from scores in the data comment (status only)
DATA=$(grep -o '<!-- audit-data: .* -->' "$TMP/journal.md" \
  | sed 's/^<!-- audit-data: //; s/ -->$//' | jq -s '.[] | select(.date=="2026-06-21")')
echo "$DATA" | jq -e '.scenarios.detective_scene_v1.status == "failed"' >/dev/null \
  || fail "audit: failed run should be in data comment as failed"
echo "$DATA" | jq -e '.scenarios.detective_scene_v1 | has("coherence") | not' >/dev/null \
  || fail "audit: failed run must carry no scores"
echo "$DATA" | jq -e '.scenarios.word_wolf.coherence == 3' >/dev/null \
  || fail "audit: ok run scores missing from data comment"

# --- append_audit.py: round-trip into select rotation ----------------------
# After appending, the evaluated ids must read as evaluated-today in select.
RT=$(python3 "$SCRIPTS/select_inventory.py" \
  --presets-dir "$INV/presets" --gallery-dir "$INV/gallery" \
  --gallery-json "$INV/gallery/gallery.json" --count 99 --journal "$TMP/journal.md")
RT_WW=$(echo "$RT" | jq -r '.[] | select(.id=="word_wolf") | .last_evaluated')
[ "$RT_WW" = "2026-06-21" ] || fail "round-trip: word_wolf should read evaluated 2026-06-21, got $RT_WW"

# --- append_audit.py: date idempotency -------------------------------------
python3 "$SCRIPTS/append_audit.py" \
  --results fixtures/results_sample.json --journal "$TMP/journal.md" >/dev/null 2>"$TMP/warn"
COUNT=$(grep -c "^## 2026-06-21$" "$TMP/journal.md")
[ "$COUNT" -eq 1 ] || fail "audit: re-append duplicated the section ($COUNT)"
grep -q "warning: replaced" "$TMP/warn" || fail "audit: replace warning missing"
# re-running same date must NOT use the replaced same-date section as its own
# baseline — word_wolf still compares to 2026-06-20, so Δ stays -4 (not 0).
grep '^| word_wolf ' "$TMP/journal.md" | grep -q -- "-4" \
  || fail "audit: same-date re-run must not self-baseline (Δ should stay -4)"

# --- append_audit.py: markers + bootstrap ----------------------------------
echo "# broken" > "$TMP/broken.md"
if python3 "$SCRIPTS/append_audit.py" \
  --results fixtures/results_sample.json --journal "$TMP/broken.md" 2>/dev/null; then
  fail "audit: missing markers should be a hard error"
fi
python3 "$SCRIPTS/append_audit.py" \
  --results fixtures/results_sample.json --journal "$TMP/bootstrap.md" >/dev/null \
  || fail "audit: absent file should bootstrap, not error"
grep -q "audit-digest:sections" "$TMP/bootstrap.md" || fail "bootstrap: sections marker missing"
grep -q "audit-digest:promotion" "$TMP/bootstrap.md" || fail "bootstrap: promotion marker missing"
grep -q "^## 2026-06-21$" "$TMP/bootstrap.md" || fail "bootstrap: section not appended"
tail -1 "$TMP/bootstrap.md" | grep -q "^Promotion:" || fail "bootstrap: promotion line not last"

# --- append_audit.py: malformed prior ok record warns (not silent) ---------
# A prior ok record missing an axis must emit a stderr warning rather than
# silently dropping out of the baseline.
cat > "$TMP/malformed.md" <<'EOF'
# seed
<!-- audit-digest:sections -->
## 2026-06-19

<!-- audit-data: {"date": "2026-06-19", "model": "gemma-4-E2B-it-Q4_K_M", "scenarios": {"bokete": {"coherence": 4, "interaction": 4, "breakdown_free": 4, "status": "ok"}}} -->

<!-- audit-digest:promotion -->
Promotion: x
EOF
python3 "$SCRIPTS/append_audit.py" \
  --results fixtures/results_sample.json --journal "$TMP/malformed.md" \
  >/dev/null 2>"$TMP/mwarn"
grep -q "missing score axes" "$TMP/mwarn" \
  || fail "audit: malformed prior ok record should warn, not silently skip"

echo "ALL TESTS PASSED"
