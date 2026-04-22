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

## QA scenarios

`PasturaUITests` covers scenarios 1 and 3 end-to-end and scenario 2 on
its primary route. Run the manual steps below whenever the navigation
surface changes in areas the automated tests do not exercise.

1. **Share Board → Try → Run Simulation** — Automated by
   `NavigationRegressionTests.testGalleryInstallThenRunSimulationReachesSimulationView`
   (PR #105). Regression symptom: ScenarioDetailView re-pushes itself.
   Re-run the manual flow only if the `--ui-test` DI path diverges from
   production (e.g., gallery install side effects that depend on a real
   network).
2. **Back gesture** — `BackGestureTests` covers the Home → ScenarioDetail
   route automatically. Manually verify the remaining routes still pop
   exactly one screen (not all the way to root): Editor, Import,
   Simulation, Results, GalleryScenarioDetail.
3. **Editor save → Home reload** — `EditorReloadTests` covers the
   `onChange(of: router.path.count)` pop-trigger path. Note: the trigger
   only fires when `newCount < oldCount` (a pop). Flows that finish by
   pushing forward — e.g. editor save then push to the new scenario's
   detail — bypass this reload; if such a flow is added, surface the
   write through the ViewModel rather than relying on the pop-trigger,
   and extend `EditorReloadTests` (or add a sibling) to cover it.
4. **Swipe-back during Try** — Tap Try, immediately swipe back to dismiss
   `GalleryScenarioDetailView` while the install is still running. Expected:
   install completes in the background, the gallery's `pushIfOnTop` guard
   sees the view is no longer on top, and no spurious push to
   `ScenarioDetailView` occurs. (Backgrounding the app does **not** pop
   views, so it does not exercise this guard.)
5. **Conditional phase — nested sub-phase editor + cross-branch move** —
   In the scenario editor, add a `conditional` phase, tap it to open
   `PhaseEditorSheet`, enter a condition, tap **Add sub-phase** inside
   the Then branch. Expected: a nested `PhaseEditorSheet` presents with
   the `conditional` option *absent* from the type picker (depth-1 UI
   enforcement). Change the sub-phase type, save, return to the outer
   editor. Save the outer phase and confirm the top-level scenario list
   shows the condition summary with `then:N else:M` counts. The nested
   sheet is sheet-owned, so its own NavigationStack is fine — this QA
   just confirms that the presentation chain (outer sheet → inner sheet)
   dismisses cleanly without leaking `.conditional` into nested depths.

   **Cross-branch move via context menu** — add 2 sub-phases each to
   Then and Else (so both branches are non-empty). Verify all of:
   - **Footer hint present** — each branch section shows
     "Long-press a sub-phase to move it to the other branch." under
     the last row, so the affordance is discoverable for users who
     don't already know long-press opens context menus.
   - **Context menu action** — long-press any sub-phase row. Expected:
     a single "Move to Then Branch" (for rows in Else) or "Move to Else
     Branch" (for rows in Then) menu item with the
     `arrow.left.arrow.right` icon. Tap it.
   - **Count invariants** — source branch shrinks by exactly one row,
     target branch grows by exactly one row. The moved sub-phase
     appears at the *end* of the target branch (tail-append by design;
     within-branch reordering uses the drag handle / `.onMove`).
   - **Round-trip persistence** — after moving, tap the moved row to
     open the nested `PhaseEditorSheet`, edit any field, save. Expected:
     the edit persists in the *new* branch, not the original one.
     Then save the outer phase and reopen the scenario; confirm the
     scenario-list summary shows the updated `then:N else:M` counts
     and that reloading the scenario (including YAML round-trip if
     toggling to YAML mode) preserves the branch membership.
   - **Tap-to-edit still works** — tapping (not long-pressing) a
     sub-phase row still opens the nested editor normally; the context
     menu should not steal tap gestures.
   - **Within-branch reorder still works** — the drag handle (if shown)
     or explicit edit-mode reorder via `.onMove` still works; the
     context menu should not interfere with long-press-to-drag for
     `.onMove`.
   - **Depth-2 nested sheets have no branches** — the nested
     `PhaseEditorSheet` opened by editing a sub-phase does not contain
     Then/Else sections (since `.conditional` is filtered from the
     type picker), so the footer hint and context-menu "Move to Other
     Branch" action do not appear at that depth. Confirm no spurious
     context-menu items leak into the nested sheet.
6. **Deep Link — cold start** — With Pastura fully terminated, tap a
   `pastura://scenario/<id>` link from Safari / Messages / another app.
   Expected: Pastura launches, waits for initialization + model-download
   completion (if the model isn't already resolved), then pushes the
   gallery scenario detail with a **"Opened from an external link"**
   banner at the top. Tapping **Try this scenario** installs via the
   normal flow. Invalid id (not present in the curated gallery) shows
   the **"Scenario Not Found"** alert — never an install prompt.
7. **Deep Link — initialization or model download in progress** —
   Open a `pastura://` link while `RootView` is still showing
   `ProgressView("Initializing...")` or `ModelDownloadView`. Expected:
   an **informational toast** appears at the bottom ("Opening shared
   scenario after setup…" / "Will open once the model finishes
   downloading"). Drain fires automatically when `.ready` transitions.
8. **Deep Link — during a running simulation** — Start a simulation,
   wait for generation to be in flight, then open a `pastura://` link
   from an external app. Expected: **toast** ("Will open when you exit
   this simulation"). The simulation does **not** halt. Back-swipe out
   of `SimulationView`; the deep link drain fires immediately and
   pushes the gallery detail on top of the popped stack. Running
   under BG continuation (toggle on) must not change this — the link
   still only drains once the simulation screen is no longer on top.
9. **Deep Link — during an editor / scoreboard / report sheet** —
   Open any sheet gated by `.deepLinkGated()` (phase editor, persona
   editor, scoreboard, report), then open a `pastura://` link.
   Expected: the sheet stays up with no visible toast (iOS sheets
   present in their own context and occlude the overlay). Dismiss the
   sheet — the drain fires immediately and the gallery detail pushes
   onto the underlying stack. User work in the sheet must **not** be
   discarded by the deep link arrival.
10. **Deep Link — iPad multi-window** — On iPad, open two Pastura
    windows (drag from dock), bring one to focus, then open a
    `pastura://` link from another app. Expected: only the focused
    window handles the link (iOS routes `.onOpenURL` to the active
    scene). The second window's `AppRouter` and `DeepLinkGate` remain
    untouched. Swapping focus after handling does not replay the URL.
