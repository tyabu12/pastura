import SwiftUI

/// The app's root four-tab bottom bar (ADR-016 D1 / D2 / D3).
///
/// Native `TabView` — **never** hand-rolled (D2). Each tab owns its own
/// `NavigationStack` driven by the matching `AppRouter` from
/// ``TabCoordinator`` (D3), and every stack registers the shared
/// ``RouteResolver`` so a push resolves identically from any tab.
///
/// ## Per-tab router injection (D3, load-bearing)
///
/// Each tab's `AppRouter` is injected via `.environment` **inside** that
/// tab's `NavigationStack` subtree (see ``TabNavigationStack``), never
/// above the `TabView`. So an ambient `@Environment(AppRouter.self)` read
/// — HomeView's pop-reload, `PasturaBackButton`, `ResultDetailView`'s
/// post-delete pop — resolves to the router of the tab the view actually
/// lives in. Injecting a single router above the `TabView` would collapse
/// all four tabs' `pop()` onto one stack.
///
/// ## Tab-reselect → pop-to-root (§2 corrected)
///
/// SwiftUI's native auto-pop-to-root on re-tapping the active tab does
/// **not** fire for a `NavigationStack(path:)` bound to an explicit
/// `[Route]` array. The native bar supplies the gesture surface (the
/// selection `Binding`'s setter runs on re-tap); the path reset is
/// performed by ``TabCoordinator/handleSelection(_:)``.
///
/// ## OS styling
///
/// `.tint(Color.moss)` tints the active tab on all supported OS. On
/// iOS 26 the native floating Liquid Glass tab bar renders automatically
/// (no opt-in); OS-specific treatments (search-role morphing) are
/// deferred to P4. Real-device QA on both iOS 17–25 and iOS 26 is
/// required — the simulator mis-renders the iOS 26 bar.
struct RootTabView: View {
  @Bindable var coordinator: TabCoordinator

  var body: some View {
    TabView(
      selection: Binding(
        get: { coordinator.selectedTab },
        set: { coordinator.handleSelection($0) }
      )
    ) {
      TabNavigationStack(router: coordinator.homeRouter) {
        HomeView()
      }
      .tag(AppTab.home)
      .tabItem {
        Image(systemName: "house")
          .accessibilityLabel(Text(String(localized: "Home")))
      }

      TabNavigationStack(router: coordinator.searchRouter) {
        SharedScenariosListView()
      }
      .tag(AppTab.search)
      .tabItem {
        Image(systemName: "magnifyingglass")
          .accessibilityLabel(Text(String(localized: "Browse")))
      }

      TabNavigationStack(router: coordinator.historyRouter) {
        // Home-entry semantic (cross-variant aggregation): empty
        // scenarioId. Becomes the History tab root (ADR-016 D4); its
        // `Route.results` case split lands in a later sub-PR.
        ResultsView(scenarioId: "")
      }
      .tag(AppTab.history)
      .tabItem {
        Image(systemName: "clock")
          .accessibilityLabel(Text(String(localized: "History")))
      }

      TabNavigationStack(router: coordinator.settingsRouter) {
        SettingsView()
      }
      .tag(AppTab.settings)
      .tabItem {
        Image(systemName: "gearshape")
          .accessibilityLabel(Text(String(localized: "Settings")))
      }
    }
    .tint(Color.moss)
  }
}

/// One tab's navigation stack: the tab's `AppRouter`-driven
/// `NavigationStack` + the shared ``RouteResolver`` + per-tab router
/// injection. Factored out so the four tabs share identical wiring.
private struct TabNavigationStack<Root: View>: View {
  let router: AppRouter
  @ViewBuilder let root: () -> Root

  var body: some View {
    // Local `@Bindable` rebinding to derive `$router.path` for the stack
    // (mirrors the established HomeView pattern). `.environment(router)`
    // scopes this tab's router to its own subtree (D3).
    @Bindable var router = router
    return NavigationStack(path: $router.path) {
      root()
        .navigationDestination(for: Route.self) { route in
          RouteResolver(route: route)
        }
    }
    .environment(router)
  }
}
