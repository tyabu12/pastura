---
paths:
  - "Pastura/Pastura/Resources/Localizable.xcstrings"
---

# Localizable.xcstrings — catalog & tooling procedures

Editing the catalog itself, and surviving `xcrun xcstringstool sync`'s output. The
Swift-authoring side is split by layer: the callsite core — Form B, the Form A fallback hazard —
is `i18n.md`; plurals and audit planning are `i18n-ui.md`. Both match this path too, so a catalog
session loads all three.

⚠️ **This file loads on a `Read` of the catalog — not on a script run.** A batch ja-fill
or `scripts/xcstrings-prune-stale.py` mutates the catalog without any agent `Read`, so
§ "Catalog editing — don't json.dumps round-trip" and § "Batch ja-fill — preserve shared
keys" are absent from exactly the sessions they govern. **Read this file explicitly
before any scripted catalog mutation.**

## xcstringstool sync output

`scripts/xcodebuild.sh build` auto-runs `xcrun xcstringstool sync` against `Localizable.xcstrings`. For **multi-arg** keys, sync generates a catalog entry with the source key plus a positional-form `en` block:

```json
"%@ assigned: %@" : {
  "localizations" : {
    "en" : {
      "stringUnit" : { "state" : "new", "value" : "%1$@ assigned: %2$@" }
    }
  }
}
```

The `en` block is Apple's disambiguated positional form, kept as a translator reference. **Add the `ja` block as a sibling under `localizations`, never replace the `en` block.** Single-arg keys (`"%@ is thinking..."`) get an empty body — insert the full `localizations.ja.stringUnit` structure.

Empty-body (`"Key" : { }`, no `localizations` block at all) is in fact the dominant *freshly-extracted* shape: multi-arg keys land empty too on first extract, **before** a later sync settles them into the positional-`en` form shown above. So don't grep `state : "new"` to find new keys — that misses the empty-body shape. `git diff` the catalog and treat any newly-added key (empty-body OR `state:"new"`) as needing a `ja` block.

## Xcode IDE re-serialization — the CLI form is canonical, discard Xcode's

Opening `Localizable.xcstrings` in the **Xcode String Catalog editor** (or
building from the IDE) re-serializes it into a different canonical form
than `xcrun xcstringstool sync` produces — a large diff (key reordering,
a leading empty `"" : {}` key, and — if any Form A site survives — Form A
interpolations rendered as typed `%@`/`%lld` instead of the CLI's `%arg`).
This is **expected divergence**, not a bug: the IDE build has compile-time
type info; the CLI tool does not.

**The CLI (`xcstringstool sync`) form is canonical** — it is what
`scripts/xcodebuild.sh build|test`, the pre-commit hook, and CI all
enforce. **Discard Xcode's editor re-serialization** (`git restore
Pastura/Pastura/Resources/Localizable.xcstrings`); never commit it. A few
artifacts (the empty `""` key, `'Pastura'` from Info.plist) reappear on
every Xcode open — inherent, not actionable.

Converting Form A → Form B (`i18n.md` § "Form A is a runtime hazard at user-facing
callsites") removes the
`%arg`/`%@` divergence class for those keys, since the source literal then
holds an explicit `%@`/`%lld` both tools extract identically. See #629.

## state=new + en-only after sync

Sync also leaves new entries with `state: "new"` on the en entry and no `ja` localization. `scripts/check_localization_coverage.py` fails CI on both conditions (missing `ja` AND `ja` `state != "translated"`), and — when sync emits an explicit `en` block (multi-arg positional forms) — also when that `en` block's `state != "translated"`. So step 3 below ("flip BOTH") is enforced on both halves.

After any commit touching a `String(localized:)` literal:

1. Run `git diff Pastura/Pastura/Resources/Localizable.xcstrings` — confirm only intended changes
2. Add the `ja` localization for new keys
3. Flip BOTH `en` and `ja` `state` to `"translated"`
4. Verify with `python3 scripts/check_localization_coverage.py` before pushing — runs in <1s

When a new key replaces an old translated one (rename / format-arg change), copy the existing `ja` value forward — usually a 1–2 token edit to match the new placeholder shape.

## Catalog editing — don't json.dumps round-trip

Editing `Localizable.xcstrings` programmatically via Python `json.loads(...)` + edit + `json.dumps(indent=2)` produces a phantom multi-thousand-line diff after the next sync. Apple-canonical format uses ` : ` (space-colon-space) for object key-value separators; Python's `json.dumps` default uses `: `. The next `xcstringstool sync` rewrites every line to Apple-canonical, engulfing the small edit.

- **For 1–3 targeted edits**: use the Edit tool with the exact Apple-canonical format. Match an existing translated entry's shape (see § "xcstringstool sync output" for the canonical structure).
- **For programmatic batch edits**: pass `separators=(',', ' : ')` to `json.dumps` so output matches Apple format. Verify by running `xcrun xcstringstool sync` after — should produce zero further drift.

Sanity check after any catalog edit: `git diff --stat Pastura/Pastura/Resources/Localizable.xcstrings` should be proportional to the change. 1000+ lines for a 1–3 key edit means format mismatch.

## Batch ja-fill — preserve shared keys

A Python script that fills `ja` across many catalog keys at once will **silently overwrite** an existing `ja` value. The hazard: short status nouns (`Paused`, `Cancelled`, `Completed` are exact `GameHeaderStatus.label` keys) are not exporter-exclusive — `GameHeaderStatus.label` drives the live status pill on Sim / Demo screens. An export-scoped slice that re-fills one of these shifts the *other* surface's copy without touching its code.

`scripts/check_localization_coverage.py` does **not** catch this: it validates *presence + state + non-emptiness + extractionState*, never *value correctness*. A wrong-but-translated `ja` passes the gate clean, so the drift reaches main silently (caught only by a code-reviewer reading the catalog diff).

**Before a batch ja-fill:** grep every target key's consumers —
`rg -F 'String(localized: "KEY")' Pastura/Pastura --type swift`. A key with ≥2 consumers on different surfaces is **shared**: reuse its prior `ja` verbatim, or split into export-only keys. Make the script idempotent — skip the overwrite when `state == "translated"` and `value` is non-empty. See #382 (a `Paused` ja value shifted under an unrelated export wrap).

## A role word in ja copy must follow `thoughtField`, not "this field feels private"

Same blind spot as the section above (coverage never checks *value correctness*), but the
failure is semantic rather than an overwrite. 「心の声」 is the ja value of **both** the
`INNER VOICE` transcript header and the editor's `Thought` role pill, so it names exactly one
role: a field that `ScenarioConventions.thoughtField(for:)` resolves to. Only `inner_thought`
(speak / choose / whisper) and `reason` (vote) qualify.

`reflect`'s `note` does **not** — `thoughtField(.reflect)` returns `nil` by design because
`note` is that phase's *primary* field. It is pilled 「主フィールド」 in the editor and never
renders in the 「心の声」 section, so its ja copy takes a neutral 「非公開メモ」 (which is also
its en sibling's reading, "private memo"). The ja prompt headers in
`PromptBuilder+PrivateSections.swift` and the Kotlin port carry the same split.

**Apply**: before writing a role word into a field's ja copy, read the resolver — every
private-to-the-viewer field is *not* a 心の声 field. Nothing mechanical catches a wrong choice:
it type-checks, translates, and passes coverage. See #1293 for the case where the wrong premise
survived a plan critique and reached review.

## Merge conflicts in the catalog

When parallel PRs add **alphabetically-adjacent** keys, `git merge` produces conflict markers that do **not** respect JSON key boundaries — they land mid-block, splitting both sides' keys across several `<<<<<<< / ======= / >>>>>>>` regions. Cause: the catalog's repeated structure (`"localizations" : { "en" : { "stringUnit" … } }`) gives git's line-level aligner many short anchor matches, so it picks alignment that minimizes line count, not key boundaries.

Don't repair each region in isolation — the markers are line-aligned, not key-aligned. Read the full conflicted span (previous resolved key → next resolved key), then **reconstruct the whole region**: all ours-added + theirs-added + unchanged keys, sorted alphabetically (xcstringstool's canonical order), as a single Edit. Verify with `python3 -c "import json; json.load(open('Pastura/Pastura/Resources/Localizable.xcstrings'))"` + `check_localization_coverage.py`. See #409.

## Sync side-effects safe to ignore at plan time

`scripts/xcodebuild.sh build` auto-runs `xcstringstool sync`, which has two harmless side-effects worth not over-handling:

- **Empty ja-as-source orphans are auto-pruned.** Wrapping a Japanese-hardcoded literal (`Text("準備ができました")` → `String(localized: "Ready")`) leaves the old `"準備ができました" : { }` orphan — but the next sync drops it automatically. Skip the explicit `xcstrings-prune-stale.py` step in a plan when the orphans are empty `{ }`. (Prune is still needed for `extractionState: "stale"` entries that carry populated `localizations` — Apple keeps those for translator reference.)
- **Trailing LF is stripped.** Sync rewrites the file ending without a final newline. Cosmetic — Xcode and xcstringstool tolerate either form, CI is green either way; ignore unless code review flags it (then `printf '\n' >> …xcstrings`).

