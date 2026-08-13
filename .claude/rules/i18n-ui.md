---
paths:
  - "Pastura/Pastura/Views/**"
  - "Pastura/Pastura/App/**"
  - "Pastura/Pastura/PasturaApp.swift"
  - "Pastura/PasturaTests/Localization/**"
  - "Pastura/Pastura/Resources/Localizable.xcstrings"
---

# i18n Rules — UI layer

The UI half of the i18n rules; `i18n.md` carries the layer-independent callsite core (Form A vs Form B) and loads on **every** app-target Swift read. Both load together in a UI or catalog session, so `§` references resolve in either direction here — never from a non-UI session, which is why the core depends on nothing in this file.

## Scope

A section belongs here on **either** arm: (1) it is written against a **SwiftUI API** (`Text` plural variants, `LocalizedStringKey` labels, `.accessibilityLabel`) and so cannot fire outside a View; or (2) it is a catalog / audit procedure whose **entire known instance set** lives in `Views/` / `App/` / `PasturaApp.swift` — layer-agnostic mechanism, UI-only reach.

Everything else stays in `i18n.md`, including `### The partial-conversion trap` and `### Apply when planning a partial-scope i18n slice`: 59 `String(localized:)` uses sit outside `Views/`+`App/` (LLM 16 / Models 37 / Data 6), so non-UI slices are real — and a core→here pointer is unreachable in exactly the session that needs it. `PasturaTests/Localization/**` is an arm for the plural runtime test; `Localizable.xcstrings` is an arm because §§ Plurals and `#if DEBUG` prescribe hand-edits to the catalog, without which `i18n-catalog.md`'s opening claim would be false.

**Accepted gaps.** Arm 2 is **time-indexed**, not structural: it holds only because every `String(localized:)` strictly inside a `#if DEBUG` block sits in `Views/` today (measured 2026-08-13 — `Views/Results/ResultDetailView.swift`, 3 sites; zero in `Engine/` / `LLM/` / `Models/` / `Data/`). A future non-UI DEBUG literal hits a rule that no longer injects — re-check the arm, don't trust it. Separately, the `PasturaTests/Localization/**` arm reaches only that directory: `String(localized:)` also appears under `PasturaTests/App/` (4 files), `Views/` (3), `Models/` (2).

## Plurals — the sanctioned exception to Form B

Form B (`i18n.md` § "Format-string pattern") does **not** pluralize: the count is
substituted by `String(format:)` *after* the catalog lookup, so the lookup
never sees it and the same form renders for every count ("1 records"). A
count-aware plural needs the count to reach the localization layer, which
means **interpolation** — the one place interpolation is correct.

Three rules, all load-bearing (first plural: `"%lld records"`, UR-003):

1. **Callsite must be the SwiftUI `Text("\(count) records")` form.** The Int
   interpolation drives String-Catalog variant selection. **Not**
   `String(localized: "...\(x)...")` — the `form_a_localized_interpolation`
   SwiftLint rule (severity error) blocks it; its regex can't tell an
   Int-plural count from the Form A String-substitution hazard. **Not** Form B
   (no variant selection, see above). For non-`Text` contexts, no plural form
   is currently sanctioned — add one here when first needed.

2. **Catalog shape** (en gets `variations.plural`, ja stays single-form):
   ```json
   "%lld records" : {
     "extractionState" : "manual",
     "localizations" : {
       "en" : { "variations" : { "plural" : {
         "one"   : { "stringUnit" : { "state" : "translated", "value" : "%lld record" } },
         "other" : { "stringUnit" : { "state" : "translated", "value" : "%lld records" } }
       } } },
       "ja" : { "stringUnit" : { "state" : "translated", "value" : "%lld 回の記録" } }
     }
   }
   ```
   Japanese CLDR has only `other` — do **not** invent a `ja` plural bucket; its
   plain `stringUnit` resolves for every count. n=0 falls to en `other`.

3. **`extractionState: "manual"` is mandatory on the key.** The COMPILER
   extracts `"%lld records"` from `Text("\(count) records")` (it knows
   `count: Int` → `%lld`), so the runtime works — but the wrapper's
   source-based `xcstringstool extract` (no type info) cannot resolve the
   interpolation, so its sync marks the key `stale` on **every**
   `scripts/xcodebuild.sh build`. `manual` opts the key out of auto-sync
   staling/pruning. Without it: perpetual stale churn (and a misleading
   "drift" signal). Verify post-build with `git diff` — the key must stay
   `manual`, not flip to `stale`.

**Coverage is blind to the en plural.** `check_localization_coverage.py`'s
`_validate_source_locale` reads `localizations.en.stringUnit` directly; a plural
en block has no direct `stringUnit` (it lives under `variations.plural.*`), so it
early-returns and never checks the `one`/`other` states. Confirm both are
`"translated"` by hand / via the runtime test below.

Test it two ways (canonical:
`Pastura/PasturaTests/Localization/RecordsCountPluralTests.swift`):

- **Structure** — a catalog-JSON change-detector (read the xcstrings via
  `#filePath`) guards the `variations.plural` blocks + the `manual` flag from a
  future sync flattening them.
- **Runtime firing** — the actual regression (n=1 → "1 records"). Resolve the key
  against the COMPILED catalog and assert literals:
  `String(localized: "\(1) records", bundle: Bundle(for: <AppClass>.self), locale: Locale(identifier: "en")) == "1 record"`.
  Naming the **app** bundle explicitly (`Bundle(for:)`) keeps it
  non-tautological — the target is app-hosted, so `Bundle.main` resolves to the
  same bundle, but relying on that is implicit. Pure
  Foundation resolution is ADR-009-compatible (no ViewInspector). `String(localized:
  "…\(x)…")` is fine in **test** code — the `form_a_localized_interpolation`
  SwiftLint rule scopes to app source only. **The `en` pin works because the
  runner's process localization resolves to `en`** (`Bundle.preferredLocalizations`),
  not because `en` is the source language — `locale:` picks the plural rule, not
  the `.lproj` table. Read `view-testing.md` § "Non-base-locale expectations"
  before asserting a `ja` value at runtime.

Device / ja-locale QA is still worth a glance, but the runtime test — not manual
QA — is the load-bearing firing signal.

## SwiftUI convenience-init label trap

SwiftUI convenience-init labels (`Stepper`, `Toggle`, `Picker`, `Slider`,
`Section`, etc.) accept `LocalizedStringKey`, not `String`. When the Swift
literal contains `\(...)` interpolation, the **entire runtime-interpolated
string** becomes the catalog lookup key. xcstringstool extracts the format
template (`"Chance: %@"`) at compile time, but at runtime the lookup key
is the literal value (`"Chance: 0.5"`) — catalog miss → English fallback,
even when locale is `ja`.

```swift
// ✗ Silent fallback on ja locale — runtime "Chance: 0.5" misses catalog
Stepper("Chance: \(formattedProb)", value: $prob, in: 0...1)

// ✓ Label-closure form + canonical String(format:) call
Stepper(value: $prob, in: 0...1) {
  Text(String(format: String(localized: "Chance: %@"), formattedProb))
}
```

Same pattern for `Toggle("...\(x)...", isOn:)`, `Picker("...\(x)...",
selection:)`, etc. Switch to the explicit label-closure overload and
format the string through the canonical `String(format: String(localized:))`
path documented in `i18n.md` § "Format-string pattern". Same observable
symptom as that file's § "Form A is a runtime hazard at user-facing callsites"
— both produce silent English fallback from a `\(…)`-interpolated literal —
but from a `LocalizedStringKey` literal rather than a `String(localized:)` one.

### Why Tier 1 / Tier 2 don't catch this

- **Tier 1 SwiftLint tripwire**: the literal is technically already inside
  a "localization-aware" callsite (`Stepper`'s `LocalizedStringKey` overload),
  so the heuristic-based unwrapped-string detector treats it as covered.
- **Tier 2 audit (`scripts/check_i18n_potential_keys.py`)**: may or may
  not surface depending on how Swift extracts the format string from the
  `LocalizedStringKey` initializer. Tier 2 empirically missed multiple
  instances — see PR #423 for the case-study triage.

### Detection grep

```
rg '(Stepper|Toggle|Picker|Slider|Section)\("[^"]*\\\(' --type swift
```

Run before any i18n slice that touches Editor / Settings / Form-heavy
surfaces.

## A custom func's `LocalizedStringKey` parameter is not extracted

Factoring a repeated row/label into a helper raises the question of how to type
its text parameter. There is no free answer — each shape trades one silent
failure for another:

| Helper signature | Caller | Extraction | Residual risk |
|---|---|---|---|
| `title: String` + `Text(title)` | `String(localized: "Rate Pastura")` | ✅ auto-tracked | a future caller passing a **raw literal** leaks silently — Tier 1 + Tier 2 are both blind (§ "Why Tier 1 / Tier 2 don't catch this") |
| `title: LocalizedStringKey` | `"Rate Pastura"` | ❌ key flips to `stale` on **every** `scripts/xcodebuild.sh build` | — |
| `title: LocalizedStringKey` **+ `extractionState: "manual"`** | `"Rate Pastura"` | ✅ survives (opted out of auto-sync) | a later **rename** of the literal leaves the old key orphaned and the new one absent — and coverage cannot fail on a key that isn't there (same blind spot as § "`#if DEBUG` strings are not auto-extracted to the catalog") |

Why row 2 fails: `scripts/xcodebuild.sh build` runs a **source-based**
`xcstringstool extract` with no type information, so it cannot tell that a bare
literal at a *custom* function's callsite is a localizable key. It sees the
literals disappear and marks them `stale`. (Distinct from § "SwiftUI
convenience-init label trap", which is about SwiftUI's *own* `LocalizedStringKey`
initializers and interpolation — this one has no interpolation and still fails.)

Row 3 is the § "Plurals — the sanctioned exception to Form B" rule-3 escape hatch applied here, and it works. Both
rows measured 2026-07-27 on `SettingsView.externalLinkRow`: switching the
parameter flipped `"Privacy Policy"` and `"Rate Pastura"` to
`"extractionState" : "stale"`; adding `manual` held them across two consecutive
builds with `check_localization_coverage.py` green.

**Apply**: prefer row 1 — keep `String`, keep `String(localized:)` at every
callsite, and put the contract in the helper's doc comment. Row 1's failure
needs a future contributor to add a caller *and* ignore that contract; row 3's
fires on an ordinary copy rename, silently, on keys that already ship. Reach for
row 3 once a helper has enough callers that a doc comment stops being a credible
gate. Canonical: `SettingsView+Feedback.swift` `externalLinkRow`.

## `#if DEBUG` strings are not auto-extracted to the catalog

**Distinct root cause from `i18n.md` § "Form A is a runtime hazard at user-facing callsites"**: there the key
exists in the catalog but the runtime-substitution form misses it; here the key
**never enters the catalog at all**. A new `String(localized: "…")` inside a
`#if DEBUG` block is NOT added to `Localizable.xcstrings` by
`scripts/xcodebuild.sh build`'s auto-sync — even on a second build. The wrapper
runs `xcstringstool extract` + `sync` *before* the xcodebuild that emits the
`.stringsdata`, and extract does not traverse the `#if DEBUG` branch reliably, so
the key stays absent. `check_localization_coverage.py` then **passes** — the key
simply isn't present to fail on — yet on a ja device the string falls back to the
English literal (same observable symptom as Form A, different cause).

**Fix:** add the key to the catalog **manually** (Apple-canonical alphabetical
position, ` : ` separators), build once, and confirm sync **keeps** it (a used key
in the Debug `.stringsdata` is retained). Don't rely on auto-sync for `#if DEBUG`
user-facing strings.

## Audit triage — `.accessibilityLabel` candidates

For i18n Tier 2 audit candidates whose target is `.accessibilityLabel(...)`, run two checks before deciding wrap-vs-skip:

1. **Grep callsites first.** Extension-property getters (`var accessibilityLabel: String { ... }`) sit far from their application site — easy to misclassify as Preview-only when the getter is in a sibling extension and the application is in a `body` 100+ lines away.

   ```
   rg '<propertyName>' --type swift
   ```

   Look for `.accessibilityLabel(<propertyName>)` form.

2. **Evaluate semantic before wrapping.** When the candidate string is an **identifier** (color slot, role, layout slot) rather than a translatable label, the right fix is `.accessibilityHidden(true)` (decorative) or a different a11y descriptor — NOT wrap with `String(localized:)`. Wrapping commits wrong semantics to translators and may amplify a pre-existing VoiceOver dissonance (en label already misleading; ja makes it worse).

Apply during initial plan drafting, not at critic time — saves a Critical-verdict re-revision cycle.

Canonical case study: `Pastura/Pastura/Views/Components/SheepAvatar.swift` `Character.accessibilityLabel` returned color-slot canonical names ("Alice"/"Bob"/"Carol"/"Dave"), not agent display names. Wrapping with ja would have committed those as translatable personal names and amplified the VoiceOver dissonance for ja-locale users. Fix: `.accessibilityHidden(true)` (avatar is decorative; adjacent `Text(agent)` carries identity).

## Audit planning — three checks before drafting a Tier 2 wrap PR

Run these against a Tier 2 candidate list (`scripts/check_i18n_potential_keys.py`) **before** planning catalog edits — each is otherwise a late Critical the pre-impl critic catches only at review time.

1. **Existing key ⇒ zero new catalog entries.** The audit groups by `(file, line, key)` and flags every wrap-site; xcstringstool dedupes by the literal string alone. Wrapping a literal that already exists in `Localizable.xcstrings` (from a prior wrap elsewhere) creates **no** new key — grep the catalog for the exact string first and drop it from the plan's "new keys" count. Don't pre-plan a `ja` translation; the existing one is reused.

2. **Does the wrap canonicalize a structural bug?** A `String(format:)` literal may hardcode an assumption that should be data-derived (a model size, a count, a unit suffix, a vendor name). Wrapping verbatim freezes that bug into the catalog as the translator source-of-truth, so the later fix costs a Swift edit **plus** a catalog rename **plus** every `ja` update. Scan the literal; if it hardcodes such a value, either parameterize it in the same PR (preferred) or skip the wrap and file a follow-up bundling the wrap with the structural fix.

3. **Intentional deferral needs a documented home.** The audit is stateless — it re-flags the same candidate every run. When a candidate is deliberately left un-wrapped pending a gating event (design-pending copy, deferred multi-model fix), an inline `// TODO` is invisible to the next audit session. Register the deferral as a row in `docs/i18n/leak-detection.md` § "Explicitly-deferred or permanent carve-outs" (source location, gating event, expected resolution), and point the inline comment at that section.
