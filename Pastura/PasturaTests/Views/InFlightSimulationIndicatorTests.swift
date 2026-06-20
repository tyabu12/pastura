import Testing

@testable import Pastura

// `@MainActor` because `shouldShowIndicator` is a static on the
// default-MainActor `InFlightSimulationIndicator`; the suite isolation lets a
// nonisolated caller reach it (`.claude/rules/swift-isolation.md` Pattern 5).
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct InFlightSimulationIndicatorTests {

  @Test func showsWhenActiveAndNotOnSimScreen() {
    // Parked-away: a run is active but no tab has the sim on top.
    #expect(
      InFlightSimulationIndicator.shouldShowIndicator(isActive: true, isSimulationOnTop: false))
  }

  @Test func hiddenWhileWatchingTheSim() {
    // On the sim screen — SimulationView is already showing the live state.
    #expect(
      !InFlightSimulationIndicator.shouldShowIndicator(isActive: true, isSimulationOnTop: true))
  }

  @Test func hiddenWhenNoRunActive() {
    #expect(
      !InFlightSimulationIndicator.shouldShowIndicator(isActive: false, isSimulationOnTop: false))
    #expect(
      !InFlightSimulationIndicator.shouldShowIndicator(isActive: false, isSimulationOnTop: true))
  }
}
