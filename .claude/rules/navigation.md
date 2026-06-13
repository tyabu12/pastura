# Navigation Rules

The root `NavigationStack` lives in `RootView` (inside `WindowGroup`) and its
`path` is owned by `AppRouter` — a per-scene `@Observable @MainActor` class
injected via `@Environment(AppRouter.self)`. All deep navigation off the root
goes through `Route` cases resolved by HomeView's
`navigationDestination(for: Route.self)`.

Generated screen-graph overview:
[`docs/design/navigation-map.md`](../../docs/design/navigation-map.md)
(CI drift-guarded — regenerate via the script, never edit by hand).

## When to use what

| Pattern | Use for |
|---------|---------|
| `NavigationLink(value: Route.X) { label }` | **Tap-driven** push (user taps the row/button to navigate). |
| `router.push(.X)` | **Programmatic** push from synchronous code (button action, callback). |
| `router.pushIfOnTop(expected:next:)` | **Programmatic push after `await`** — guards against pushing onto an unrelated screen if the user popped back during the suspension. |
| `router.pop()` / `router.popToRoot()` | Programmatic back / unwind. |
| `PasturaBackButton()` | Custom back chevron for **root NavigationStack** pushed views. Wraps `router.pop()`. Use with `.navigationBarBackButtonHidden(true)` + `.preservesPasturaSwipeBackGesture()`. See "Custom back button" section below. |
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

## Custom back button — `PasturaBackButton`

Every view pushed onto the root `NavigationStack` MUST replace the
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
swipe-back on pushed views without re-enabling pop on the root.

**Scope**: root NavigationStack push only. Sheet / fullScreenCover
content has its own dismiss path — use `@Environment(\.dismiss)`
directly. `PasturaBackButton` calls `router.pop()` which mutates
`AppRouter.path` and does NOT dismiss sheets.

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

Moved to [`docs/qa/navigation-qa.md`](../../docs/qa/navigation-qa.md)
(scenarios 1–17, numbering preserved — external "QA scenario N"
references resolve there). Run them whenever the navigation surface
changes in areas the automated tests do not exercise.
