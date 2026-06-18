import Testing

@testable import Pastura

/// Unit tests for ``HomeView/cardPosition(_:firstId:lastId:)`` — the pure
/// display-state helper that places a scenario row within the single grouped
/// card (d3, #684). Locks in the four-case partition so a refactor can't
/// silently break the rounded-corner / hairline rendering (`view-testing.md`
/// rule 1: assert pure logic, never rendered output).
///
/// `@MainActor` per `swift-isolation.md` Pattern 5: `ScenarioCardSlice.Position`
/// is an auto-synth-`Equatable` enum on a default-MainActor App-layer type, so
/// `==` from a nonisolated test would trip the conformance-lookup isolation.
@Suite(.timeLimit(.minutes(1)))
@MainActor
struct HomeScenarioCardPositionTests {

  @Test func singleRowIsOnly() {
    #expect(HomeView.cardPosition("a", firstId: "a", lastId: "a") == .only)
  }

  @Test func firstRowIsTop() {
    #expect(HomeView.cardPosition("a", firstId: "a", lastId: "c") == .top)
  }

  @Test func lastRowIsBottom() {
    #expect(HomeView.cardPosition("c", firstId: "a", lastId: "c") == .bottom)
  }

  @Test func interiorRowIsMiddle() {
    #expect(HomeView.cardPosition("b", firstId: "a", lastId: "c") == .middle)
  }
}
