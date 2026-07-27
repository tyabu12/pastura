---
paths:
  - "Pastura/PasturaTests/**"
  - "Pastura/PasturaUITests/**"
  - "Pastura/Pastura/Views/**"
  - "Pastura/Pastura/App/**ViewModel.swift"
---

# View Testing Strategy

Decision record: [ADR-009](../../docs/decisions/ADR-009.md). Operational
rule below.

## Rule

1. **Extract View logic to unit-tests.** When adding a new View,
   identify its logic surface (validation rules, formatting, computed
   display state) and put that into a unit test in
   `Pastura/PasturaTests/Views/` following the existing patterns
   (`AgentOutputRowContractTests`, `PersonaEditorSheetValidationTests`,
   `DesignTokensTests`, etc.). Assert against pure-logic properties,
   never rendered output.

2. **UI tests for the navigation-integration boundary only.** Add to
   `Pastura/PasturaUITests/` only when the regression target cannot be
   reached from pure logic. The existing 3 model the bar:
   `NavigationRegressionTests`, `BackGestureTests`, `EditorReloadTests`.
   (`ScreenshotTourTests` is a review-only capture tour — ADR-009
   decision 5, CI-skipped — and does not count against this bar.)

3. **Do NOT introduce ViewInspector or swift-snapshot-testing.** Both
   add third-party-library risk (Xcode-major refresh cadence) and CI
   flakiness without catching the timing-class bugs that dominate
   Phase 2 fix history. Full rationale in ADR-009.

4. **Frame / animation-timing bugs are not in scope** for automated
   tests. Defer to manual QA + code-review gatekeeping. PRs #252, #249,
   #150 are case-study patterns.

## Change-detector tripwire for code-review-gated tokens

When a visual / timing surface is code-review-gated only (rule 4) and has
no manual trigger to *see* it, extract its load-bearing layout / timing
constants into a named enum and add a **change-detector** unit test that
asserts each value. A failure is NOT a bug — it means a code-review-gated
token drifted (typically in an unrelated refactor) and the editor must
confirm the change passed review, then update the expected value. This
narrows the silent-drift regression window without rendering the View, so
rule 3 (no ViewInspector / snapshot) still holds. Frame the intent in the
test's doc-comment, or the next contributor will (fairly) delete it as
tautological.

Only `Equatable` constants qualify: `SwiftUI.Font` / `AnyTransition` are
not `Equatable`, so leave those inline and code-review-gate them. Canonical
example: `LanguageDriftToastLayout` + `LanguageDriftToastLayoutTests` (the
`.languageMismatch` drift toast; #456 / ADR-009 § Amendment 2026-06-23).

Full Why + alternatives + revisit triggers:
[ADR-009](../../docs/decisions/ADR-009.md).

## Non-base-locale expectations

`locale:` in `String(localized:bundle:locale:)` selects the plural / format
**rule** only — the `.lproj` table follows the *process's* localization
(`Bundle.preferredLocalizations`). So a `ja` pin against the app bundle
silently returns the `en` value, and a guard built on one asserts nothing
about ja. Probed 2026-07-27 on the simulator test runner: `locale: ja` on
`"%lld records"` → `1 records`, i.e. ja's `other`-only rule applied to the
**en** table (`ja.lproj` ships; it is simply not selected).

Three working shapes: pin the **base** locale at runtime
(`RecordsCountPluralTests`); assert non-base values against the catalog JSON
— the change-detector shape above (`StoreCaptureTabLabelTests`); or, for a
real runtime resolution, scope the bundle to the table —
`Bundle(path: appBundle.path(forResource: "ja", ofType: "lproj"))`, which
does return `観察履歴`.
