import Foundation
import Testing

@testable import Pastura

@MainActor
@Suite(.timeLimit(.minutes(1))) struct TabCoordinatorTests {

  // MARK: - Construction (ADR-016 D3)

  @Test func startsOnHomeTab() {
    let coordinator = TabCoordinator()
    #expect(coordinator.selectedTab == .home)
  }

  @Test func eachTabRootStartsEmpty() {
    let coordinator = TabCoordinator()
    for tab in AppTab.allCases {
      #expect(coordinator.router(for: tab).path.isEmpty)
    }
  }

  @Test func hasFourDistinctRouters() {
    let coordinator = TabCoordinator()
    // D3: four *unmodified* AppRouter instances, one per tab — never a
    // shared/widened router. Identity-distinctness is the contract that
    // keeps each tab's pushIfOnTop / popToRoot guards local.
    let ids = AppTab.allCases.map { ObjectIdentifier(coordinator.router(for: $0)) }
    #expect(Set(ids).count == AppTab.allCases.count)
  }

  @Test func routerForTabReturnsTheTabsOwnInstance() {
    let coordinator = TabCoordinator()
    #expect(coordinator.router(for: .home) === coordinator.homeRouter)
    #expect(coordinator.router(for: .search) === coordinator.searchRouter)
    #expect(coordinator.router(for: .history) === coordinator.historyRouter)
    #expect(coordinator.router(for: .settings) === coordinator.settingsRouter)
  }

  @Test func allRoutersEnumeratesEveryTab() {
    let coordinator = TabCoordinator()
    let fromAll = Set(coordinator.allRouters.map(ObjectIdentifier.init))
    let fromTabs = Set(AppTab.allCases.map { ObjectIdentifier(coordinator.router(for: $0)) })
    #expect(fromAll == fromTabs)
  }

  // MARK: - Tab-reselect → pop-to-root (pure helper; ADR-016 §2 corrected)

  @Test func isReselectionTrueForSelectedTabFalseForOthers() {
    let coordinator = TabCoordinator()  // selectedTab == .home
    #expect(coordinator.isReselection(of: .home))
    #expect(!coordinator.isReselection(of: .search))
    #expect(!coordinator.isReselection(of: .history))
    #expect(!coordinator.isReselection(of: .settings))
  }

  @Test func handleSelectionSwitchesTabWithoutPopping() {
    let coordinator = TabCoordinator()
    coordinator.homeRouter.push(.scenarioDetail(scenarioId: "x"))

    coordinator.handleSelection(.search)

    #expect(coordinator.selectedTab == .search)
    // Switching tabs must NOT unwind the previously-selected tab's stack.
    #expect(coordinator.homeRouter.path == [.scenarioDetail(scenarioId: "x")])
  }

  @Test func handleSelectionReselectPopsThatTabToRoot() {
    let coordinator = TabCoordinator()
    coordinator.homeRouter.push(.scenarioDetail(scenarioId: "x"))
    coordinator.homeRouter.push(.simulation(scenarioId: "x"))

    coordinator.handleSelection(.home)  // re-select the already-selected tab

    #expect(coordinator.selectedTab == .home)
    #expect(coordinator.homeRouter.path.isEmpty)
  }

  @Test func handleSelectionReselectUnwindsOnlyThatTabsStack() {
    let coordinator = TabCoordinator()
    coordinator.homeRouter.push(.scenarioDetail(scenarioId: "home"))
    coordinator.searchRouter.push(.galleryScenarioDetail(scenario: makeGalleryScenario(id: "g")))

    coordinator.handleSelection(.search)  // switch to search (was on home)
    coordinator.handleSelection(.search)  // re-select search → pop search only

    #expect(coordinator.searchRouter.path.isEmpty)
    // Home's stack is untouched by a pop on the search tab.
    #expect(coordinator.homeRouter.path == [.scenarioDetail(scenarioId: "home")])
  }

  // MARK: - isSimulationOnTop fold (ADR-016 D5.1 / D5.4)

  @Test func isSimulationOnTopFalseWhenNoSimulationAnywhere() {
    let coordinator = TabCoordinator()
    coordinator.homeRouter.push(.scenarioDetail(scenarioId: "x"))
    #expect(!coordinator.isSimulationOnTop)
  }

  @Test func isSimulationOnTopTrueWhenSimulationOnNonSelectedTab() {
    let coordinator = TabCoordinator()  // selectedTab == .home
    // A simulation the user backgrounded by switching tabs is still
    // in-flight (ADR-003) — the fold must see it on a NON-selected tab.
    coordinator.searchRouter.push(.simulation(scenarioId: "x"))
    #expect(coordinator.selectedTab == .home)
    #expect(coordinator.isSimulationOnTop)
  }

  @Test func isSimulationOnTopFalseWhenSimulationIsMidStackNotTop() {
    let coordinator = TabCoordinator()
    coordinator.homeRouter.push(.simulation(scenarioId: "x"))
    coordinator.homeRouter.push(.resultDetail(simulationId: "r"))  // sim now mid-stack
    #expect(!coordinator.isSimulationOnTop)
  }

  // MARK: - isSimulationOnTop → warm-splash consumer (ADR-016 D5.4)

  // The fold is correct in isolation (above), and `shouldPlayWarmSplash`
  // is correct given a literal `isSimulationOnTop` (LaunchPhaseCoordinator
  // tests). These wire the REAL any-tab fold into the warm-splash gate —
  // the only coverage that catches a narrowing applied between the fold
  // and its consumer (e.g. the gate reading the selected tab's top route
  // instead of `isSimulationOnTop`). `// D5.4: any-tab — do not narrow`.

  @Test func anyTabSimulationSuppressesWarmSplash() {
    let coordinator = TabCoordinator()  // selectedTab == .home
    // Sim backgrounded on a NON-selected tab: a fold narrowed to the
    // selected tab would return false here and the splash would wrongly
    // play over the in-flight run — this is the regression catch.
    coordinator.searchRouter.push(.simulation(scenarioId: "x"))

    let shouldPlay = LaunchPhaseCoordinator.shouldPlayWarmSplash(
      launchKind: .warm,
      appIsReady: true,
      isSimulationOnTop: coordinator.isSimulationOnTop,
      isSheetActive: false)

    #expect(shouldPlay == false)
  }

  @Test func warmSplashPlaysWhenNoTabHasSimulation() {
    // Positive control so the suppression test isn't vacuously false:
    // with no sim on any tab the fold is false and the warm splash plays.
    let coordinator = TabCoordinator()
    coordinator.homeRouter.push(.scenarioDetail(scenarioId: "x"))

    let shouldPlay = LaunchPhaseCoordinator.shouldPlayWarmSplash(
      launchKind: .warm,
      appIsReady: true,
      isSimulationOnTop: coordinator.isSimulationOnTop,
      isSheetActive: false)

    #expect(shouldPlay == true)
  }

  // MARK: - Deep-link drain routing (ADR-016 D5.2)

  @Test func presentDeepLinkedGalleryScenarioSelectsSearchTabAndPushesOntoIt() {
    let coordinator = TabCoordinator()  // selectedTab == .home
    // User is mid-navigation on a NON-search tab when the link arrives.
    coordinator.homeRouter.push(.scenarioDetail(scenarioId: "home"))
    let scenario = makeGalleryScenario(id: "linked")

    coordinator.presentDeepLinkedGalleryScenario(scenario)

    // Primary, each independently revert-sensitive: the target tab is the
    // resolution-fixed さがす tab (not the currently-selected one), and the
    // detail lands on THAT tab's router.
    #expect(coordinator.selectedTab == .search)
    #expect(coordinator.searchRouter.path.last == .galleryScenarioDetail(scenario: scenario))
    // Secondary defense-in-depth: the routing touches only さがす.
    #expect(coordinator.homeRouter.path == [.scenarioDetail(scenarioId: "home")])
    #expect(coordinator.historyRouter.path.isEmpty)
    #expect(coordinator.settingsRouter.path.isEmpty)
  }

  @Test func presentDeepLinkedGalleryScenarioAppendsOntoNonEmptySearchStack() {
    let coordinator = TabCoordinator()
    // さがす already shows a gallery detail (user browsed there) when a new
    // link drains. Plain `push` appends unconditionally — pinning the
    // D5.2 plain-`push` choice so a future ⑥ switch to a guarded push
    // surfaces here rather than passing silently.
    let existing = makeGalleryScenario(id: "existing")
    coordinator.searchRouter.push(.galleryScenarioDetail(scenario: existing))
    let linked = makeGalleryScenario(id: "linked")

    coordinator.presentDeepLinkedGalleryScenario(linked)

    #expect(
      coordinator.searchRouter.path == [
        .galleryScenarioDetail(scenario: existing),
        .galleryScenarioDetail(scenario: linked)
      ])
  }

  // MARK: - Cross-tab isolation (ADR-016 D3)

  @Test func pushOnOneTabLeavesOtherTabsEmpty() {
    let coordinator = TabCoordinator()
    coordinator.homeRouter.push(.scenarioDetail(scenarioId: "x"))

    #expect(coordinator.searchRouter.path.isEmpty)
    #expect(coordinator.historyRouter.path.isEmpty)
    #expect(coordinator.settingsRouter.path.isEmpty)
  }

  // MARK: - Return to running simulation (Phase B, ADR-017 #682)

  @Test func returnToRunningSimulationSelectsHostTabAndPushesRoute() {
    let coordinator = TabCoordinator()
    coordinator.selectedTab = .home

    let route = Route.simulation(scenarioId: "abc")
    coordinator.returnToRunningSimulation(tab: .search, route: route)

    #expect(coordinator.selectedTab == .search, "re-selects the run's host tab")
    #expect(coordinator.searchRouter.path == [route], "pushes the sim route onto the host tab")
  }

  @Test func returnToRunningSimulationDoesNotPushDuplicateWhenOnTop() {
    let coordinator = TabCoordinator()
    let route = Route.resumeSimulation(simulationId: "run-1")
    coordinator.homeRouter.push(route)

    coordinator.returnToRunningSimulation(tab: .home, route: route)

    #expect(
      coordinator.homeRouter.path == [route],
      "no duplicate push when the sim route is already on top (rapid re-tap)")
  }

  // MARK: - Helpers

  private func makeGalleryScenario(id: String) -> GalleryScenario {
    GalleryScenario(
      id: id, title: id, category: .experimental,
      description: "", author: "",
      recommendedModel: ModelRegistry.gemma4E2B.id, estimatedInferences: 0,
      // swiftlint:disable:next force_unwrapping
      yamlURL: URL(string: "https://example.com/\(id).yaml")!,
      yamlSHA256: "h", addedAt: "2026-04-15")
  }
}
