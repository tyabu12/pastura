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

3. **Do NOT introduce ViewInspector or swift-snapshot-testing.** Both
   add third-party-library risk (Xcode-major refresh cadence) and CI
   flakiness without catching the timing-class bugs that dominate
   Phase 2 fix history. Full rationale in ADR-009.

4. **Frame / animation-timing bugs are not in scope** for automated
   tests. Defer to manual QA + code-review gatekeeping. PRs #252, #249,
   #150 are case-study patterns.

Full Why + alternatives + revisit triggers:
[ADR-009](../../docs/decisions/ADR-009.md).
