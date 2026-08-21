---
paths:
  - "Pastura/Pastura/Resources/Localizable.xcstrings"
---

# Localizable.xcstrings — catalog & tooling procedures

Editing the catalog and surviving `xcstringstool sync`. Authoring: `i18n.md`, `i18n-ui.md`.

## xcstringstool sync output

`scripts/xcodebuild.sh build` auto-runs `xcstringstool sync`. A multi-arg key lands with a
positional-form `en` block, Apple's translator reference: **add `ja` beside it under
`localizations`, never replacing `en`**. The dominant freshly-extracted shape, though, is an empty
body (`"Key" : { }`) — multi-arg keys land empty too, until a later sync settles them. So **don't
grep `state : "new"` for new keys**; `git diff`, and treat every new key as needing `ja`. Sync
auto-prunes empty `"…" : { }` orphans, but an `extractionState: "stale"` entry with populated
localizations survives it and needs `scripts/xcstrings-prune-stale.py`.

## Xcode IDE re-serialization — the CLI form is canonical, discard Xcode's

Xcode's String Catalog editor re-serializes the file differently from `xcstringstool sync` — a big
diff with key reordering and a leading empty `"" : {}` key. Expected divergence — the IDE build has
type info, the CLI does not. The CLI form is what the wrapper, hook, and CI enforce, so discard the
editor's (`git restore …/Localizable.xcstrings`); its artifacts return on every open.

## state=new + en-only after sync

`check_localization_coverage.py` fails CI on a missing `ja`, on `ja state != "translated"`, and on
an explicit `en` block whose `state != "translated"` — so after a commit touching a
`String(localized:)` literal, add `ja`, flip **both** states, run it. It never checks value
correctness: when a new key replaces an old translated one, copy the old `ja` forward.

## Catalog editing — don't json.dumps round-trip

Editing via `json.loads` + `json.dumps(indent=2)` produces a phantom multi-thousand-line diff at the
next sync: Apple separates object keys with ` : `, Python's default is `: `, and sync rewrites every
line. For 1–3 edits use the Edit tool with the exact canonical shape; for batch edits pass
`separators=(',', ' : ')`, then sync and confirm zero drift. `git diff --stat` must stay
proportional — 1000+ lines for a small edit is a format mismatch.

## Batch ja-fill — preserve shared keys

A script that fills `ja` across many keys will **silently overwrite** an existing value, and short
status nouns are not exporter-exclusive: `Paused`, `Cancelled`, `Completed` are exact
`GameHeaderStatus.label` keys driving the live status pill, so an export-scoped slice re-filling one
shifts another surface's copy with no code edit — and a wrong-but-translated `ja` passes coverage.
Grep each key's consumers first
(`rg -F 'String(localized: "KEY")' Pastura/Pastura --type swift`): ≥2 consumers on different
surfaces means **shared** — reuse the prior `ja` or split the keys — and keep the script idempotent.

## A role word in ja copy must follow `thoughtField`, not "this field feels private"

「心の声」 is the ja value of **both** the `INNER VOICE` transcript header and the editor's `Thought`
role pill, so it names exactly the fields `ScenarioConventions.thoughtField(for:)` resolves to —
`inner_thought`, `reason`. `reflect`'s `note` does **not** qualify (`thoughtField(.reflect)` is
`nil`): it is that phase's *primary* field, pilled 「主フィールド」, never in the 「心の声」 section, so
its ja takes 「非公開メモ」 (`PromptBuilder+PrivateSections.swift`). Read the resolver first: nothing
mechanical catches a wrong role word — it type-checks and passes coverage.

## Merge conflicts in the catalog

When parallel PRs add **alphabetically-adjacent** keys, git's conflict markers ignore JSON key
boundaries — they land mid-block, so repairing region by region silently mis-assigns keys. Read the
full conflicted span (previous resolved key → next) and **reconstruct the whole region** —
ours-added, theirs-added, unchanged, sorted alphabetically — as one Edit, then verify with
`json.load` plus the coverage checker.
