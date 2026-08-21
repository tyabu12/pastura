---
paths:
  - "Pastura/PasturaTests/**"
  - "Pastura/PasturaUITests/**"
  - "Pastura/Pastura/Views/**"
  - "Pastura/Pastura/App/**ViewModel.swift"
---

# View Testing Strategy

Decision record: [ADR-009](../../docs/decisions/ADR-009.md). Operational rule below.

## Rule

1. **Extract View logic to unit tests** in `Pastura/PasturaTests/Views/`, asserting pure-logic properties, never rendered output.
2. **UI tests for the navigation-integration boundary only**, when the target cannot be reached from pure logic.
3. **Do NOT introduce ViewInspector or swift-snapshot-testing.**
4. **Frame / animation-timing bugs are out of scope**; defer to manual QA and code review.

## Change-detector tripwire for code-review-gated tokens

Extract a code-review-gated surface's load-bearing constants into a named enum and pin each value in a unit test. A failure is not a bug — the token drifted, usually in an unrelated refactor — so confirm the change passed review, then update the expectation; say so in the test's doc comment.

`Equatable` is necessary but **not sufficient**. `SwiftUI.Font` / `AnyTransition` are not `Equatable` at all — leave those inline and code-review-gate them. `Color` is, yet a `PasturaDynamicColor`-backed alias compares by **provider instance**, so an assertion that two tokens *differ* passes vacuously and can never fire whenever either side is paired (two *fixed* aliases do compare by value). Pin *which token* a consumer reads (`style.fillToken == Color.moss`); leave *what value* to `DesignTokensTests`. Fixed-appearance exception: `swiftui-traps.md` § "`ImageRenderer` does not inherit the ambient environment".

**Extracting inline colours into accessors so a pin can read them leaves the pin blind to `body`** — two places now decide the colour, and a `body` that re-inlines a token diverges while the accessor pin stays green. Snapshots are ruled out, so keep `body` free of `Color.` references and the divergence is a grep. Reference: `PredictionOutcomeBadgeTokenTests`.

## Non-base-locale expectations

`locale:` in `String(localized:bundle:locale:)` selects the plural / format **rule** only — the `.lproj` table follows the process's localization, so a `ja` pin against the app bundle silently returns the `en` value and asserts nothing about ja.

Three working shapes: pin the locale the **runner already resolves to** (`RecordsCountPluralTests`); assert other locales against the catalog JSON as a change detector (`StoreCaptureTabLabelTests`); or scope the bundle to the table itself. **Both** layers of that last one are optional (`path(forResource:)` is `String?` *and* `Bundle(path:)` is failable), so unwrap twice — `#require` over `!` for a located failure, not because Hard Rule 1 applies (test code is exempt):

```swift
let jaPath = try #require(appBundle.path(forResource: "ja", ofType: "lproj"))
let jaBundle = try #require(Bundle(path: jaPath))
#expect(String(localized: "History", bundle: jaBundle) == "観察履歴")
```
