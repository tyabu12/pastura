---
paths:
  - "Pastura/Pastura/Views/**"
  - "Pastura/Pastura/App/**"
  - "Pastura/Pastura/PasturaApp.swift"
---

# Navigation Rules

## The model

Each of the four bottom tabs owns its own `NavigationStack`, whose `path` is owned by a per-tab `AppRouter` held by `TabCoordinator`; the router is injected **inside** the tab's stack subtree, so an ambient `@Environment(AppRouter.self)` read resolves to the router of the tab the view lives in. All deep navigation goes through `Route` cases resolved by the shared `RouteResolver`. The bar is a native `TabView`, never hand-rolled — injecting one router **above** the `TabView` collapses all four tabs onto one stack — and the deep-link drain pushes with plain `push`, not `pushIfOnTop`, by design. Decisions: ADR-016 (bottom-tab IA), ADR-017 (focus mode), ADR-008 (route identity).

Screen graph: [`docs/design/navigation-map.md`](../../docs/design/navigation-map.md) — generated, never hand-edited. Regenerate it in the **same commit** as any `Route` add/remove/rename, `NavigationLink(value:)` / `router.push` edge change, or callsite file move, and stage both. The pre-commit gate fires only when the staged diff touches a nav-map input, so drift staged without one reaches CI alone.

## When to use what

| Pattern | Use for |
|---------|---------|
| `NavigationLink(value: Route.X) { label }` | Tap-driven push. |
| `router.push(.X)` | Programmatic push from synchronous code, onto the current tab's stack. |
| `router.pushIfOnTop(expected:next:)` | Programmatic push **after `await`** — guards against pushing onto an unrelated screen if the user popped back during the suspension. |
| `router.pop()` / `router.popToRoot()` | Programmatic back / unwind within the current tab's stack. |
| `PasturaBackButton()` | Custom back chevron for views pushed onto a tab's stack. Wraps `router.pop()`, falling back to `dismiss()` when the environment carries no router. |
| `@Environment(\.dismiss)` | Dismissing a sheet / modal that is **not** part of a tab's stack. |

## Forbidden inside a tab's stack

`navigationDestination(item:)` and `navigationDestination(isPresented:)` MUST NOT be added to any view pushed onto a tab's stack (any destination resolved by the shared `RouteResolver`). Mixing them with the Route-based registry makes the two destination scopes fight, and pushed views silently re-render or fail to advance instead of pushing the next screen. Use `router.push` / `router.pushIfOnTop` instead. Reference: `Views/Community/SharedScenarios/GalleryScenarioDetailView.swift`.

## Custom back button — `PasturaBackButton`

Every view pushed onto a tab's `NavigationStack` MUST use `PasturaBackButton()` together with **both** `.navigationBarBackButtonHidden(true)` and `.preservesPasturaSwipeBackGesture()` — omitting either breaks silently (no back affordance, or no swipe-back on iOS 26).

Callsite template, the reason the pairing is load-bearing, toolbar action-button styling, and the title display-mode convention: `docs/design/design-system.md` § 5.8.1 / § 5.8.2 / § 5.11.

**Its router is read as an optional `@Environment(AppRouter.self)`, and must stay optional.** iOS 26 can size a toolbar item from inside the push transition (`UIKitBarItemHost.initializeSize()` via `BarAppearanceBridge.didMoveToWindow`), reaching the item's environment read before `TabNavigationStack`'s `.environment(router)` propagates to that separate view graph; the non-optional form then trips the `EnvironmentValues.subscript` assertion and terminates the app (TestFlight 1.3 (888) / iOS 26.6, #1683 — one report, never reproduced). Nothing in the build or the test suite catches a regression here: ADR-009 rules out render tests, and the failure needs a real push transition. The nil arm logs and calls `dismiss()` rather than returning silently, so a router that never arrives shows up in the log instead of as a dead back button.

## Sheets, popovers, fullScreenCover — out of scope

A tab's `AppRouter` manages **that tab's `NavigationStack` only**. Sheet / popover / fullScreenCover content has its own navigation context and may freely use `navigationDestination(item:)`, `navigationDestination(isPresented:)`, or its own `NavigationStack` — the rule above does not reach it.

## AppRouter scope (load-bearing)

`AppRouter` holds **only** the navigation path. Selection state, modal presentation flags, search queries / form state, and network in-flight flags all belong in local `@State` or a feature ViewModel. **Tab selection lives on `TabCoordinator.selectedTab`**, never on `AppRouter`; that split is why `TabCoordinator` owns four routers rather than `AppRouter` being widened.

## Render-time hints — `RouteHint`

A `Route` field that affects **display only** (a title placeholder shown synchronously at push time, an animation parameter) must be wrapped in `RouteHint<T>` so the auto-synthesized `Hashable` keeps using identity-bearing fields alone. A plain `String?` hint makes `.scenarioDetail("x")` and `.scenarioDetail("x", "Foo")` compare unequal and **silently breaks `pushIfOnTop` guards** that callers write without the hint.

`RouteHint`'s `==` is always `true` and `hash(into:)` a no-op, so identity is preserved — which is load-bearing in the other direction too: never treat two hints as `.value`-interchangeable; read `.value` from the instance you hold. Reference: `App/RouteHint.swift`.

## QA scenarios

Moved to [`docs/qa/navigation-qa.md`](../../docs/qa/navigation-qa.md) — numbering preserved, so external "QA scenario N" references resolve there.
