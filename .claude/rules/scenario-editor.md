---
paths:
  - "Pastura/Pastura/App/ScenarioEditor*"
  - "Pastura/Pastura/Views/Editor/**"
  - "Pastura/PasturaTests/App/ScenarioEditorViewModel*"
---

# ScenarioEditor — Funnel Invariant

`ScenarioEditorViewModel` holds a **dual buffer**: visual fields and `yamlText` are independent, each authoritative for whichever mode the user last touched. They reconcile only at materialization, in the private `currentScenario()` funnel ([ADR-018](../../docs/decisions/ADR-018.md)).

## Invariant

Every callsite needing a `(Scenario, yaml)` pair from the editor — save, export, preview, share — MUST route through `currentScenario()`. Reading `buildScenario()` or `serializer.serialize(...)` directly bypasses the mode dispatch and silently re-introduces the drift class: materializing from empty visual fields when the user only ever touched YAML mode.

## What the funnel gate does not cover

`scripts/scenario-editor-funnel-gate.sh` counts `buildScenario()` occurrences, so a count of exactly 3 with a sanctioned callsite swapped for a **new** direct visual-state read still passes; `ScenarioEditorViewModelTests.visualModeSavePreservesExtraData` is the behavioural backstop. If the VM is split into `ScenarioEditorViewModel+*.swift`, revisit the expected count.
