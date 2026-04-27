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

## Render-time hints — `RouteHint`

Some `Route` cases need to carry **render-time hints** (e.g.
`initialName: String?` for the navigation title to show
synchronously at push time, before the destination view's async load
completes). Such hints are NOT navigation identity — they affect
display only. Wrap them in `RouteHint<T>`
(`Pastura/Pastura/App/RouteHint.swift`) so the auto-synthesized
`Hashable` on `Route` continues to use only identity-bearing fields:

```swift
case scenarioDetail(
  scenarioId: String,
  initialName: RouteHint<String> = .init()
)
```

Why this matters: a plain `String?` hint would make
`.scenarioDetail("x")` (default-nil) and
`.scenarioDetail("x", "Foo")` compare unequal, silently breaking
`pushIfOnTop` guards that callers naturally write without the hint.
`RouteHint`'s `==` is always `true` and `hash(into:)` is a no-op,
so identity is preserved on `scenarioId` alone.

⚠️ `RouteHint`'s identity-neutrality is **load-bearing**. Do NOT
treat `RouteHint("Foo") == RouteHint("Bar")` as `.value`
interchangeability — always read `.value` from the specific instance
you hold. The type's header doc-comment carries this warning.

When reviewing a new `Route` case:

- [ ] Identity-bearing fields (e.g. ids) are plain associated values.
- [ ] Render-time-only fields (placeholders, animation params) are
      wrapped in `RouteHint<T>`.
- [ ] If the case adds `RouteHint`, the destination resolver in
      `HomeView.routeDestination(_:)` extracts `.value` to pass to
      the destination view.
- [ ] If a callsite pushes with a hint, the source-of-truth for the
      hint value is documented (e.g. gallery curation invariant —
      see `GallerySeedYAMLTests.galleryTitleMatchesYAMLName`).

Decision record: [ADR-008](../../docs/decisions/ADR-008.md). Type
definition + standalone tests:
[`RouteHint.swift`](../../Pastura/Pastura/App/RouteHint.swift),
[`RouteHintTests.swift`](../../Pastura/PasturaTests/App/RouteHintTests.swift).

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
7. **Deep Link — before the app is `.ready`** — Open a `pastura://`
   link while `RootView` is still in any non-`.ready` state:
   `ProgressView("Initializing...")`, `ModelPickerView`
   (`.needsModelSelection` — fresh multi-model install), or
   `ModelDownloadView` (`.needsModelDownload`). Expected: an
   **informational toast** appears at the bottom, with the copy
   matching the current state:

   - `.initializing` → "Opening shared scenario after setup…"
   - `.needsModelSelection` → "Will open after you choose a model"
   - `.needsModelDownload` → "Will open once the model finishes
     downloading"

   Drain fires automatically when `.ready` transitions. The
   `.needsModelSelection` → `.needsModelDownload` hop (user taps a
   row) must keep the pending URL queued — the toast copy updates to
   the download message, and the drain still only fires on `.ready`.
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
11. **Multi-model picker — fresh install on supported device** —
    Install Pastura on a supported device (≥ 8 GB RAM) with no prior
    install and no seeded UserDefaults. Expected: after the splash,
    `ModelPickerView` shows instead of `ModelDownloadView`. Two rows
    appear (Gemma 4 E2B and Qwen 3 4B), each surfacing vendor +
    decimal GB size, with a moss-accented "Start with this model"
    button. Tap Qwen's button; app transitions to
    `ModelDownloadView` and starts downloading Qwen, not Gemma.
    Legacy Gemma TestFlight users (existing Gemma file on disk) must
    **not** see the picker on upgrade — they route through
    `.needsModelDownload` → `.ready` as before.
12. **Multi-model Settings — switch active model (simulation idle)** —
    On a device with both models downloaded, open **Settings →
    Models**. Expected: the active model shows an "Active" badge;
    the other shows "Ready" with a menu containing **Use this
    model** and **Delete**. Tap the ellipsis, choose **Use this
    model**. Expected: Active badge moves, UserDefaults is updated
    (verify by re-launching the app — the newly-selected model
    stays active), and the next simulation runs on the new model.
    No visible in-flight spinner — the swap is instant in the UI;
    the actual model load happens at the next `run()` call.
13. **Multi-model Settings — switch disabled during simulation** —
    Start a simulation, navigate to **Settings → Models** while
    generation is in flight. Expected: the section **footer** copy
    changes to "Finish the current simulation before switching
    models…". On the non-active `.ready` row, tap the ellipsis —
    the **Use this model** action is **disabled** (grayed), while
    **Delete** remains enabled. Deleting the non-active model
    succeeds and does not disturb the running simulation (the
    running LLM service keeps its own file reference).
14. **Multi-model Settings — delete the only `.ready` model** —
    On a device with one model downloaded and the other not,
    open **Settings → Models** and try to delete the active model.
    Expected: the active row's menu does **not** offer a Delete
    action at all (it's gated by `isActive == false`). To delete,
    the user must first **Use this model** on a different
    descriptor — but that requires the other model to be
    downloaded. The only recovery flow from "I have only one model
    and want to delete it" is: download the other model → switch
    active → delete the first. QA covers: after this sequence,
    re-launch the app and confirm it lands on the newly-active
    descriptor without re-prompting the picker.
15. **Multi-model Settings — delete confirmation dialog** — On a
    `.ready` non-active row, tap **Delete** from the menu. Expected:
    a confirmation dialog titled "Delete `<displayName>`?" with a
    message showing the re-download cost ("Re-downloading `<size>`
    takes a few minutes.") and two buttons: **Delete** (destructive
    red) and **Cancel**. Cancel dismisses without side effects.
    Delete removes the file (verify via re-launch — state returns
    to `.notDownloaded`) and the row's menu flips to showing
    **Download** instead.
16. **Multi-model Settings — Download triggers DL demo cover** —
    On a `.notDownloaded` row, tap **Download** from the menu.
    Expected: a full-screen modal cover slides up presenting the
    DL-time demo experience (`ModelDownloadHostView`) for that
    descriptor — the same UX as the first-launch
    `.needsModelDownload` slot. Verify all of:
    - **Cover content tracks the tapped descriptor** — `PromoCard`
      progress bar / percent / size strings must reflect the row
      the user tapped, not the active model. (Easy to mistake when
      Gemma is active and the user taps Qwen's Download row.)
    - **Cellular consent gate** — toggle Airplane Mode off +
      cellular on (no prior consent), then tap **Download**.
      Expected: cover does **NOT** present; instead the
      scene-level confirmation dialog appears (see scenario 17).
      Tap **Download anyway** → cover presents and demo replay
      plays on cellular. Tap **Wait for Wi-Fi** → cover never
      opens; tap **Download** again on the row to retry.
    - **Cancel button + confirmation dialog** — tap the X in the
      top-trailing corner of the cover. A `.confirmationDialog`
      appears titled "Stop downloading?" with a destructive
      "Stop and discard" button and a "Continue downloading"
      cancel button. Tapping **Continue downloading** dismisses
      only the dialog; the cover stays up and the download keeps
      progressing. Tapping **Stop and discard** dismisses the
      cover, removes both the partial `.download` file and any
      finalized model file (defensive double-delete), and resets
      `state[descriptor.id]` to `.notDownloaded`. The Settings
      row reflects this within ~one frame.
    - **DL completion auto-dismisses** — let the download finish.
      Expected: the cover dismisses **without** the
      `DLCompleteOverlay` ("準備ができました / tap anywhere to
      begin"); that overlay's copy is meaningful only on the
      first-launch slot, so the Settings cover suppresses it via
      `showsCompleteOverlay: false` and dismisses on `.ready`.
      The Settings row immediately shows "Ready" and the menu
      flips to "Use this model" / "Delete".
    - **Active switch is NOT automatic** — after the cover
      dismisses, the row that finished downloading is `.ready`
      but **not** `.active`; the Active badge stays on the
      previously-active row. The user must explicitly tap
      "Use this model" to switch.
    - **Deep-link gating during cover** — open a `pastura://` URL
      from another app while the cover is up. Expected: the
      gate-blocked toast appears (cover is `.deepLinkGated()`),
      not a navigation push under the cover. Dismiss the cover
      (cancel or completion); the deep link drains afterward.
    - **App kill mid-download → Settings re-tap resumes** —
      while the cover is up and progress is partway, kill the app
      from the multitasking switcher. Re-launch, return to
      **Settings → Models**, tap **Download** again on the same
      row. The cover re-presents and the download resumes from
      the partial file (verify by progress jumping past 0% on
      first paint — `performDownload` reads the resume offset
      from the `.download` file size). Crash-recovery is **not**
      the same path as Cancel — Cancel deletes the partial,
      crash leaves it intact.
    - **Sequential-DL guard** — start a download from row A, let
      it run, then attempt to tap Download on row B. Expected:
      the **menu's** Download item on row B is disabled
      (`otherDownloadInProgress` — covers both `.downloading`
      state on any other row AND `pendingCellularConsent != nil`
      for any other row, see scenario 17). It cannot be
      triggered, so no second cover appears. (If the disabled
      state ever regresses, the cover's tap handler also
      re-checks `state[descriptor.id] == .downloading`
      post-`startDownload` as defense-in-depth and bails
      silently if the policy rejected the call.)

17. **Cellular consent dialog (#191 / ADR-007 §3.3 (c))** —
    `ModelManager.startDownload` gates on cellular network +
    no prior consent at every entry point. Verify the
    scene-level `.confirmationDialog` presents and behaves
    correctly across all paths:

    - **Picker tap on cellular (fresh install)** — pick a model;
      gate fires → dialog appears with "Download on cellular?"
      title, "Download anyway" (destructive) / "Wait for Wi-Fi"
      (cancel) buttons. State stays `.notDownloaded`; the
      `ModelDownloadHostView` underneath shows the **Wi-Fi
      advisory** (Wi-Fi recommended" + "Try Again" button)
      instead of demo replay. Tap **Download anyway** → consent
      persists in UserDefaults (`com.pastura.hasCellularDownloadConsent`),
      `startDownload` re-fires, state flips `.downloading`, demo
      replay starts. Tap **Wait for Wi-Fi** → state stays
      `.notDownloaded`, Wi-Fi advisory remains, dialog dismisses;
      tap "Try Again" to re-present the dialog.

    - **Relaunch on cellular without consent** — terminate the
      app mid-download (or before any DL), re-launch on cellular.
      Expected: `initialize()` hits the `.notDownloaded` branch,
      dialog presents identically to the picker path. No bytes
      flow until the user accepts.

    - **Relaunch on cellular WITH consent already granted** —
      after a prior accept, terminate and re-launch on cellular.
      Expected: dialog does **NOT** present; auto-resume proceeds
      directly into demo replay.

    - **Settings → Download on cellular** — open Settings →
      Models on cellular (no consent), tap **Download** on a
      `.notDownloaded` row. Expected: cover does **NOT** open
      immediately; dialog presents at scene level instead. Tap
      **Download anyway** → state goes `.downloading`, cover
      opens via the `.onChange(of: modelManager.state)` observer.
      Tap **Wait for Wi-Fi** → cover never opens; user stays on
      the Settings list.

    - **PromoCard "Retry" after error on cellular** — once a
      download is mid-flight (after consent), simulate a network
      drop (Airplane Mode → off again on cellular). State goes
      `.error`, PromoCard shows inline retry. Tap **Retry**.
      With consent already granted (this session), the retry
      proceeds without re-prompting. To test the gate-on-retry
      path: clear consent (UserDefaults → reset key) and retry —
      the dialog presents.

    - **Tap-outside dismiss = decline** — on iPad / large iPhone
      where dialog has tappable margin, tap outside the dialog
      area. Expected: same as **Wait for Wi-Fi** — `pendingCellularConsent`
      clears, state stays `.notDownloaded`. (Wired through the
      synthesized `Binding<Bool>` set closure; without that
      wiring the gate would silently leak `pendingCellularConsent`
      non-nil after iOS auto-closed the dialog.)

    - **Multi-row tap during pending dialog** — on Settings on
      cellular (no consent), tap **Download** on row A → dialog
      appears. Without dismissing, tap **Download** on row B
      from the menu. Expected: row B's Download menu item is
      **disabled** (`otherDownloadInProgress` covers
      `pendingCellularConsent != nil`). The dialog continues
      to reflect row A's descriptor; row B is not affected.

    - **One-time consent persistence** — after a single accept,
      every subsequent `startDownload` (any path, any row, this
      session and future sessions) skips the dialog. Verify by
      tapping Download in Settings on a second `.notDownloaded`
      row — cover opens directly without re-prompting.
