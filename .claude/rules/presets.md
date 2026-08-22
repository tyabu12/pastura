---
paths:
  - "Pastura/Pastura/Resources/**"
---

# Preset YAML Scenarios

Bundled scenarios live in `Resources/Presets/`; those files are the single source
of truth for their content and schema. Read the actual file rather than any copy.

## Conventions

- **Fixture coupling is structural, not textual.** These files are BOTH
  user-facing presets AND test fixtures. Renaming/removing a preset, dropping an
  `_en` sibling, or changing the preset count / `language` / `sourceId` breaks
  `PresetLoaderTests` and `BundledPresetSourceIdSchemaTests`; an unknown
  `{placeholder}` token breaks `BundledPresetPlaceholderCoverageTests`. Editing
  persona *wording* or *topic text* alone is safe — those suites key on ids,
  schema shape, and placeholder tokens, not literal content.
- **ja/en parity is about mechanics.** Keep the `_en` sibling in sync on phases,
  agent count, and topic/word count; wording is localized, mechanics are not.
  Only the structural half (ids, counts, schema shape) is incidentally pinned by
  the preset suites, so a sibling can diverge in mechanics with everything green.
- **`assign` with `target: all` — self-framing topic values.** The shared お題
  renders as one line with the value **verbatim** and no "Topic:"/"お題:" label
  (`SimulationEvent.sharedAssignment`), so each `source:`/`topics` entry must read
  as a complete self-framing statement (`やらかし「…」`, `Your blunder: …`,
  `お悩み:「…」`, `Problem: …`). A bare noun renders contextless, and nothing
  fails.

## Scenario design defaults — bias toward "subtract"

Canonical: `.claude/skills/scenario-factory/PLAYBOOK.md` § "Subtract by default".

## The register-dominance law

Gemma 4 E2B's behavior follows a persona's **register** — its tone, archetype,
and the phase structure around it — **not** the persona's stated goal or the
wording of its instructions. A "scheming" goal reaches `inner_thought` but rarely
changes what the agent *does*; a per-turn state field like `mood` fixates on its
seed value and echoes it mechanically rather than tracking events.

**Apply:** to change agent *behavior*, change **structure** — phase design,
forced events, hard-binary choices, non-mappable persona values — not goal prose
or "be dynamic" nudges. A wording-only lever ships, moves flavor, and changes no
action, with nothing to show that it did nothing. The remedy has a floor: a
quantitative form constraint the model cannot evaluate (5-7-5 mora allocation)
does not load through structure either — a `reflect`-then-`speak` counting
phase scored 2/16 against a 0/16 control — so relax the promise rather than add a
lever. Reference: `docs/models/eval-log.md` (§ Corpus observations).
