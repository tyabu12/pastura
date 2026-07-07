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
/// all four tabs' `pop()` onto one stack. Each tab wraps its
/// `TabNavigationStack` in a structural `Tab`.
///
/// ## Tab-reselect → pop-to-root (§2 corrected)
///
/// SwiftUI's native auto-pop-to-root on re-tapping the active tab does
/// **not** fire for a `NavigationStack(path:)` bound to an explicit
/// `[Route]` array. The native bar supplies the gesture surface (the
/// selection `Binding`'s setter runs on re-tap); the path reset is
/// performed by ``TabCoordinator/handleSelection(_:)``.
///
/// ## Structural `Tab` API
///
/// The bar uses the structural `Tab` API (iOS 18+; the minimum deployment
/// target per ADR-019). It replaced `.tabItem` (deprecated on iOS 18+) and
/// keeps the iOS 26 search-role morph re-enableable behind a one-line
/// `role:` change — though that morph is currently **deferred** (see the
/// さがす-tab note below).
///
/// ADR-016 D1 keeps tabs **icon-only** (no text title). The structural
/// `Tab` API has no icon-only titled initializer, so each tab uses the
/// `label:`-closure form with a bare `Image` (no `Text`) to preserve that.
/// Whether the iOS 26 Liquid Glass *floating* bar renders this cleanly
/// icon-only is verified only on a real device (the simulator mis-renders
/// the iOS 26 bar); if it cannot, the fallback is native labels (which
/// would amend ADR-016 D1).
///
/// The さがす tab is a **regular grouped tab**, not `Tab(role:.search)`:
/// the iOS 26 search role separates it into a detached capsule that reads
/// as an in-screen search button rather than a tab switch. The iOS 26
/// search-field morph is deferred in favor of that clarity (ADR-016 §7).
///
/// `.tint(Color.moss)` tints the active tab on all supported OS.
struct RootTabView: View {
  @Bindable var coordinator: TabCoordinator

  var body: some View {
    tabView
  }

  /// Selection binding whose setter routes through
  /// ``TabCoordinator/handleSelection(_:)`` so a re-tap pops the active tab
  /// to root (§2).
  private var selectionBinding: Binding<AppTab> {
    Binding(
      get: { coordinator.selectedTab },
      set: { coordinator.handleSelection($0) }
    )
  }

  // MARK: - Tab bar (structural `Tab` API; grouped search tab, morph deferred)

  private var tabView: some View {
    TabView(selection: selectionBinding) {
      Tab(value: AppTab.home) {
        homeStack
      } label: {
        tabIcon(.home, label: String(localized: "Home"))
      }
      // さがす: a regular grouped tab — deliberately NOT `role: .search`.
      // The iOS 26 search role separates the tab into its own trailing
      // capsule + morphs it into a search field, but that detached
      // magnifying glass reads as an in-screen search button rather than a
      // tab switch (compounded by History's own in-screen search). Keeping
      // it grouped with the other tabs makes "this switches screens"
      // unmistakable. Search itself stays the in-screen `.searchable` on
      // `SharedScenariosListView`; the iOS 26 morph is deferred (ADR-016 §7).
      Tab(value: AppTab.search) {
        searchStack
      } label: {
        tabIcon(.search, label: String(localized: "Browse"))
      }
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

  // MARK: - Shared per-tab content

  private var homeStack: some View {
    TabNavigationStack(router: coordinator.homeRouter) { HomeView() }
  }
  // Search is the in-screen `.searchable` on `SharedScenariosListView`
  // (`GallerySearchable`); the tab just navigates here (no iOS 26 morph —
  // the search tab is a grouped regular tab, not `role: .search`).
  private var searchStack: some View {
    TabNavigationStack(router: coordinator.searchRouter) { SharedScenariosListView() }
  }
  // History tab root (ADR-016 D4): `.aggregate` selects the cross-variant
  // aggregation of all past results. `Route.results` survives only as the
  // per-scenario detail push (`.scenario`) from ScenarioDetailView;
  // ``ResultsView`` drops its back chrome for this aggregate root variant.
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
      // Locale-independent handle for UI tests to switch tabs by identifier
      // instead of the localized VoiceOver label (StoreScreenshotTests runs
      // under en AND ja, where label-based tab queries would not resolve).
      .accessibilityIdentifier(Self.accessibilityID(for: tab))
  }
}

extension RootTabView {
  /// SF Symbol for `tab`, swapping to the `.fill` variant when active so
  /// the selected tab reads as filled and the others as outlined.
  ///
  /// `magnifyingglass` has **no** `.fill` variant (`magnifyingglass.fill`
  /// does not exist and would render blank), so the さがす tab keeps the
  /// outline in both states and relies on the moss `.tint` alone to mark
  /// active. Pure + `internal` so the mapping is unit-tested. Drives all
  /// four tabs (the さがす tab is a grouped regular tab, not a search role,
  /// so it too maps through here).
  static func symbolName(for tab: AppTab, isActive: Bool) -> String {
    switch tab {
    case .home: return isActive ? "house.fill" : "house"
    case .search: return "magnifyingglass"
    case .history: return isActive ? "clock.fill" : "clock"
    case .settings: return isActive ? "gearshape.fill" : "gearshape"
    }
  }

  /// Stable, locale-independent accessibility identifier for `tab`'s tab-bar
  /// button. Used by `StoreScreenshotTests` to switch tabs by identifier
  /// (`app.tabBars.buttons["rootTab.history"]`) so navigation works under any
  /// locale. Pure + `internal` so the mapping is unit-tested.
  static func accessibilityID(for tab: AppTab) -> String {
    switch tab {
    case .home: return "rootTab.home"
    case .search: return "rootTab.search"
    case .history: return "rootTab.history"
    case .settings: return "rootTab.settings"
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
