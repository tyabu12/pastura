---
paths:
  - "Pastura/Pastura/Resources/**"
---

# Preset YAML Scenarios

Bundled scenarios live in `Resources/Presets/` (originally converted from the
Python prototype's hardcoded scenarios). **Do NOT embed preset YAML in full
here** — the source files are the single source of truth, and an inline copy
drifts silently. It did: this file's snapshots had diverged from the shipped
files in `description`, `context`, persona wording, the `rounds`/`topics`
counts, the `summarize` phase, and the `language:` field. Read the actual file
instead.

Current inventory (each has an `_en` sibling — see i18n below):
`prisoners_dilemma`, `bokete`, `target_score_race`, `word_wolf`, `last_fable`.

## Conventions

- **File naming**: snake_case matching `id:` (e.g. `prisoners_dilemma.yaml`).
  The English variant is `<id>_en.yaml` with `language: en`.
- **`language:` is required** (`ja` / `en`) — it drives runtime preset
  selection (#388), and `ScenarioLoader` rejects a preset that omits it (no
  backward-compat fill). A preset without it is a bug.
- **Dual-purpose = fixture coupling (load-bearing).** These files are BOTH
  user-facing presets AND test fixtures — but the coupling is **structural, not
  textual**. Renaming/removing a preset, dropping an `_en` sibling, or changing
  the preset count / `language` / `sourceId` breaks `PresetLoaderTests` and
  `BundledPresetSourceIdSchemaTests`; introducing an unknown `{placeholder}`
  token in a prompt/template breaks `BundledPresetPlaceholderCoverageTests`.
  Editing persona *wording* or *topic text* alone is safe (those suites key on
  ids, schema shape, and placeholder tokens — not literal content). Still, grep
  the `id` across `PasturaTests/` and run the affected suite
  (`scripts/xcodebuild.sh test -only-testing PasturaTests/<Suite>`) before
  committing a preset change.
- **Schema is owned by code, not duplicated here.** The field shape
  (`id`/`name`/`description`/`agents`/`rounds`/`context`/`personas`/`phases`)
  is defined by the `Scenario` model + `ScenarioLoader`; the canonical
  per-phase LLM output field names (`statement` / `inner_thought` for speak,
  `action` for choose, `vote` / `reason` for vote) live in
  `ScenarioConventions.swift`. Scenario-specific extra fields (e.g. bokete's
  `topics`, word wolf's `words`) are modelled as `Scenario.extraData` and
  referenced by the `assign` phase's `source:` — the field list above is not
  a closed set.
- **ja/en parity**: keep the `_en` sibling structurally in sync (same phases,
  agent count, topic/word count); wording is localized, mechanics are not.
- **`assign` with `target: all` — self-framing topic values (#939).** The shared
  お題 renders as one line with the value **verbatim** and no "Topic:"/"お題:"
  label (`SimulationEvent.sharedAssignment`), so each `source:`/`topics` entry
  must read as a complete self-framing statement (e.g. `やらかし「…」`,
  `Your blunder: …`, `お悩み:「…」`, `Problem: …`) — a bare noun would render
  contextless.

## Scenario design defaults — bias toward "subtract" (#919)

Default a new scenario to the SMALLER shape; each addition trades against 2B
breakdown rate, tokens, and on-device latency, so additions need a stated
reason. These are **defaults for NEW scenarios** — the shipped presets (4 of 5
run 5 agents) predate the guideline, not violations of it. Guides with a
reason-for-deviation, not hard rules. (The interestingness proposals in #906
bias toward *adding* fields/phases — this section is the brake.)

- **Output fields: 2 (`statement` + `inner_thought`).** Each extra output field
  is another grammar-constrained value per turn — more JSON-parse-failure
  exposure, tokens, and wait. Add a third only with a reason (canonical field
  names in Conventions above / `ScenarioConventions`).
- **Agents: 3–4.** Five agents × several rounds is a long on-device wait
  (inference target ≤50 — scenario-factory SKILL Step 2); a triangle also reads
  clearer than a pentagon (general drama-design rule). An axis that genuinely
  needs more (elimination bracket) is a reasoned exception.
- **Log growth: design for 2B long-context decay.** Long transcripts degrade the
  model — cap rounds, or scope prompt visibility with `log_window: N` (#907);
  don't assume a clean full log in a long run.
- **Scoring is optional.** Not every scenario must end as a game-show tally. Drop
  the `vote → score_calc → summarize` spine when the payoff is the phenomenon
  itself — `scoring_free` observation and a `narrate` (#909) score-free ending
  are first-class.

## The register-dominance law (#958)

Gemma 4 E2B's behavior follows a persona's **register** — its tone, archetype,
and the phase structure around it — **not** the persona's stated goal or the
wording of its instructions. A "scheming" goal reaches `inner_thought` but rarely
changes what the agent *does* (#958); a per-turn state field like `mood` fixates
on its seed value and echoes it mechanically rather than tracking events (#913 — a
seeded mood token was copied verbatim across four turns while the agent was under
direct attack).

**Apply:** to change agent *behavior*, change **structure** — phase design, forced
events, hard-binary choices, non-mappable persona values — not goal prose or "be
dynamic" nudges. Wording-only levers move flavor, not action; confirmed by #911
(framing > instruction), #957 (whisper pays off only where game structure fits it),
#958 / #913 (goal/mood wording inert). This is *why* the subtract-by-default
default above holds: the model rides structure, so give it structure, not more
words.
