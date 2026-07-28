---
paths:
  - "Pastura/Pastura/Views/**"
  - "Pastura/Pastura/App/**"
  - "Pastura/Pastura/PasturaApp.swift"
---

# Navigation Rules

## Scope — why the `paths:` globs are what they are

`PasturaApp.swift` is listed **separately and is not optional**. It is the only
top-level Swift file under `Pastura/Pastura/`, so neither directory glob reaches
it, and four invariants this file states live nowhere else: `TabCoordinator()`
(`:124`, its sole construction in the app target), the "deliberately not
`.environment(router)`" comment (`:274`) that encodes the collapse-all-tabs trap
below, the `tryDrain` deep-link drain (`:484`), and the any-tab
`isSimulationOnTop` fold (`:460`–`:463`, ending in `// D5.4: any-tab — do not
narrow`). `scripts/generate-navigation-map.py`'s `SCAN_DIRS` covers only
`Views` and `App`, so the drift gate does **not** backstop it — this rule text is
its only guard.

The directory entries use the bare `**` form rather than `**/*.swift` because
`App/` holds 68 direct-child `.swift` files (`AppRouter.swift` among them) and
`Views/` holds 5: a `**/` that binds ≥1 path segment would silently drop every
one. `App/**` reaches direct children under either globstar reading, and
`Views/`+`App/` contain no non-Swift files, so the suffix would buy nothing.

**Accepted gaps**: a session that reaches a matching file only via Bash or
`Grep` — never a `Read` — does not load this rule; and test files fall outside,
including `ScreenshotTourTests.swift`, which is a nav-map input. The nav-map
pre-commit / CI drift gate backstops the latter.

## The model

The app's root is a **four-tab bottom bar** (`RootTabView`, inside
`WindowGroup`; ADR-016). Each tab owns its **own** `NavigationStack`
whose `path` is owned by a per-tab `AppRouter` — four instances held by
`TabCoordinator`, a per-scene `@Observable @MainActor` class. Each tab's
stack injects its router via `.environment` **inside** the tab's
`NavigationStack` subtree (`TabNavigationStack`), so an ambient
`@Environment(AppRouter.self)` read resolves to the router of the tab the
view lives in. All deep navigation within a tab goes through `Route`
cases resolved by the shared `RouteResolver` (registered on every tab's
`navigationDestination(for: Route.self)`).

Generated screen-graph overview:
[`docs/design/navigation-map.md`](../../docs/design/navigation-map.md)
(CI drift-guarded — regenerate via the script, never edit by hand).

Regenerate in the **same commit** as any `Route` add/remove/rename,
`NavigationLink(value:)` / `router.push` edge change, or callsite **file move**:
`python3 scripts/generate-navigation-map.py` then `--self-test` then `--check`,
staging both the map and the script. Both the pre-commit
`navigation-map-precommit-gate.sh` and the CI "Navigation map drift guard" run
`--check`, but the pre-commit gate is **trigger-scoped** — it fires only when the
staged diff touches a nav-map input (`Views`/`App` `.swift`,
`ScreenshotTourTests.swift`, the generator, or the map), so drift staged without
one is caught only by CI. A callsite file move fires the guard even when the
generated map is **byte-identical**: the script attributes each callsite to a
screen via `FILE_TO_SCREEN`, so a moved `NavigationLink(value: Route.X)` fails
with "navigation callsite found but file is not in FILE_TO_SCREEN" — fix by
adding the new path to `FILE_TO_SCREEN`.

## Bottom-tab IA — `TabCoordinator` (load-bearing)

The four-tab model (ADR-016) replaced the single root `NavigationStack`.
Key invariants:

- **`TabCoordinator` owns four *unmodified* `AppRouter` instances**
  (home / search / history / settings) plus `selectedTab`. `AppRouter`
  is never widened into a multi-path container — every existing guard
  (`pushIfOnTop` / `popToRoot` / `path.last`) stays correct **locally
  inside each tab**.
- **Native `TabView`, never hand-rolled** (`RootTabView`). Per-tab
  router injection happens inside `TabNavigationStack`'s `NavigationStack`
  subtree — injecting one router above the `TabView` would collapse all
  four tabs onto one stack.
- **Deep-link drain → さがす (Search) tab.** A resolved
  `.galleryScenarioDetail` is a Search-tab destination, so
  `TabCoordinator.presentDeepLinkedGalleryScenario(_:)` selects the
  Search tab and **plain-`push`**es onto `searchRouter` — *not*
  `pushIfOnTop`. The `await` that `pushIfOnTop` guards already completed
  upstream in `PasturaApp.tryDrain`, and the freshly-selected tab root is
  normally an empty stack where the guard would no-op.
- **Tab re-select → that tab's `popToRoot()`.** SwiftUI's native
  auto-pop-to-root on re-tapping the active tab does **not** fire for a
  `NavigationStack(path:)` bound to an explicit `[Route]` array — the
  native bar supplies only the *gesture surface* (the selection
  `Binding`'s setter runs on re-tap); the path reset is performed
  manually by `TabCoordinator.handleSelection(_:)`.
- **`isSimulationOnTop` is an any-tab fold.** A `.simulation` /
  `.resumeSimulation` route on top of **any** tab's stack gates the
  deep-link drain and suppresses the warm splash. Load-bearing on multi-tab
  *hosting* (a sim can top any tab's stack) + scenePhase-background
  (ADR-003), **not** on tab-switching — do not narrow to the selected tab
  (ADR-016 § Amendment 2026-06-18).
- **Simulation focus mode (#646).** While a sim is on top, the tab bar is
  hidden (`.toolbar(.hidden, for: .tabBar)` on `SimulationView`), so
  tab-switching mid-run is structurally impossible; the only exits are back
  / swipe-back (confirm-on-leave `.back` arm + `.paused` safety net). The
  PR #673 tab-switch defer machinery (`hasUnsavedInFlightRun` /
  `pendingTabSwitch`) was removed — do not re-add it. ADR-017.
- **Phase B opt-in cross-screen continuation (#682, ADR-017 § Amendment
  2026-06-20).** With `FeatureFlags.keepRunningOnLeaveEnabled` on (default
  off), leaving the sim **parks** the run in memory instead of ending it
  (`SimulationView.disappearAction` → `session.requestPark(.viewHide)`); the
  `.paused` safety net is the Setting-off path. While parked-away the
  `InFlightSimulationIndicator` (mounted on the `RootTabView` overlay, shown
  when `isActive && !isSimulationOnTop`) re-surfaces the run via
  `TabCoordinator.returnToRunningSimulation(tab:route:)` — a plain `push`
  (the sim route was popped on leave), guarded against a duplicate when
  already on top. This re-consumes the `isSimulationOnTop` fold — do not
  delete it.
- **Contextual bottom action bar on ScenarioDetail (#856, ADR-016 § Amendment
  2026-07-01).** `ScenarioDetailView` and `ScenarioEditorView` hide the tab bar
  (`.toolbar(.hidden, for: .tabBar)`) and replace it with a contextual bottom
  action bar (`ScenarioDetailActionBar` in a `.safeAreaInset`: Run /
  Edit·Template / Delete, tab-bar-style icon-over-label) — tab-switching to
  other sections isn't a real use case from a scenario detail / editor. Same
  **API** as focus mode (#646) for the hide but a **different rationale**
  (contextual actions, not run-protection): `isSimulationOnTop` and the
  focus-mode machinery are untouched. Editor hides its own tab bar so its state
  is consistent regardless of entry (ScenarioDetail vs Home "new scenario").
  The bar applies `glassEffect` (iOS 26+) so it reads as a continuation of the
  native tab bar it replaces; the glass rendering + the `InFlightSimulationIndicator`
  pill's clearance against it are real-device QA gates. Bar items are tap-driven
  `NavigationLink`s (a custom bar, not a native `.bottomBar` — the latter is
  icon-only on iOS 26).

## When to use what

| Pattern | Use for |
|---------|---------|
| `NavigationLink(value: Route.X) { label }` | **Tap-driven** push (user taps the row/button to navigate). |
| `router.push(.X)` | **Programmatic** push from synchronous code. The ambient `@Environment(AppRouter.self)` is the **current tab's** router, so this pushes onto the tab the view lives in. |
| `router.pushIfOnTop(expected:next:)` | **Programmatic push after `await`** — guards against pushing onto an unrelated screen if the user popped back during the suspension. |
| `router.pop()` / `router.popToRoot()` | Programmatic back / unwind **within the current tab's stack**. |
| `PasturaBackButton()` | Custom back chevron for views pushed onto a **tab's** `NavigationStack`. Wraps `router.pop()`. Use with `.navigationBarBackButtonHidden(true)` + `.preservesPasturaSwipeBackGesture()`. See "Custom back button" section below. |
| `@Environment(\.dismiss)` | Dismissing a sheet / modal that is **not** part of a tab's stack. |

## Forbidden inside a tab's stack

`navigationDestination(item:)` and `navigationDestination(isPresented:)` MUST
NOT be added to any view that gets pushed onto a tab's stack (i.e. any
destination resolved by the shared `RouteResolver`). Mixing them with the
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
        ScenarioDetailView(scenarioId: token.id)   // ⚠️ mixed with the Route registry
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

## Custom back button — `PasturaBackButton`

Every view pushed onto a tab's `NavigationStack` MUST replace the
system back chevron with `PasturaBackButton()` to opt out of iOS 26's
automatic Liquid Glass capsule styling. The pair of modifiers is
load-bearing — omitting either breaks behavior:

```swift
.navigationBarBackButtonHidden(true)        // hide system back BUTTON
.preservesPasturaSwipeBackGesture()         // re-enable swipe-back gesture
.toolbar {
  ToolbarItem(placement: .topBarLeading) { PasturaBackButton() }
  // ... other action items in the SAME toolbar { } block ...
}
```

**Why `.preservesPasturaSwipeBackGesture()` is required**: on iOS 26,
`.navigationBarBackButtonHidden(true)` ALSO disables the
`UINavigationController.interactivePopGestureRecognizer` (verified by
`BackGestureTests` regressing without the modifier). The modifier
mounts an invisible `UIViewControllerRepresentable` probe at the view
level (NOT inside the `ToolbarItem` — toolbar slots constrain size
enough that `.background()` doesn't render the representable) which
walks to the host `UINavigationController` and reinstalls the gesture
with a delegate gating on `viewControllers.count > 1` — preserving
swipe-back on pushed views without re-enabling pop on a tab root.

**Scope**: a tab's NavigationStack push only. Sheet / fullScreenCover
content has its own dismiss path — use `@Environment(\.dismiss)`
directly. `PasturaBackButton` calls `router.pop()` which mutates the
current tab's `AppRouter.path` and does NOT dismiss sheets.

**Accepted accessibility regression**: System back announces
`"Back, button, <upstream view title>"`; `PasturaBackButton` announces
only `"Back, button"`. The chevron-only design intentionally drops
the contextual upstream title for visual quietude (design-system §1).
QA scenario 2 in `docs/qa/navigation-qa.md` documents the new
VoiceOver expectation.

**Action item button styling**: pair `PasturaToolbarButtonStyle`
(`.primary` / `.destructive` / `.secondary` variants) with toolbar
action buttons to opt out of the Liquid Glass capsule that iOS 26
auto-applies based on `ToolbarItemPlacement`. See
`docs/design/design-system.md` § 5.8 for variant → token mapping.

**Title display mode (`.large` / `.inline`)**: which pushed screen uses
a large vs inline navigation title is a design-system convention, not a
routing concern — see `docs/design/design-system.md`
§ "Navigation title display mode". This rule governs only the back
button / toolbar chrome.

## Sheets, popovers, fullScreenCover — out of scope

Each tab's `AppRouter` manages **that tab's `NavigationStack` only**.
Sheet / popover / fullScreenCover content has its own navigation context
and may freely use `navigationDestination(item:)`,
`navigationDestination(isPresented:)`, or its own internal
`NavigationStack`. The existing `PhaseEditorSheet`, `PersonaEditorSheet`,
`ScoreboardSheet`, and `ModelDownloadView` are sheet-owned stacks and are
unaffected by this rule.

## AppRouter scope (load-bearing)

`AppRouter` holds **only** the navigation path. Do not add:

- selection state (use local `@State`) — **tab selection lives on
  `TabCoordinator.selectedTab`**, never on `AppRouter`; this split is
  the whole reason `TabCoordinator` owns the routers rather than widening
  `AppRouter` (ADR-016 D3).
- modal presentation flags (use local `@State` with `.sheet(item:)`)
- search queries / form state (use local `@State` or a feature ViewModel)
- network in-flight flags (use local `@State` or a ViewModel)

If you find yourself wanting to add a property to `AppRouter`, ask whether
the state is genuinely "where in the navigation tree are we?" — if not, it
belongs elsewhere.

## PR review checklist

When reviewing changes that touch navigation:

- [ ] No new `navigationDestination(item:|isPresented:)` inside views pushed
      onto any tab's stack. Sheet-owned NavigationStacks are fine.
- [ ] Programmatic pushes from `await` callsites use `pushIfOnTop` rather
      than raw `push` (unless the call cannot be reached after the originating
      view is popped, OR the target tab root is freshly selected and empty —
      the deep-link drain's plain `push`, see "Bottom-tab IA").
- [ ] No direct mutation of `router.path` outside `AppRouter` itself. The
      per-tab routers are driven by `TabCoordinator` via method calls
      (`push` / `popToRoot`), not direct `path` mutation, so the grep below
      stays clean. Reads (`.count` / `.last` / `.isEmpty`) are fine:
      `rg 'router\.path\s*(=[^=]|\.append|\.removeLast|\.removeAll|\.insert|\.remove\b)' Pastura --glob '!**/AppRouter*'`
      should be empty.
- [ ] No new properties on `AppRouter` beyond navigation-path management
      (tab selection → `TabCoordinator`).
- [ ] Focus mode intact (#646): `SimulationView` keeps
      `.toolbar(.hidden, for: .tabBar)`, and no tab-switch defer state is
      re-introduced on `TabCoordinator` (`hasUnsavedInFlightRun` /
      `pendingTabSwitch` were removed). `isSimulationOnTop` stays an any-tab
      fold (ADR-016 § Amendment 2026-06-18).
- [ ] `Route` add/remove/rename, `NavigationLink`/`router.push` edge change, or
      callsite **file move** regenerated `docs/design/navigation-map.md` in the
      same commit (`generate-navigation-map.py --check`; new callsite file also
      added to `FILE_TO_SCREEN`).

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
- [ ] If the case adds `RouteHint`, the shared `RouteResolver` extracts
      `.value` to pass to the destination view.
- [ ] If a callsite pushes with a hint, the source-of-truth for the
      hint value is documented (e.g. gallery curation invariant —
      see `GallerySeedYAMLTests.galleryTitleMatchesYAMLName`).

Decision record: [ADR-008](../../docs/decisions/ADR-008.md). Type
definition + standalone tests:
[`RouteHint.swift`](../../Pastura/Pastura/App/RouteHint.swift),
[`RouteHintTests.swift`](../../Pastura/PasturaTests/App/RouteHintTests.swift).

## QA scenarios

Moved to [`docs/qa/navigation-qa.md`](../../docs/qa/navigation-qa.md)
(numbering preserved — external "QA scenario N" references resolve
there). Run them whenever the navigation surface
changes in areas the automated tests do not exercise.
