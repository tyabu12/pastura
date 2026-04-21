# Navigation Rules

The root `NavigationStack` lives in `RootView` (inside `WindowGroup`) and its
`path` is owned by `AppRouter` — a per-scene `@Observable @MainActor` class
injected via `@Environment(AppRouter.self)`. All deep navigation off the root
goes through `Route` cases resolved by HomeView's
`navigationDestination(for: Route.self)`.

## When to use what

| Pattern | Use for |
|---------|---------|
| `NavigationLink(value: Route.X) { label }` | **Tap-driven** push (user taps the row/button to navigate). |
| `router.push(.X)` | **Programmatic** push from synchronous code (button action, callback). |
| `router.pushIfOnTop(expected:next:)` | **Programmatic push after `await`** — guards against pushing onto an unrelated screen if the user popped back during the suspension. |
| `router.pop()` / `router.popToRoot()` | Programmatic back / unwind. |
| `@Environment(\.dismiss)` | Dismissing a sheet / modal that is **not** part of the root stack. |

## Forbidden inside the root stack

`navigationDestination(item:)` and `navigationDestination(isPresented:)` MUST
NOT be added to any view that gets pushed onto the root stack (i.e. any
destination in `HomeView.routeDestination(_:)`). Mixing them with the
Route-based destination registry causes the two destination scopes to fight,
and pushed views silently re-render or fail to advance.

The exact bug that motivated this rule: `GalleryScenarioDetailView` once used
`navigationDestination(item: $installedToken)` to push the installed
`ScenarioDetailView` after `tryInstall`. Tapping **Run Simulation** from that
pushed view would re-render `ScenarioDetailView` instead of advancing to
`SimulationView`.

### ❌ Negative example (do not do this)

```swift
struct GalleryScenarioDetailView: View {
  @State private var installedToken: InstalledToken?

  var body: some View {
    Content()
      .navigationDestination(item: $installedToken) { token in
        ScenarioDetailView(scenarioId: token.id)   // ⚠️ mixed with root's Route registry
      }
  }
}
```

### ✅ Positive example

```swift
struct GalleryScenarioDetailView: View {
  @Environment(AppRouter.self) private var router

  private func handleInstallSuccess(scenarioId: String) {
    router.pushIfOnTop(
      expected: .galleryScenarioDetail(scenario: scenario),
      next: .scenarioDetail(scenarioId: scenarioId))
  }
}
```

## Sheets, popovers, fullScreenCover — out of scope

`AppRouter` manages the **root NavigationStack only**. Sheet / popover /
fullScreenCover content has its own navigation context and may freely use
`navigationDestination(item:)`, `navigationDestination(isPresented:)`, or
its own internal `NavigationStack`. The existing `PhaseEditorSheet`,
`PersonaEditorSheet`, `ScoreboardSheet`, and `ModelDownloadView` are
sheet-owned stacks and are unaffected by this rule.

## AppRouter scope (load-bearing)

`AppRouter` holds **only** the navigation path. Do not add:

- selection state (use local `@State`)
- modal presentation flags (use local `@State` with `.sheet(item:)`)
- search queries / form state (use local `@State` or a feature ViewModel)
- network in-flight flags (use local `@State` or a ViewModel)

If you find yourself wanting to add a property to `AppRouter`, ask whether
the state is genuinely "where in the navigation tree are we?" — if not, it
belongs elsewhere.

## PR review checklist

When reviewing changes that touch navigation:

- [ ] No new `navigationDestination(item:|isPresented:)` inside views pushed
      onto the root stack. Sheet-owned NavigationStacks are fine.
- [ ] Programmatic pushes from `await` callsites use `pushIfOnTop` rather
      than raw `push` (unless the call cannot be reached after the originating
      view is popped).
- [ ] No direct mutation of `router.path` outside `AppRouter` itself.
      Grep (mutation patterns only — `.count` / `.last` / `.isEmpty` reads
      are fine):
      `rg 'router\.path\s*(=[^=]|\.append|\.removeLast|\.removeAll|\.insert|\.remove\b)' Pastura --glob '!**/AppRouter*'`
      should be empty.
- [ ] No new properties on `AppRouter` beyond navigation-path management.

## Manual QA scenarios (no UI test target yet)

Run these whenever the navigation surface changes:

1. **Share Board → Try → Run Simulation** — From Home, tap Share Board, pick a
   gallery scenario, tap **Try this scenario**, wait for install, then tap
   **Run Simulation** on the pushed scenario detail. Expected: SimulationView
   appears. Regression symptom: ScenarioDetailView re-pushes itself.
2. **Back gesture from any depth** — Swipe back from each of:
   ScenarioDetail, Editor, Import, Simulation, Results, GalleryScenarioDetail.
   Expected: each pop returns one screen, not all the way to root.
3. **Editor save → return to Home** — From Home, open New Scenario, save,
   confirm Home reloads with the new scenario showing (the
   `onChange(of: router.path.count)` reload trigger). Note: the trigger
   only fires when `newCount < oldCount` (a pop). Flows that finish by
   pushing forward — e.g. editor save then push to the new scenario's
   detail — bypass this reload; if such a flow is added, surface the
   write through the ViewModel rather than relying on the pop-trigger.
4. **Swipe-back during Try** — Tap Try, immediately swipe back to dismiss
   `GalleryScenarioDetailView` while the install is still running. Expected:
   install completes in the background, the gallery's `pushIfOnTop` guard
   sees the view is no longer on top, and no spurious push to
   `ScenarioDetailView` occurs. (Backgrounding the app does **not** pop
   views, so it does not exercise this guard.)
5. **Conditional phase — nested sub-phase editor + sub-phase drag** —
   In the scenario editor, add a `conditional` phase, tap it to open
   `PhaseEditorSheet`, enter a condition, tap **Add sub-phase** inside
   the Then branch. Expected: a nested `PhaseEditorSheet` presents with
   the `conditional` option *absent* from the type picker (depth-1 UI
   enforcement). Change the sub-phase type, save, return to the outer
   editor. Save the outer phase and confirm the top-level scenario list
   shows the condition summary with `then:N else:M` counts. The nested
   sheet is sheet-owned, so its own NavigationStack is fine — this QA
   just confirms that the presentation chain (outer sheet → inner
   sheet) dismisses cleanly without leaking `.conditional` into nested
   depths.

   Drag UX — add 2–3 sub-phases to each branch, then verify all of:
   - **Within-branch reorder** — long-press the drag handle of any
     sub-phase and drag up/down within the same branch. Expected:
     top-edge insertion line appears under the hovered row, release
     completes the move.
   - **Cross-branch drag** — drag a sub-phase from Then into Else (or
     vice versa). Expected: Else rows highlight the insertion line as
     the drag enters, release inserts the sub-phase into the target
     branch at the hovered index.
   - **Drop into empty branch** — delete all Else sub-phases so the
     branch shows the dashed "No sub-phases yet" placeholder, then
     drag a Then sub-phase into the placeholder. Expected: placeholder
     text switches to "Drop here" on hover, release inserts into Else.
   - **Tap-to-edit + swipe-to-delete still work** — tap the content
     area of any row → opens nested editor. Swipe left on any row →
     reveals Delete action. These must coexist with drag without
     gesture swallowing.
   - **Context menu move actions** — long-press the content area (not
     the handle) of any sub-phase. Expected: "Move Up", "Move Down",
     "Move to Then/Else Branch" options. Boundary items are disabled
     (no Move Up on first row, no Move Down on last row).
   - **Depth-2 nested sheets have no branches** — the nested sheet
     opened by editing a sub-phase does not contain Then/Else sections
     (since `.conditional` is filtered out), so this drag feature does
     not apply at that depth. Confirm no drag affordances appear.

6. **Top-level phase list — drag reorder + context menu** — In the
   scenario editor at the top level, add 3+ phases to a scenario.
   Verify:
   - **Drag handle reorder** — long-press the `line.3.horizontal`
     handle on any row and drag to reorder. Expected: top-edge
     insertion line under the hovered row, release completes the move.
     Tap-to-edit (on the content area) and swipe-to-delete must still
     work.
   - **Context menu** — long-press the content area (not the handle)
     of any phase. Expected: "Move Up" / "Move Down" actions with
     boundary items disabled.
   - **Empty list drop target renders** — remove all phases so the
     dashed "No phases yet" placeholder appears, then add a phase via
     the Add Phase button and confirm the list repopulates. The empty
     placeholder also serves as a drop target, but since sub-phases
     and top-level phases are never on screen together, cross-surface
     drag is blocked by construction (distinct `Transferable` payload
     types); no interactive test is needed.
