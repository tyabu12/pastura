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
`prisoners_dilemma`, `bokete`, `target_score_race`, `word_wolf`.

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
