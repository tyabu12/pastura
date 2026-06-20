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
/// all four tabs' `pop()` onto one stack. The per-tab `TabNavigationStack`
/// content is identical across the two OS branches below — only the tab
/// *enumeration wrapper* differs.
///
/// ## Tab-reselect → pop-to-root (§2 corrected)
///
/// SwiftUI's native auto-pop-to-root on re-tapping the active tab does
/// **not** fire for a `NavigationStack(path:)` bound to an explicit
/// `[Route]` array. The native bar supplies the gesture surface (the
/// selection `Binding`'s setter runs on re-tap); the path reset is
/// performed by ``TabCoordinator/handleSelection(_:)``.
///
/// ## OS branches (iOS 18+ structural `Tab` vs iOS 17 `.tabItem`)
///
/// iOS 18+ adopts the structural `Tab` API so the さがす (Browse) tab can
/// use ``SwiftUI/TabRole/search`` — which on iOS 26 separates the tab and
/// **morphs** it into a search field (automatic from `Tab(role:.search)` +
/// the `.searchable` already on ``SharedScenariosListView``). iOS 17 keeps
/// the closure-based `.tabItem` form (`.tabItem` is deprecated on iOS 18+
/// and the new `Tab` builder cannot be mixed with `.tabItem` in one
/// `TabView`, so the whole bar is branched).
///
/// ADR-016 D1 keeps tabs **icon-only** (no text title). The structural
/// `Tab` API has no icon-only titled initializer, so the modern branch
/// uses the `label:`-closure form with a bare `Image` (no `Text`) to
/// preserve that. Whether the iOS 26 Liquid Glass *floating* bar renders
/// this cleanly icon-only is verified only on a real device (the simulator
/// mis-renders the iOS 26 bar); if it cannot, the fallback is native
/// labels (which would amend ADR-016 D1). The さがす tab uses the
/// empty-label `Tab(role:.search)` so the system supplies the search
/// affordance + morph; its VoiceOver label is the system default rather
/// than the explicit "Browse" of the other tabs (accepted, device-QA item).
///
/// `.tint(Color.moss)` tints the active tab on all supported OS.
struct RootTabView: View {
  @Bindable var coordinator: TabCoordinator

  var body: some View {
    if #available(iOS 18.0, *) {
      modernTabView
    } else {
      legacyTabView
    }
  }

  /// Shared selection binding — the same `AppTab` enum drives both
  /// branches; only the per-tab plumbing (`Tab(value:)` vs `.tag()`)
  /// differs. The setter routes through ``TabCoordinator/handleSelection(_:)``
  /// so a re-tap pops the active tab to root (§2).
  private var selectionBinding: Binding<AppTab> {
    Binding(
      get: { coordinator.selectedTab },
      set: { coordinator.handleSelection($0) }
    )
  }

  // MARK: - iOS 18+ (structural `Tab` API; iOS 26 morphs the search tab)

  @available(iOS 18.0, *)
  private var modernTabView: some View {
    TabView(selection: selectionBinding) {
      Tab(value: AppTab.home) {
        homeStack
      } label: {
        tabIcon(.home, label: String(localized: "Home"))
      }
      // さがす: `role: .search` pins this trailing on iOS 18–25 and, on
      // iOS 26, separates it + morphs the bar into a search field (driven
      // by the `.searchable` inside `SharedScenariosListView`). Empty
      // label — the search role supplies the magnifying-glass affordance.
      Tab(value: AppTab.search, role: .search) { searchStack }
      Tab(value: AppTab.history) {
        historyStack
      } label: {
        tabIcon(.history, label: String(localized: "History"))
      }
      Tab(value: AppTab.settings) {
        settingsStack
      } label: {
        tabIcon(.settings, label: String(localized: "Settings"))
      }
    }
    .tint(Color.moss)
  }

  // MARK: - iOS 17 fallback (closure-based `.tabItem`)

  private var legacyTabView: some View {
    TabView(selection: selectionBinding) {
      homeStack
        .tag(AppTab.home)
        .tabItem { tabIcon(.home, label: String(localized: "Home")) }
      searchStack
        .tag(AppTab.search)
        .tabItem { tabIcon(.search, label: String(localized: "Browse")) }
      historyStack
        .tag(AppTab.history)
        .tabItem { tabIcon(.history, label: String(localized: "History")) }
      settingsStack
        .tag(AppTab.settings)
        .tabItem { tabIcon(.settings, label: String(localized: "Settings")) }
    }
    .tint(Color.moss)
  }

  // MARK: - Shared per-tab content

  // History tab root (ADR-016 D4): `.aggregate` selects the cross-variant
  // aggregation of all past results. `Route.results` survives only as the
  // per-scenario detail push (`.scenario`) from ScenarioDetailView;
  // ``ResultsView`` drops its back chrome for this aggregate root variant.
  private var homeStack: some View {
    TabNavigationStack(router: coordinator.homeRouter) { HomeView() }
  }
  private var searchStack: some View {
    TabNavigationStack(router: coordinator.searchRouter) { SharedScenariosListView() }
  }
  private var historyStack: some View {
    TabNavigationStack(router: coordinator.historyRouter) { ResultsView(scope: .aggregate) }
  }
  private var settingsStack: some View {
    TabNavigationStack(router: coordinator.settingsRouter) { SettingsView() }
  }

  /// Icon-only tab label (ADR-016 D1) — no visible text title, so do NOT
  /// "restore" a text label; VoiceOver reads the passed `.accessibilityLabel`
  /// (the JA tab name).
  ///
  /// `.environment(\.symbolVariants, .none)` is LOAD-BEARING: since iOS 15 a
  /// `TabView` tab bar auto-applies the `.fill` variant to EVERY tab symbol,
  /// which would fill our outline (inactive) symbols too and erase the
  /// active/inactive distinction. Disabling the auto-variant lets
  /// `symbolName(for:isActive:)` drive the fill toggle explicitly. Do NOT
  /// remove it.
  private func tabIcon(_ tab: AppTab, label: String) -> some View {
    Image(systemName: Self.symbolName(for: tab, isActive: coordinator.selectedTab == tab))
      .environment(\.symbolVariants, .none)
      .accessibilityLabel(Text(label))
  }
}

extension RootTabView {
  /// SF Symbol for `tab`, swapping to the `.fill` variant when active so
  /// the selected tab reads as filled and the others as outlined.
  ///
  /// `magnifyingglass` has **no** `.fill` variant (`magnifyingglass.fill`
  /// does not exist and would render blank), so the さがす tab keeps the
  /// outline in both states and relies on the moss `.tint` alone to mark
  /// active. Pure + `internal` so the mapping is unit-tested. Drives the
  /// iOS 17 branch and the iOS 18+ non-search tabs; the iOS 18+ さがす tab
  /// uses the system search-role affordance instead.
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
