import Testing

@testable import Pastura

@MainActor
@Suite(.timeLimit(.minutes(1))) struct RootTabViewTests {

  // MARK: - Tab icon fill toggle

  @Test func activeTabUsesFillVariant() {
    #expect(RootTabView.symbolName(for: .home, isActive: true) == "house.fill")
    #expect(RootTabView.symbolName(for: .history, isActive: true) == "clock.fill")
    #expect(RootTabView.symbolName(for: .settings, isActive: true) == "gearshape.fill")
  }

  @Test func inactiveTabUsesOutlineVariant() {
    #expect(RootTabView.symbolName(for: .home, isActive: false) == "house")
    #expect(RootTabView.symbolName(for: .history, isActive: false) == "clock")
    #expect(RootTabView.symbolName(for: .settings, isActive: false) == "gearshape")
  }

  @Test func searchTabHasNoFillVariant() {
    // `magnifyingglass.fill` does not exist in SF Symbols and would render
    // blank — pin the outline in BOTH states so a future "consistency fix"
    // doesn't silently break the さがす tab icon.
    #expect(RootTabView.symbolName(for: .search, isActive: true) == "magnifyingglass")
    #expect(RootTabView.symbolName(for: .search, isActive: false) == "magnifyingglass")
  }
}
