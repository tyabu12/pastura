import Foundation
import SwiftUI

/// The four bottom-bar tabs (ADR-016 D1).
///
/// Raw IA identity only — labels / SF Symbols / tint live at the
/// `TabView` construction site (``RootTabView``), not here, so the
/// coordinator stays a pure navigation-state owner with no view concerns.
enum AppTab: Hashable, CaseIterable {
  case home
  case search
  case history
  case settings
}

/// Owns the four per-tab navigation stacks and the selected-tab state for
/// the bottom-tab information architecture (ADR-016 D3).
///
/// ## Why four routers rather than one widened `AppRouter`
///
/// The existing navigation guards (`pushIfOnTop`, `popToRoot`,
/// `path.last`) are written against a single linear `[Route]` stack. Four
/// independent ``AppRouter`` instances preserve every guard's correctness
/// **locally inside each tab**; a single four-segmented path would force
/// each guard to learn which segment it operates on. So this coordinator
/// holds four *unmodified* `AppRouter`s — the type each guard already
/// depends on is never mutated (ADR-016 D3, navigation.md
/// "AppRouter scope").
///
/// ## Why `selectedTab` lives here, not on `AppRouter`
///
/// `navigation.md` § "AppRouter scope (load-bearing)" forbids non-path
/// state on `AppRouter`. Tab selection is selection state, not a
/// navigation path, so it belongs on the coordinator.
@Observable
@MainActor
final class TabCoordinator {
  /// 牧場 — brand header + resumable-simulation card + scenario list.
  let homeRouter = AppRouter()
  /// さがす — shared-scenario gallery + search.
  let searchRouter = AppRouter()
  /// 観察履歴 — past results, date-grouped.
  let historyRouter = AppRouter()
  /// 設定 — settings surface.
  let settingsRouter = AppRouter()

  /// The currently-selected tab. Drives the `TabView` selection binding.
  var selectedTab: AppTab = .home

  /// All four routers, for cross-tab folds (e.g. ``isSimulationOnTop``).
  /// Order matches ``AppTab/allCases``.
  var allRouters: [AppRouter] {
    [homeRouter, searchRouter, historyRouter, settingsRouter]
  }

  /// The `AppRouter` owning `tab`'s navigation stack.
  func router(for tab: AppTab) -> AppRouter {
    switch tab {
    case .home: return homeRouter
    case .search: return searchRouter
    case .history: return historyRouter
    case .settings: return settingsRouter
    }
  }

  /// Whether a `.simulation` route is on top of **any** tab's stack.
  ///
  /// `// D5.4: any-tab — do not narrow`. A simulation the user
  /// backgrounded by switching tabs is genuinely in-flight (its inference
  /// + `BGContinuedProcessingTask` re-attach keep running regardless of
  /// the selected tab — ADR-003), so it must still block the deep-link
  /// drain and suppress the warm splash. Narrowing this to the selected
  /// tab would mis-time both (ADR-016 D5.4).
  var isSimulationOnTop: Bool {
    allRouters.contains { router in
      if case .some(.simulation) = router.path.last { return true }
      return false
    }
  }

  /// Pure predicate for the tab-reselect → pop-to-root interceptor:
  /// `true` when `tab` is already the selected tab.
  ///
  /// Extracted so the interceptor decision is unit-testable without a
  /// live `TabView` (mirrors
  /// ``LaunchPhaseCoordinator/shouldPlayWarmSplash(launchKind:appIsReady:isSimulationOnTop:isSheetActive:)``).
  ///
  /// Why a manual interceptor at all: SwiftUI's native auto-pop-to-root
  /// on re-tapping the active tab does **not** fire for a
  /// `NavigationStack(path:)` bound to an explicit `[Route]` array — the
  /// system only manages its own implicit path. The native bar provides
  /// the *gesture surface* (the selection binding's setter is invoked on
  /// re-tap); the path reset is ours to perform (ADR-016 §2, corrected).
  func isReselection(of tab: AppTab) -> Bool {
    tab == selectedTab
  }

  /// Applies a tab-bar selection event: pop the tab to root on
  /// re-selection, switch to it otherwise. Wire this from the `TabView`
  /// selection `Binding`'s setter.
  func handleSelection(_ tab: AppTab) {
    if isReselection(of: tab) {
      router(for: tab).popToRoot()
    } else {
      selectedTab = tab
    }
  }

  /// Presents a resolved deep-linked gallery scenario on the さがす
  /// (Search) tab (ADR-016 D5.2).
  ///
  /// A `.galleryScenarioDetail` is a さがす-tab destination, so the target
  /// tab is fixed by the resolution kind — **not** the currently-selected
  /// tab. Select that tab, then push onto its router. So a link arriving
  /// while the user is on another tab still lands the detail on Search.
  ///
  /// Plain `push` (not `pushIfOnTop`): the `await` that `pushIfOnTop`
  /// guards already completed in `PasturaApp.tryDrain` before the drain
  /// reaches here, and the freshly-selected tab root is normally an empty
  /// stack where `pushIfOnTop` would no-op. Matches the prior
  /// unconditional push. (Extracted from `PasturaApp.applyResolution` so
  /// the routing kernel is unit-testable — `DeepLinkTabRoutingUITests`
  /// covers the surrounding async drain glue end-to-end.)
  func presentDeepLinkedGalleryScenario(_ scenario: GalleryScenario) {
    selectedTab = .search
    searchRouter.push(.galleryScenarioDetail(scenario: scenario))
  }
}
