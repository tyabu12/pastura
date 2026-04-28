# View Testing Strategy

Pastura's Views/ + UI test footprint is deliberately narrow. Logic that
*could* live in a View is extracted to a unit-testable target (ViewModel,
formatter, validator, computed display state); UI tests are reserved for
navigation-integration regressions. ViewInspector and snapshot-testing
libraries are not used.

## What to do

### View → unit-test (logic surface extraction)

When adding a new View, identify its **logic surface** and put that into
a unit test in `Pastura/PasturaTests/Views/`, following the existing
patterns:

| Pattern | Existing example |
|---------|------------------|
| Public init contract pin (call-site pinning) | `AgentOutputRowContractTests` |
| Pure layout / geometry helpers | `SheepAvatarTests`, `ChatBubbleTests` |
| Form validation rules | `PersonaEditorSheetValidationTests`, `PhaseEditorSheetValidationTests` |
| Display-name / label formatting | `PhaseTypeLabelTests` |
| Design token constants | `DesignTokensTests` |
| Route dispatch / ready-handoff branching | `DemoReplayHostViewTests` |

Tests instantiate the View struct directly when needed (no SwiftUI host
infrastructure), but assert against pure-logic properties / computed
values — never rendered output.

### UI test — navigation-integration boundary only

Add a UI test in `Pastura/PasturaUITests/` only when the regression
target is a navigation-integration boundary that pure logic cannot
cover. The current 3 tests model the bar:

| Test | Boundary it covers |
|------|---------------------|
| `NavigationRegressionTests` | gallery install → run-sim push, AppRouter `pushIfOnTop` guard |
| `BackGestureTests` | Home → Detail swipe-back pop-by-one |
| `EditorReloadTests` | editor save → Home `onChange(of: router.path.count)` reload trigger |

Frame-level / animation-timing bugs (e.g. overlay flash, default-value
flash, animation race) are **not** in scope for automated tests — they
fall to manual QA + code-review gatekeeping. See PR #252, #249, #150
for the cost-of-investigation pattern.

## What NOT to do

### Do not introduce ViewInspector

Concrete reasons:
- ViewInspector breaks on every Xcode major; current Xcode 26 has a
  community-fix-pending status, with several SwiftUI navigation / list
  / animation / presentation APIs already on the unsupported list.
- Tests written against the ViewInspector API leak SwiftUI internals
  (view-tree shape, modifier ordering) into the test, so changes to the
  View body force test churn even when behavior is unchanged.

### Do not introduce swift-snapshot-testing

Concrete reasons:
- Snapshot diffs are flaky across simulator GPU / renderer / iOS-version
  variation, and re-recording on each Xcode update is mandatory churn.
- Pastura already has CI time pressure (#250 / #189 — parallel-testing
  cascade); a snapshot suite adds another category of pre-merge friction
  without catching the timing-class bugs that dominate Phase 2 fix
  history.

### Do not chase 100% Views/ coverage

Phase 2 fix-commit analysis (2026-04-27 audit, 10 representative
commits): **50%** were already preventable by existing infra (Sendable
compile-time, `withObservationTracking`, ViewModel unit tests, parser
tests); **30%** are timing/animation bugs neither ViewInspector nor
snapshot testing reliably catches; **20%** are domain-logic bugs in
ViewModels that surface visibly. Adding a thick Views/ test layer would
move the frontier on roughly 0% of these categories.

CLAUDE.md "UI tests are not required for MVP" remains in effect; Phase 2
has not changed that policy.

## When to revisit

This rule should be re-evaluated if any of the following becomes true:

- Apple ships a stable, first-party SwiftUI inspection API (e.g., a
  hypothetical `View.inspect()` shipped in the standard SDK).
- The frame/timing bug ratio (category (b) above) climbs above 50% over
  3+ consecutive months — this would shift the cost/benefit math toward
  snapshot testing despite its flakiness.
- A specific high-value flow becomes too complex for ViewModel-level
  testing alone (e.g., a user-visible regression that was fundamentally
  unreachable from the VM layer).

## Cross-references

- `navigation.md` — the QA scenarios list naming what manual coverage
  remains for the routes UI tests don't exercise.
- `testing.md` — overall testing priority order
  (JSONResponseParser → ScenarioLoader → TemplateExpander → PhaseHandlers
  → ScoreCalcHandler) and `MockLLMService` deterministic-test pattern.
- `docs/decisions/ADR-001.md` — Architecture Overview; the layer
  diagram explains why most testable logic lives in Engine / App below
  the View boundary.
