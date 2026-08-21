---
paths:
  - "Pastura/Pastura/Views/**"
  - "Pastura/Pastura/App/**"
  - "Pastura/Pastura/PasturaApp.swift"
  - "Pastura/PasturaTests/Localization/**"
  - "Pastura/Pastura/Resources/Localizable.xcstrings"
---

# i18n Rules — UI layer

`i18n.md` carries the layer-independent callsite core.

## Plurals — the sanctioned exception to Form B

Form B substitutes the count *after* the lookup, so one form renders for every count ("1 records").
A plural needs the count to reach the localization layer, so **interpolation is correct here and
nowhere else**.

1. **The callsite is the SwiftUI `Text("\(count) records")` form** — the `Int` interpolation drives
   variant selection. Not `String(localized: "…\(x)…")`, which SwiftLint blocks; nothing outside
   `Text` is sanctioned.

2. **Catalog shape** — `en` gets `variations.plural`, `ja` stays single-form. Japanese CLDR has
   only `other`: never invent a `ja` plural bucket; its `stringUnit` resolves for every count,
   n=0 included.
   ```json
   "%lld records" : { "extractionState" : "manual", "localizations" : {
     "en" : { "variations" : { "plural" : {
       "one" : { "stringUnit" : { "state" : "translated", "value" : "%lld record" } },
       "other" : { "stringUnit" : { "state" : "translated", "value" : "%lld records" } } } } },
     "ja" : { "stringUnit" : { "state" : "translated", "value" : "%lld 回の記録" } } } }
   ```

3. **`extractionState: "manual"` is mandatory.** The compiler extracts `"%lld records"` knowing
   `count: Int`, so the runtime works — but the source-based extract has no type info and marks the
   key `stale` on **every** `scripts/xcodebuild.sh build`; `manual` opts it out.

**Coverage is blind to the en plural**: `check_localization_coverage.py` reads
`localizations.en.stringUnit`, which a plural block has not, so it early-returns without checking
`one` / `other`. Confirm both by hand; pin them in `Localization/RecordsCountPluralTests.swift`.

## SwiftUI convenience-init label trap

Convenience-init labels (`Stepper`, `Toggle`, `Picker`, `Slider`, `Section`) take
`LocalizedStringKey`, so a literal containing `\(...)` makes the **runtime-interpolated string** the
lookup key: extract writes `"Chance: %@"`, the runtime looks up `"Chance: 0.5"` — catalog miss,
English fallback, even on `ja`.

```swift
// ✗ runtime "Chance: 0.5" misses the catalog
Stepper("Chance: \(formattedProb)", value: $prob, in: 0...1)
// ✓ label closure + String(format:)
Stepper(value: $prob, in: 0...1) {
  Text(String(format: String(localized: "Chance: %@"), formattedProb))
}
```

### Why Tier 1 / Tier 2 don't catch this

Tier 1 treats the literal as covered (it is inside a `LocalizedStringKey` callsite); Tier 2 sees
the format template, not the runtime key. Grep:

```
rg '(Stepper|Toggle|Picker|Slider|Section)\("[^"]*\\\(' --type swift
```

## A custom func's `LocalizedStringKey` parameter is not extracted

Each shape for a helper's text parameter trades one silent failure for another:

- `title: LocalizedStringKey` with a bare literal at the callsite — the source-based extract cannot
  tell that literal is a key, and flips it `stale` every build.
- the same plus `extractionState: "manual"` survives, but a later **rename** orphans the old key and
  leaves the new one absent — coverage cannot fail on a key that isn't there.

**Apply**: prefer `title: String` with `String(localized:)` at every callsite, contract in the doc
comment. See `SettingsView+Feedback.swift`.

## `#if DEBUG` strings are not auto-extracted to the catalog

A `String(localized: "…")` inside `#if DEBUG` never reaches the catalog: the wrapper extracts and
syncs before the build emits the `.stringsdata`, and extract does not traverse the branch.
Coverage then **passes** — no key to fail on — yet a `ja` device falls back to English. Add it
**manually** (canonical alphabetical position, ` : ` separators), build once, and confirm sync
keeps it.

## Audit triage — `.accessibilityLabel` candidates

Two checks at plan time, before wrap-vs-skip:

1. **Grep the callsites first** — extension-property getters sit far from their application site
   and read as Preview-only. `rg '<propertyName>' --type swift`, looking for
   `.accessibilityLabel(<propertyName>)`.

2. **Evaluate the semantic.** When the string is an **identifier** (color slot, role, layout slot)
   rather than a translatable label, the fix is `.accessibilityHidden(true)` or another a11y
   descriptor — a wrap commits wrong semantics to translators and worsens VoiceOver dissonance.
   See `SheepAvatar.swift`.
