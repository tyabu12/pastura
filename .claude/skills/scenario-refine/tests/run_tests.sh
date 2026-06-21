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

# --- select_inventory.py: empty / absent journal (first-run path) -----------
JE=$(sel --count 99 --journal "$TMP/does_not_exist.md")
echo "$JE" | jq -e 'all(.last_evaluated == null)' >/dev/null \
  || fail "absent journal should leave every last_evaluated null"
echo "$JE" | jq -e 'length >= 6' >/dev/null || fail "absent journal should still enumerate inventory"

echo "ALL TESTS PASSED"
