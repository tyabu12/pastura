#!/usr/bin/env bash
#
# scripts/tests/gallery-highlight-test.sh — regression tests for the ADR-029
# scenario-highlight tooling: scripts/gallery_highlight_extract.py,
# scripts/gallery_highlight_validate.py, and check-gallery-entry.sh's
# highlight wiring (#1381).
#
# Black-box, same shape as gallery-scripts-test.sh: each case scaffolds an
# ISOLATED throwaway git repo under a tempdir (scripts copied into
# <tmp>/scripts/, a minimal docs/gallery/ + a fixture ContentBlocklist.json,
# `git init`) and runs the tools from inside it. check-gallery-entry.sh
# resolves its root via `git rev-parse --show-toplevel`, so the real
# docs/gallery/ is never touched and cases are parallel-safe.
#
# CI-wired via the `scripts/tests/*-test.sh` naming convention (the
# `shell-tests` job, ubuntu / bash 5+). The scripts under test also ship to
# macOS bash 3.2, so run this under /bin/bash before merge for 3.2 coverage:
#
#   /bin/bash scripts/tests/gallery-highlight-test.sh

set -euo pipefail

for dep in jq python3 git shasum; do
  command -v "$dep" >/dev/null 2>&1 || { echo "ERROR: missing dependency: $dep" >&2; exit 1; }
done
python3 -c "import yaml" 2>/dev/null || { echo "ERROR: PyYAML not available — 'python3 -m pip install pyyaml'" >&2; exit 1; }

SRC_SCRIPTS="$(git rev-parse --show-toplevel)/scripts"
TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT

PASS=0
FAIL=0
OUT=""
RC=0

bad() { echo "FAIL: $1" >&2; FAIL=$((FAIL + 1)); }

runc() {
  local d="$1"; shift
  set +e
  OUT="$(cd "$d" && "$@" 2>&1)"
  RC=$?
  set -e
}

expect_ok()   { if [ "$RC" -eq 0 ]; then PASS=$((PASS + 1)); else bad "$1 (rc=$RC): $OUT"; fi; }
expect_fail() { if [ "$RC" -ne 0 ]; then PASS=$((PASS + 1)); else bad "$1 (expected non-zero rc): $OUT"; fi; }
expect_out()  { case "$OUT" in *"$1"*) PASS=$((PASS + 1));; *) bad "$2 (missing '$1'): $OUT";; esac; }

# --- Scaffold --------------------------------------------------------------

sha() { shasum -a 256 "$1" | awk '{print $1}'; }

# A repo with one gallery scenario `demo_v1` (phases: speak_each, summarize;
# rounds 4) and no highlight yet.
new_repo() {
  local d
  d="$(mktemp -d "$TMPROOT/repo.XXXXXX")"
  mkdir -p "$d/scripts" "$d/docs/gallery/highlights" "$d/Pastura/Pastura/Resources"
  cp "$SRC_SCRIPTS/check-gallery-entry.sh" \
     "$SRC_SCRIPTS/gallery_highlight_validate.py" \
     "$SRC_SCRIPTS/gallery_highlight_extract.py" "$d/scripts/"
  cat > "$d/Pastura/Pastura/Resources/ContentBlocklist.json" <<'JSON'
{
  "version": 1,
  "patterns": [
    { "term": "殺す", "contentCategory": "violence" },
    { "term": "Fuck", "contentCategory": "profanity" },
    { "term": "naive", "contentCategory": "harassment" }
  ]
}
JSON
  git -C "$d" init -q
  git -C "$d" config user.email "t@example.com"
  git -C "$d" config user.name "tester"
  printf '%s' "$d"
}

# mk_scenario <repo> <id> <phases-json> [rounds] [secret]
mk_scenario() {
  local d="$1" id="$2" phases="$3" rounds="${4:-4}" secret="${5:-}"
  cat > "$d/docs/gallery/$id.yaml" <<YAML
id: $id
language: ja
name: Name of $id
agents: 3
rounds: $rounds
description: card description
personas:
  - name: アヤ
    description: aa
YAML
  if [ -n "$secret" ]; then
    printf '    secret: hidden agenda\n' >> "$d/docs/gallery/$id.yaml"
  fi
  printf 'phases:\n' >> "$d/docs/gallery/$id.yaml"
  echo "$phases" | jq -r '.[] | "  - type: " + .' >> "$d/docs/gallery/$id.yaml"

  local s
  s="$(sha "$d/docs/gallery/$id.yaml")"
  jq --arg id "$id" --arg sha "$s" --argjson phases "$phases" \
     --argjson rounds "$rounds" \
     '.scenarios += [{id: $id, title: ("T " + $id), rounds: $rounds,
                      phases: $phases, language: "ja",
                      yaml_url: ($id + ".yaml"), yaml_sha256: $sha}]' \
     "$d/docs/gallery/gallery.json" > "$d/docs/gallery/gallery.json.tmp"
  mv "$d/docs/gallery/gallery.json.tmp" "$d/docs/gallery/gallery.json"
}

init_index() {
  printf '{\n  "updated_at": "2026-01-01T00:00:00Z",\n  "scenarios": []\n}\n' \
    > "$1/docs/gallery/gallery.json"
}

# The default hook is `kind: raw` — a `phases:` fragment, which is exactly the
# case `raw` exists for: no structured rendition is claimed, so the fragment
# publishes as a YAML block. Cases exercising the persona shape pass their own
# hook via mk_highlight's 6th argument.
HOOK_RAW='{"kind":"raw","fragment":"phases:\n  - type: speak_each","caption":"この一行が会話を生む"}'
HOOK_PERSONA='{"kind":"persona","fragment":"  - name: アヤ\n    description: 率直な被験者。\n  - name: ケン\n    description: 場を読む同調者。","caption":"この2人の設定を書き換えると流れが変わる。"}'

# mk_highlight <repo> <id> <excerpt-json> [window_override] [teaser] [hook-json]
mk_highlight() {
  local d="$1" id="$2" excerpt="$3" wo="${4:-false}" teaser="${5:-最後の一言は、まだ言われていない。}"
  local hook="${6:-$HOOK_RAW}"
  local ysha
  ysha="$(sha "$d/docs/gallery/$id.yaml")"
  jq -n --arg id "$id" --arg ysha "$ysha" --argjson excerpt "$excerpt" \
        --argjson wo "$wo" --arg teaser "$teaser" --argjson hook "$hook" \
    '{schema_version: 1,
      scenario_ref: {id: $id, yaml_sha256: $ysha},
      source: {model: "gemma-4-e2b-q4-k-m", run_id: "r1", generated_at: "2026-08-05"},
      excerpt: $excerpt,
      yaml_hook: $hook,
      teaser: $teaser,
      window_override: $wo,
      content_filter_applied: true}' \
    > "$d/docs/gallery/highlights/$id.json"
}

# link_highlight <repo> <id> — add the paired index fields with the real hash.
link_highlight() {
  local d="$1" id="$2" hsha
  hsha="$(sha "$d/docs/gallery/highlights/$id.json")"
  jq --arg id "$id" --arg hsha "$hsha" \
     '.scenarios |= map(if .id == $id then
        . + {highlight_url: ("highlights/" + $id + ".json"), highlight_sha256: $hsha}
      else . end)' \
     "$d/docs/gallery/gallery.json" > "$d/docs/gallery/gallery.json.tmp"
  mv "$d/docs/gallery/gallery.json.tmp" "$d/docs/gallery/gallery.json"
}

# One eligible excerpt entry: speak_each at phase_index 0, round 1.
EX_OK='[{"agent":"アヤ","round":1,"phase":"speak_each","phase_index":0,"source_field":"statement","text":"私はBだと思う。"}]'

gate() { runc "$1" bash scripts/check-gallery-entry.sh --all; }

# ============================ validator / gate ============================

# H0 — a repo with no highlights at all still passes (no-op path).
R="$(new_repo)"; init_index "$R"; mk_scenario "$R" demo_v1 '["speak_each","summarize"]'
rmdir "$R/docs/gallery/highlights"
gate "$R"; expect_ok "H0 no highlights → gate passes"

# H1 — a valid highlight passes.
R="$(new_repo)"; init_index "$R"; mk_scenario "$R" demo_v1 '["speak_each","summarize"]'
mk_highlight "$R" demo_v1 "$EX_OK"; link_highlight "$R" demo_v1
gate "$R"; expect_ok "H1 valid highlight passes"

# H2 — highlight_sha256 drift fails with the highlight-specific message.
R="$(new_repo)"; init_index "$R"; mk_scenario "$R" demo_v1 '["speak_each","summarize"]'
mk_highlight "$R" demo_v1 "$EX_OK"; link_highlight "$R" demo_v1
jq '.scenarios[0].highlight_sha256 = "deadbeef"' "$R/docs/gallery/gallery.json" > "$R/t" && mv "$R/t" "$R/docs/gallery/gallery.json"
gate "$R"; expect_fail "H2 highlight_sha256 drift fails"
expect_out "highlight: highlight_sha256 mismatch" "H2 names the highlight sha check"

# H3 — scenario YAML edited after the highlight was pinned (stale yaml_sha256).
R="$(new_repo)"; init_index "$R"; mk_scenario "$R" demo_v1 '["speak_each","summarize"]'
mk_highlight "$R" demo_v1 "$EX_OK"; link_highlight "$R" demo_v1
jq '.scenarios[0].scenario_ref' /dev/null 2>/dev/null || true
python3 - "$R" <<'PY'
import json, sys
d = sys.argv[1]
p = d + "/docs/gallery/highlights/demo_v1.json"
doc = json.load(open(p))
doc["scenario_ref"]["yaml_sha256"] = "0" * 64
json.dump(doc, open(p, "w"), ensure_ascii=False, indent=2)
PY
link_highlight "$R" demo_v1
gate "$R"; expect_fail "H3 stale scenario_ref.yaml_sha256 fails"
expect_out "highlight: yaml_sha256 mismatch" "H3 names the yaml sha check"

# H4 — orphan file: highlight exists, index carries no highlight fields.
R="$(new_repo)"; init_index "$R"; mk_scenario "$R" demo_v1 '["speak_each","summarize"]'
mk_highlight "$R" demo_v1 "$EX_OK"
gate "$R"; expect_fail "H4 unreferenced highlight file fails"
expect_out "highlight: orphan" "H4 names the orphan check"

# H4b — orphan file whose id is absent from gallery.json entirely.
R="$(new_repo)"; init_index "$R"; mk_scenario "$R" demo_v1 '["speak_each","summarize"]'
mk_highlight "$R" demo_v1 "$EX_OK"
mv "$R/docs/gallery/highlights/demo_v1.json" "$R/docs/gallery/highlights/ghost_v1.json"
gate "$R"; expect_fail "H4b highlight for an unknown id fails"
expect_out "highlight: orphan" "H4b names the orphan check"

# H5 — pairing violation: highlight_url without highlight_sha256.
R="$(new_repo)"; init_index "$R"; mk_scenario "$R" demo_v1 '["speak_each","summarize"]'
mk_highlight "$R" demo_v1 "$EX_OK"; link_highlight "$R" demo_v1
jq 'del(.scenarios[0].highlight_sha256)' "$R/docs/gallery/gallery.json" > "$R/t" && mv "$R/t" "$R/docs/gallery/gallery.json"
gate "$R"; expect_fail "H5 half-paired index entry fails"
expect_out "highlight: pairing" "H5 names the pairing check"

# H6 — within-round bound: speak_each sits after `vote` in the phase list.
R="$(new_repo)"; init_index "$R"; mk_scenario "$R" demo_v1 '["vote","speak_each","summarize"]'
mk_highlight "$R" demo_v1 '[{"agent":"アヤ","round":1,"phase":"speak_each","phase_index":1,"source_field":"statement","text":"やっぱりね。"}]'
link_highlight "$R" demo_v1
gate "$R"; expect_fail "H6 post-outcome utterance fails"
expect_out "highlight: within-round bound" "H6 names the within-round check"

# H7 — round window: round 4 of 4 without an override.
R="$(new_repo)"; init_index "$R"; mk_scenario "$R" demo_v1 '["speak_each","summarize"]'
mk_highlight "$R" demo_v1 '[{"agent":"アヤ","round":4,"phase":"speak_each","phase_index":0,"source_field":"statement","text":"もう言うしかない。"}]'
link_highlight "$R" demo_v1
gate "$R"; expect_fail "H7 late-round excerpt without override fails"
expect_out "highlight: round window" "H7 names the round-window check"

# H7b — same excerpt passes with window_override: true.
R="$(new_repo)"; init_index "$R"; mk_scenario "$R" demo_v1 '["speak_each","summarize"]'
mk_highlight "$R" demo_v1 '[{"agent":"アヤ","round":4,"phase":"speak_each","phase_index":0,"source_field":"statement","text":"もう言うしかない。"}]' true
link_highlight "$R" demo_v1
gate "$R"; expect_ok "H7b window_override: true accepts the late round"

# H8 — excerpt cap: 9 entries.
R="$(new_repo)"; init_index "$R"; mk_scenario "$R" demo_v1 '["speak_each","summarize"]'
NINE="$(jq -n '[range(9) | {agent:"アヤ", round:1, phase:"speak_each", phase_index:0,
                            source_field:"statement", text:("line " + (.|tostring))}]')"
mk_highlight "$R" demo_v1 "$NINE"; link_highlight "$R" demo_v1
gate "$R"; expect_fail "H8 nine excerpt entries fail"
expect_out "highlight: excerpt cap" "H8 names the cap check"

# H9 — source_field allowlist: inner_thought is never publishable.
R="$(new_repo)"; init_index "$R"; mk_scenario "$R" demo_v1 '["speak_each","summarize"]'
mk_highlight "$R" demo_v1 '[{"agent":"アヤ","round":1,"phase":"speak_each","phase_index":0,"source_field":"inner_thought","text":"本当はCだ。"}]'
link_highlight "$R" demo_v1
gate "$R"; expect_fail "H9 inner_thought source_field fails"
expect_out "highlight: source_field" "H9 names the source_field check"

# H9b — ineligible phase (reflect is private, in any round/position).
R="$(new_repo)"; init_index "$R"; mk_scenario "$R" demo_v1 '["reflect","summarize"]'
mk_highlight "$R" demo_v1 '[{"agent":"アヤ","round":1,"phase":"reflect","phase_index":0,"source_field":"statement","text":"心の中では。"}]'
link_highlight "$R" demo_v1
gate "$R"; expect_fail "H9b reflect excerpt fails"
expect_out "highlight: phase not excerpt-eligible" "H9b names the eligibility check"

# H10 — blocklist match, diacritic- and case-insensitive ("naïve" vs "naive").
R="$(new_repo)"; init_index "$R"; mk_scenario "$R" demo_v1 '["speak_each","summarize"]'
mk_highlight "$R" demo_v1 '[{"agent":"アヤ","round":1,"phase":"speak_each","phase_index":0,"source_field":"statement","text":"You are so NaÏve."}]'
link_highlight "$R" demo_v1
gate "$R"; expect_fail "H10 blocklist match fails"
expect_out "highlight: blocklist" "H10 names the blocklist check"
case "$OUT" in *naive*|*NaÏve*) bad "H10 leaked the matched term into the message";; *) PASS=$((PASS + 1));; esac

# H10b — blocklist match in the teaser (not just excerpt text).
R="$(new_repo)"; init_index "$R"; mk_scenario "$R" demo_v1 '["speak_each","summarize"]'
mk_highlight "$R" demo_v1 "$EX_OK" false "最後は殺すつもりだった。"
link_highlight "$R" demo_v1
gate "$R"; expect_fail "H10b blocklist match in teaser fails"
expect_out "teaser matches" "H10b locates the teaser"

# H11 — content_filter_applied must be exactly true.
R="$(new_repo)"; init_index "$R"; mk_scenario "$R" demo_v1 '["speak_each","summarize"]'
mk_highlight "$R" demo_v1 "$EX_OK"
python3 - "$R" <<'PY'
import json, sys
p = sys.argv[1] + "/docs/gallery/highlights/demo_v1.json"
doc = json.load(open(p)); doc["content_filter_applied"] = False
json.dump(doc, open(p, "w"), ensure_ascii=False, indent=2)
PY
link_highlight "$R" demo_v1
gate "$R"; expect_fail "H11 content_filter_applied false fails"
expect_out "highlight: content_filter_applied" "H11 names the attestation check"

# H12 — index declares a highlight whose file does not exist.
R="$(new_repo)"; init_index "$R"; mk_scenario "$R" demo_v1 '["speak_each","summarize"]'
mk_highlight "$R" demo_v1 "$EX_OK"; link_highlight "$R" demo_v1
rm "$R/docs/gallery/highlights/demo_v1.json"
gate "$R"; expect_fail "H12 missing highlight file fails"
expect_out "highlight: missing file" "H12 names the missing-file check"

# H13 — schema family: a highlight with `source` dropped fails as schema.
# (`source.model` is also the field the web build's guard checks, so this
# case covers both sides of the data-schema↔web seam.)
R="$(new_repo)"; init_index "$R"; mk_scenario "$R" demo_v1 '["speak_each","summarize"]'
mk_highlight "$R" demo_v1 "$EX_OK"
python3 - "$R" <<'PY'
import json, sys
p = sys.argv[1] + "/docs/gallery/highlights/demo_v1.json"
doc = json.load(open(p)); del doc["source"]
json.dump(doc, open(p, "w"), ensure_ascii=False, indent=2)
PY
link_highlight "$R" demo_v1
gate "$R"; expect_fail "H13 missing source fails"
expect_out "highlight: schema" "H13 names the schema check"

# H14 — phase_index naming a different phase than `phase` (distinct code
# path from H6's within-round bound; phases[:1] holds no outcome phase, so
# only the mismatch check can redden here).
R="$(new_repo)"; init_index "$R"; mk_scenario "$R" demo_v1 '["speak_each","summarize"]'
mk_highlight "$R" demo_v1 '[{"agent":"アヤ","round":1,"phase":"speak_each","phase_index":1,"source_field":"statement","text":"ずれてる。"}]'
link_highlight "$R" demo_v1
gate "$R"; expect_fail "H14 phase_index naming another phase fails"
expect_out "highlight: phase_index mismatch" "H14 names the mismatch check"

# --- yaml_hook.kind (ADR-029 § Amendment 2026-08-08) ---------------------
#
# H1 already covers the `raw` positive via the default hook. Each case below
# perturbs exactly one thing and asserts the *message*, not just the exit code:
# several of these checks live in the same funnel, so a bare `expect_fail`
# would pass on a neighbour's failure.

# H15 — the persona shape the app renders is accepted (positive control for
# every negative below; without it they could all be passing vacuously).
R="$(new_repo)"; init_index "$R"; mk_scenario "$R" demo_v1 '["speak_each","summarize"]'
mk_highlight "$R" demo_v1 "$EX_OK" false "最後の一言は、まだ言われていない。" "$HOOK_PERSONA"
link_highlight "$R" demo_v1
gate "$R"; expect_ok "H15 kind=persona with a well-formed fragment passes"

# H16 — a hook with no `kind` at all fails as schema. This is the shape every
# pre-amendment file has, so it is what the migration had to sweep.
R="$(new_repo)"; init_index "$R"; mk_scenario "$R" demo_v1 '["speak_each","summarize"]'
mk_highlight "$R" demo_v1 "$EX_OK" false "最後の一言は、まだ言われていない。" \
  '{"fragment":"phases:","caption":"cap"}'
link_highlight "$R" demo_v1
gate "$R"; expect_fail "H16 yaml_hook without kind fails"
expect_out "yaml_hook must be {kind: str" "H16 names kind in the schema message"

# H17 — a kind outside the allowlist fails, and is NOT silently treated as raw.
R="$(new_repo)"; init_index "$R"; mk_scenario "$R" demo_v1 '["speak_each","summarize"]'
mk_highlight "$R" demo_v1 "$EX_OK" false "最後の一言は、まだ言われていない。" \
  '{"kind":"phases","fragment":"phases:","caption":"cap"}'
link_highlight "$R" demo_v1
gate "$R"; expect_fail "H17 unlisted yaml_hook.kind fails"
expect_out "highlight: yaml_hook kind" "H17 names the kind allowlist check"

# H18 — `secret:` inside a persona fragment. The extractor's hard-fail reads
# the scenario YAML (E2), so before this the gate had no copy of the rule and
# a hand-edited hook could publish a hidden agenda.
R="$(new_repo)"; init_index "$R"; mk_scenario "$R" demo_v1 '["speak_each","summarize"]'
mk_highlight "$R" demo_v1 "$EX_OK" false "最後の一言は、まだ言われていない。" \
  '{"kind":"persona","fragment":"  - name: アヤ\n    description: 率直な被験者。\n    secret: 本当は協力者。","caption":"cap"}'
link_highlight "$R" demo_v1
gate "$R"; expect_fail "H18 secret: in a persona fragment fails"
expect_out "highlight: yaml_hook secret" "H18 names the secret check"

# H18b — the same `secret:` under kind=raw. This is the arm H18 alone did not
# cover: the check used to sit behind the persona branch, so a `raw` fragment —
# published verbatim on both surfaces, and the likelier place for an unreviewed
# paste — carried a hidden agenda straight through the gate.
R="$(new_repo)"; init_index "$R"; mk_scenario "$R" demo_v1 '["speak_each","summarize"]'
mk_highlight "$R" demo_v1 "$EX_OK" false "最後の一言は、まだ言われていない。" \
  '{"kind":"raw","fragment":"personas:\n  - name: アヤ\n    secret: 本当は協力者。","caption":"cap"}'
link_highlight "$R" demo_v1
gate "$R"; expect_fail "H18b secret: in a raw fragment fails"
expect_out "highlight: yaml_hook secret" "H18b names the secret check"

# H18c — a sequence-item `- secret:` form, which the line scan must also see.
R="$(new_repo)"; init_index "$R"; mk_scenario "$R" demo_v1 '["speak_each","summarize"]'
mk_highlight "$R" demo_v1 "$EX_OK" false "最後の一言は、まだ言われていない。" \
  '{"kind":"raw","fragment":"  - secret: 本当は協力者。","caption":"cap"}'
link_highlight "$R" demo_v1
gate "$R"; expect_fail "H18c sequence-item secret: fails"
expect_out "highlight: yaml_hook secret" "H18c names the secret check"

# H19 — kind=persona over a fragment that is not a persona list. The `phases:`
# fragment is legal under `raw` (H1) and illegal here, which is the whole point
# of the discriminator.
R="$(new_repo)"; init_index "$R"; mk_scenario "$R" demo_v1 '["speak_each","summarize"]'
mk_highlight "$R" demo_v1 "$EX_OK" false "最後の一言は、まだ言われていない。" \
  '{"kind":"persona","fragment":"phases:\n  - type: speak_each","caption":"cap"}'
link_highlight "$R" demo_v1
gate "$R"; expect_fail "H19 kind=persona over a non-persona fragment fails"
expect_out "not a non-empty persona list" "H19 names the shape check"

# H20 — a key outside {name, description}. Distinct from H18: `secret` has its
# own named failure, so a generic-key case is needed to reach the other arm.
R="$(new_repo)"; init_index "$R"; mk_scenario "$R" demo_v1 '["speak_each","summarize"]'
mk_highlight "$R" demo_v1 "$EX_OK" false "最後の一言は、まだ言われていない。" \
  '{"kind":"persona","fragment":"  - name: アヤ\n    description: 率直な被験者。\n    mood: 不安","caption":"cap"}'
link_highlight "$R" demo_v1
gate "$R"; expect_fail "H20 unknown persona key fails"
expect_out "outside the allowlist" "H20 names the key allowlist check"

# H21 — the `personas:`-keyed shape is the second form Decision 1 accepts.
R="$(new_repo)"; init_index "$R"; mk_scenario "$R" demo_v1 '["speak_each","summarize"]'
mk_highlight "$R" demo_v1 "$EX_OK" false "最後の一言は、まだ言われていない。" \
  '{"kind":"persona","fragment":"personas:\n  - name: アヤ\n    description: 率直な被験者。","caption":"cap"}'
link_highlight "$R" demo_v1
gate "$R"; expect_ok "H21 personas:-keyed persona fragment passes"

# H22 — a fragment that is not parseable YAML at all.
R="$(new_repo)"; init_index "$R"; mk_scenario "$R" demo_v1 '["speak_each","summarize"]'
mk_highlight "$R" demo_v1 "$EX_OK" false "最後の一言は、まだ言われていない。" \
  '{"kind":"persona","fragment":"  - name: [アヤ\n    description: 壊れている","caption":"cap"}'
link_highlight "$R" demo_v1
gate "$R"; expect_fail "H22 unparseable persona fragment fails"
expect_out "not parseable YAML" "H22 names the parse failure"

# H23 — a `personas:` key with a sibling. The shape is rejected either way; what
# this pins is the *message*, which used to say "not a persona list" of a
# fragment that visibly has one.
R="$(new_repo)"; init_index "$R"; mk_scenario "$R" demo_v1 '["speak_each","summarize"]'
mk_highlight "$R" demo_v1 "$EX_OK" false "最後の一言は、まだ言われていない。" \
  '{"kind":"persona","fragment":"personas:\n  - name: アヤ\n    description: d\nphases:\n  - type: speak_each","caption":"cap"}'
link_highlight "$R" demo_v1
gate "$R"; expect_fail "H23 personas: with a sibling key fails"
expect_out "parsed top level was a mapping with keys" "H23 names what it parsed instead"

# H24 — non-string YAML keys. `sorted()` over a mixed-type key set raises
# TypeError, which would abort the run with a traceback instead of the
# one-failure-per-line contract the module promises. Two extras are required:
# a single one never reaches a comparison.
R="$(new_repo)"; init_index "$R"; mk_scenario "$R" demo_v1 '["speak_each","summarize"]'
mk_highlight "$R" demo_v1 "$EX_OK" false "最後の一言は、まだ言われていない。" \
  '{"kind":"persona","fragment":"  - name: アヤ\n    description: d\n    mood: x\n    1: c","caption":"cap"}'
link_highlight "$R" demo_v1
gate "$R"; expect_fail "H24 mixed-type extra keys fail"
expect_out "outside the allowlist" "H24 reports rather than tracebacks"

# ============================== extractor ================================

# mk_run <repo> <path> — a minimal 4-round transcript. Line numbers:
#   1 run_start, 2 round_started(1), 3 phase_started(speak_each, idx 0),
#   4 agent_output(アヤ), 5 phase_started(summarize, idx 1), 6 summary,
#   7 round_started(4), 8 phase_started(speak_each, idx 0),
#   9 agent_output(アヤ, round 4), 10 run_end
mk_run() {
  cat > "$2" <<'JSONL'
{"type":"run_start","run_id":"run-1","date":"2026-08-05","scenario_id":"demo_v1","scenario_name":"T","language":"ja","model":"gemma-4-e2b-q4-k-m","timeout_sec":900,"estimated_inferences":12}
{"type":"event","t":0.1,"attempt":1,"event":"round_started","round":1,"total_rounds":4}
{"type":"event","t":0.2,"attempt":1,"event":"phase_started","phase_type":"speak_each","phase_path":[0]}
{"type":"event","t":0.3,"attempt":1,"event":"agent_output","agent":"アヤ","phase_type":"speak_each","fields":{"statement":"私はBだと思う。","inner_thought":"本当はCかも。"}}
{"type":"event","t":0.4,"attempt":1,"event":"phase_started","phase_type":"summarize","phase_path":[1]}
{"type":"event","t":0.5,"attempt":1,"event":"summary","value":"1周目が終わった。"}
{"type":"event","t":0.6,"attempt":1,"event":"round_started","round":4,"total_rounds":4}
{"type":"event","t":0.7,"attempt":1,"event":"phase_started","phase_type":"speak_each","phase_path":[0]}
{"type":"event","t":0.8,"attempt":1,"event":"agent_output","agent":"アヤ","phase_type":"speak_each","fields":{"statement":"もう言うしかない。"}}
{"type":"event","t":0.9,"attempt":1,"event":"run_end","run_id":"run-1","status":"ok","attempts":1,"duration_sec":9.0}
JSONL
}

mk_selection() {  # repo path
  cat > "$2" <<'JSON'
{
  "picks": [4],
  "yaml_hook": { "kind": "raw", "fragment": "phases:\n  - type: speak_each", "caption": "この一行が会話を生む" },
  "teaser": "最後の一言は、まだ言われていない。"
}
JSON
}

# E1 — end-to-end: extractor writes a file the gate then accepts.
R="$(new_repo)"; init_index "$R"; mk_scenario "$R" demo_v1 '["speak_each","summarize"]'
mk_run "$R" "$R/run.jsonl"; mk_selection "$R" "$R/sel.json"
runc "$R" python3 scripts/gallery_highlight_extract.py --run run.jsonl --id demo_v1 --selection sel.json --generated-at 2026-08-05
expect_ok "E1 extractor exits 0"
expect_out "1 excerpt entries" "E1 reports the excerpt count"
if [ -f "$R/docs/gallery/highlights/demo_v1.json" ]; then PASS=$((PASS + 1)); else bad "E1 wrote no highlight file"; fi
runc "$R" jq -r '[.excerpt[0].round, .excerpt[0].phase_index, .excerpt[0].text] | @tsv' docs/gallery/highlights/demo_v1.json
expect_out "1	0	私はBだと思う。" "E1 derives round from round_started + phase_index from phase_started"
link_highlight "$R" demo_v1
gate "$R"; expect_ok "E1 extractor output passes the gate end-to-end"

# E1b — deterministic output: a second run is byte-identical.
B1="$(sha "$R/docs/gallery/highlights/demo_v1.json")"
runc "$R" python3 scripts/gallery_highlight_extract.py --run run.jsonl --id demo_v1 --selection sel.json --generated-at 2026-08-05
B2="$(sha "$R/docs/gallery/highlights/demo_v1.json")"
if [ "$B1" = "$B2" ]; then PASS=$((PASS + 1)); else bad "E1b output is not byte-deterministic"; fi

# E2 — secret-declaring scenario hard-fails.
R="$(new_repo)"; init_index "$R"; mk_scenario "$R" demo_v1 '["speak_each","summarize"]' 4 secret
mk_run "$R" "$R/run.jsonl"; mk_selection "$R" "$R/sel.json"
runc "$R" python3 scripts/gallery_highlight_extract.py --run run.jsonl --id demo_v1 --selection sel.json
expect_fail "E2 secret-declaring scenario fails"
expect_out "secret mechanism" "E2 names the secret hard-fail"

# E3 — a pick outside the round window is refused, and accepted with the flag.
R="$(new_repo)"; init_index "$R"; mk_scenario "$R" demo_v1 '["speak_each","summarize"]'
mk_run "$R" "$R/run.jsonl"; mk_selection "$R" "$R/sel.json"
runc "$R" python3 scripts/gallery_highlight_extract.py --run run.jsonl --id demo_v1 --pick 9 \
  --yaml-hook-kind raw --yaml-hook-fragment "phases:" --yaml-hook-caption "cap" --teaser "まだ終わらない。"
expect_fail "E3 late-round pick fails without --window-override"
expect_out "highlight: round window" "E3 names the round-window check"
runc "$R" python3 scripts/gallery_highlight_extract.py --run run.jsonl --id demo_v1 --pick 9 \
  --window-override --yaml-hook-kind raw --yaml-hook-fragment "phases:" --yaml-hook-caption "cap" --teaser "まだ終わらない。"
expect_ok "E3 --window-override accepts the late-round pick"
runc "$R" jq -r '.window_override' docs/gallery/highlights/demo_v1.json
expect_out "true" "E3 records window_override: true"

# E4 — a pick that is not an agent_output line is refused.
R="$(new_repo)"; init_index "$R"; mk_scenario "$R" demo_v1 '["speak_each","summarize"]'
mk_run "$R" "$R/run.jsonl"
runc "$R" python3 scripts/gallery_highlight_extract.py --run run.jsonl --id demo_v1 --pick 6 \
  --yaml-hook-kind raw --yaml-hook-fragment "phases:" --yaml-hook-caption "cap" --teaser "t"
expect_fail "E4 summary-line pick fails"
expect_out "not an \`agent_output\` event" "E4 names the pick check"

# E5 — an unknown phase name in the transcript hard-fails.
R="$(new_repo)"; init_index "$R"; mk_scenario "$R" demo_v1 '["speak_each","summarize"]'
mk_run "$R" "$R/run.jsonl"; mk_selection "$R" "$R/sel.json"
sed 's/"phase_type":"summarize"/"phase_type":"teleport"/' "$R/run.jsonl" > "$R/run2.jsonl"
runc "$R" python3 scripts/gallery_highlight_extract.py --run run2.jsonl --id demo_v1 --selection sel.json
expect_fail "E5 unknown phase name fails"
expect_out "unknown phase" "E5 names the phase-catalog tripwire"

# E6 — a stale gallery.json yaml_sha256 refuses extraction.
R="$(new_repo)"; init_index "$R"; mk_scenario "$R" demo_v1 '["speak_each","summarize"]'
mk_run "$R" "$R/run.jsonl"; mk_selection "$R" "$R/sel.json"
printf '\n# drift\n' >> "$R/docs/gallery/demo_v1.yaml"
runc "$R" python3 scripts/gallery_highlight_extract.py --run run.jsonl --id demo_v1 --selection sel.json
expect_fail "E6 stale index yaml_sha256 fails"
expect_out "yaml_sha256 mismatch" "E6 names the yaml sha check"

# E7 — no picks: the tool never chooses excerpts itself.
R="$(new_repo)"; init_index "$R"; mk_scenario "$R" demo_v1 '["speak_each","summarize"]'
mk_run "$R" "$R/run.jsonl"
runc "$R" python3 scripts/gallery_highlight_extract.py --run run.jsonl --id demo_v1 \
  --yaml-hook-kind raw --yaml-hook-fragment "phases:" --yaml-hook-caption "cap" --teaser "t"
expect_fail "E7 missing picks fails"
expect_out "no picks" "E7 refuses to choose excerpts"

# E8 — blocklist match in the picked text blocks the write.
R="$(new_repo)"; init_index "$R"; mk_scenario "$R" demo_v1 '["speak_each","summarize"]'
mk_run "$R" "$R/run.jsonl"
sed 's/私はBだと思う。/こいつを殺すしかない。/' "$R/run.jsonl" > "$R/run3.jsonl"
runc "$R" python3 scripts/gallery_highlight_extract.py --run run3.jsonl --id demo_v1 --pick 4 \
  --yaml-hook-kind raw --yaml-hook-fragment "phases:" --yaml-hook-caption "cap" --teaser "t"
expect_fail "E8 blocklist match blocks extraction"
expect_out "highlight: blocklist" "E8 names the blocklist check"
if [ ! -e "$R/docs/gallery/highlights/demo_v1.json" ]; then PASS=$((PASS + 1)); else bad "E8 wrote a file despite the blocklist failure"; fi

# E9 — a pick from a discarded retry attempt is refused (a retried run
# renumbers rounds, so an attempt-1 pick would be mis-contextualized).
R="$(new_repo)"; init_index "$R"; mk_scenario "$R" demo_v1 '["speak_each","summarize"]'
mk_run "$R" "$R/run.jsonl"
python3 - "$R/run.jsonl" <<'PY'
import sys
p = sys.argv[1]
lines = open(p, encoding="utf-8").read().rstrip("\n").split("\n")
retry = [l.replace('"attempt":1', '"attempt":2') for l in lines[1:-1]]
open(p, "w", encoding="utf-8").write("\n".join(lines[:-1] + retry + [lines[-1]]) + "\n")
PY
runc "$R" python3 scripts/gallery_highlight_extract.py --run run.jsonl --id demo_v1 --pick 4 \
  --yaml-hook-kind raw --yaml-hook-fragment "phases:" --yaml-hook-caption "cap" --teaser "t"
expect_fail "E9 attempt-1 pick in a retried log fails"
expect_out "final attempt" "E9 names the attempt guard"

# E10 — the extractor refuses to guess a kind. It has the fragment in hand and
# could sniff it, which is precisely what the discriminator exists to stop:
# `persona` vs `raw` is a presentation decision belonging to the curator.
R="$(new_repo)"; init_index "$R"; mk_scenario "$R" demo_v1 '["speak_each","summarize"]'
mk_run "$R" "$R/run.jsonl"
runc "$R" python3 scripts/gallery_highlight_extract.py --run run.jsonl --id demo_v1 --pick 4 \
  --yaml-hook-fragment "phases:" --yaml-hook-caption "cap" --teaser "t"
expect_fail "E10 omitted yaml_hook.kind fails"
expect_out "missing yaml_hook.kind" "E10 names the missing field"

# E10b — and refuses an unlisted one rather than falling back to raw.
runc "$R" python3 scripts/gallery_highlight_extract.py --run run.jsonl --id demo_v1 --pick 4 \
  --yaml-hook-kind phases --yaml-hook-fragment "phases:" --yaml-hook-caption "cap" --teaser "t"
expect_fail "E10b unlisted yaml_hook.kind fails at extraction"
expect_out "is not in the allowlist" "E10b names the allowlist"

echo "gallery-highlight-test: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
