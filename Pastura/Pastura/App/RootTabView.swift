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
      // Icon-only tabs across ALL supported OS (ADR-016 D1 / design "D3"
      // mock) — intentionally no visible text title, so do NOT "restore"
      // `Label(text:)`. VoiceOver reads the per-icon `.accessibilityLabel`
      // (the JA tab name); its correct surfacing on the tab button is
      // confirmed by the real-device QA this PR already requires.
      //
      // `.environment(\.symbolVariants, .none)` on each icon is
      // LOAD-BEARING: since iOS 15 a `TabView` tab bar auto-applies the
      // `.fill` variant to EVERY tab symbol, which would fill our outline
      // (inactive) symbols too and erase the active/inactive distinction.
      // Disabling the auto-variant lets `symbolName(for:isActive:)` drive
      // the fill toggle explicitly. Do NOT remove it.
      TabNavigationStack(router: coordinator.homeRouter) {
        HomeView()
      }
      .tag(AppTab.home)
      .tabItem {
        Image(systemName: Self.symbolName(for: .home, isActive: coordinator.selectedTab == .home))
          .environment(\.symbolVariants, .none)
          .accessibilityLabel(Text(String(localized: "Home")))
      }

      TabNavigationStack(router: coordinator.searchRouter) {
        SharedScenariosListView()
      }
      .tag(AppTab.search)
      .tabItem {
        Image(
          systemName: Self.symbolName(for: .search, isActive: coordinator.selectedTab == .search)
        )
        .environment(\.symbolVariants, .none)
        .accessibilityLabel(Text(String(localized: "Browse")))
      }

      TabNavigationStack(router: coordinator.historyRouter) {
        // History tab root (ADR-016 D4): empty scenarioId selects the
        // cross-variant aggregation of all past results. `Route.results`
        // survives only as the per-scenario detail push (non-empty
        // scenarioId) from ScenarioDetailView; ``ResultsView`` drops its
        // back chrome for this empty-id root variant.
        ResultsView(scenarioId: "")
      }
      .tag(AppTab.history)
      .tabItem {
        Image(
          systemName: Self.symbolName(for: .history, isActive: coordinator.selectedTab == .history)
        )
        .environment(\.symbolVariants, .none)
        .accessibilityLabel(Text(String(localized: "History")))
      }

      TabNavigationStack(router: coordinator.settingsRouter) {
        SettingsView()
      }
      .tag(AppTab.settings)
      .tabItem {
        Image(
          systemName: Self.symbolName(
            for: .settings, isActive: coordinator.selectedTab == .settings)
        )
        .environment(\.symbolVariants, .none)
        .accessibilityLabel(Text(String(localized: "Settings")))
      }
    }
    .tint(Color.moss)
  }
}

extension RootTabView {
  /// SF Symbol for `tab`, swapping to the `.fill` variant when active so
  /// the selected tab reads as filled and the others as outlined.
  ///
  /// `magnifyingglass` has **no** `.fill` variant (`magnifyingglass.fill`
  /// does not exist and would render blank), so the さがす tab keeps the
  /// outline in both states and relies on the moss `.tint` alone to mark
  /// active. Pure + `internal` so the mapping is unit-tested.
  static func symbolName(for tab: AppTab, isActive: Bool) -> String {
    switch tab {
    case .home: return isActive ? "house.fill" : "house"
    case .search: return "magnifyingglass"
    case .history: return isActive ? "clock.fill" : "clock"
    case .settings: return isActive ? "gearshape.fill" : "gearshape"
    }
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
    // (the `@Bindable` shadow pattern documented on ``AppRouter``).
    // `.environment(router)` scopes this tab's router to its own
    // subtree (D3).
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
