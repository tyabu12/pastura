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

## PR review grep

```
rg 'buildScenario\(\)' Pastura/Pastura/App/ScenarioEditorViewModel.swift
```

Should return **exactly 3 hits** (callsites from `switchToYAMLMode()` and
`currentScenario()`, plus the `private func buildScenario()` declaration).
Hit-count assertion — line numbers drift on any insertion. **>3** means a
new consumer is reading visual state directly: either route through
`currentScenario()`, or treat it as a named re-evaluation trigger for #338
(the source-of-truth shift was deliberately deferred). **<3** means a
sanctioned callsite was dropped — same re-evaluation gate applies.

## Related

- PR #336 — drift bug fixed via the funnel
- Issue #338 — deferred source-of-truth refactor; this rule is the safety net
