---
paths:
  - "Pastura/Pastura/App/ScenarioEditor*"
  - "Pastura/Pastura/Views/Editor/**"
  - "Pastura/PasturaTests/App/ScenarioEditorViewModel*"
---

# ScenarioEditor — Funnel Invariant

`ScenarioEditorViewModel` holds a **dual buffer**: visual fields and
`yamlText` are independent, each the source of truth for whichever mode
the user last touched. Visual edits do not normalize the user's YAML
(preserving comments, key order); YAML edits do not parse on every
keystroke. The two sides reconcile at materialization via the private
`currentScenario()` funnel. PR #336 introduced it after `save()` silently
materialized from empty visual fields when the user had only ever touched
YAML mode (`"Agent count (0)"` error).

## Invariant

Every new callsite that needs a `(Scenario, yaml)` pair from the editor —
save, export, preview, share — MUST route through `currentScenario()`.
Reading `buildScenario()` or `serializer.serialize(...)` directly bypasses
the mode dispatch and silently re-introduces the #336 drift class.

## Automated gate

`scripts/scenario-editor-funnel-gate.sh` counts `buildScenario()`
occurrences across `Pastura/Pastura/App/ScenarioEditorViewModel*.swift` and
fails when the count `!= 3` (1 private declaration + 2 sanctioned callsites
in `switchToYAMLMode()` and `currentScenario()`). It runs in the git
pre-commit hook (self-gates on the VM glob) and the CI
`scenario-editor-funnel-drift` job. Manual check:

```
grep -oF 'buildScenario()' Pastura/Pastura/App/ScenarioEditorViewModel.swift | wc -l
```

The count is a **re-evaluation trigger, not a correctness proof**:

- **> 3** — a new consumer reads visual state directly. Route it through
  `currentScenario()`, or treat it as the trigger to revisit the editor
  source-of-truth design (see #725).
- **< 3** — a sanctioned callsite was dropped; same re-evaluation gate.
- **A count of 3 with a NEW direct visual-state read** still violates the
  funnel. The Swift behavioral tripwire (`visualModeSavePreservesExtraData`
  in `ScenarioEditorViewModelTests`) is the backstop.

If the VM is ever split into `ScenarioEditorViewModel+*.swift`, revisit the
expected count in the gate.
