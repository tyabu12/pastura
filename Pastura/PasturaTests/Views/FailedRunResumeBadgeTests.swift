import Testing

@testable import Pastura

// `@MainActor` unconditionally: `resumeRoute` returns the MainActor-isolated
// `Route`, and the identity assertions call `==` on `Route` / the truth-table
// calls `==` on `SimulationStatus` — both resolve their conformance from the
// MainActor context here (swift-isolation Pattern 5). Mirrors DegradedRunBadgeTests.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct FailedRunResumeBadgeTests {

  // MARK: - isResumable truth table

  @Test func failedWithFirstRoundCompletedIsResumable() {
    #expect(FailedRunResumeBadge.isResumable(status: .failed, currentRound: 1))
  }

  @Test func failedWithLaterRoundIsResumable() {
    #expect(FailedRunResumeBadge.isResumable(status: .failed, currentRound: 5))
  }

  @Test func failedBeforeFirstCheckpointIsNotResumable() {
    // Died in round 1 before any `.roundCheckpoint` → currentRound stays 0.
    #expect(!FailedRunResumeBadge.isResumable(status: .failed, currentRound: 0))
  }

  @Test func completedRunIsNotResumable() {
    #expect(!FailedRunResumeBadge.isResumable(status: .completed, currentRound: 5))
  }

  @Test func pausedRunIsNotResumableHere() {
    // `.paused` resumes via the Home card, not this failed-run banner.
    #expect(!FailedRunResumeBadge.isResumable(status: .paused, currentRound: 5))
  }

  @Test func runningRunIsNotResumable() {
    #expect(!FailedRunResumeBadge.isResumable(status: .running, currentRound: 5))
  }

  @Test func cancelledRunIsNotResumable() {
    #expect(!FailedRunResumeBadge.isResumable(status: .cancelled, currentRound: 5))
  }

  @Test func nilStatusIsNotResumable() {
    #expect(!FailedRunResumeBadge.isResumable(status: nil, currentRound: 5))
  }

  // MARK: - resumeRoute

  @Test func resumeRouteTargetsResumeSimulationWithId() {
    let route = FailedRunResumeBadge.resumeRoute(simulationId: "run-1", name: "Foo")
    guard case .resumeSimulation(let id, let hint) = route else {
      Issue.record("expected .resumeSimulation, got \(route)")
      return
    }
    #expect(id == "run-1")
    #expect(hint.value == "Foo")
  }

  @Test func resumeRouteAcceptsNilName() {
    let route = FailedRunResumeBadge.resumeRoute(simulationId: "run-1", name: nil)
    guard case .resumeSimulation(let id, let hint) = route else {
      Issue.record("expected .resumeSimulation, got \(route)")
      return
    }
    #expect(id == "run-1")
    #expect(hint.value == nil)
  }

  @Test func resumeRouteIdentityIgnoresName() {
    // RouteHint is identity-neutral (ADR-008): same id + different name ⇒ ==.
    let routeFoo = FailedRunResumeBadge.resumeRoute(simulationId: "run-1", name: "Foo")
    let routeBar = FailedRunResumeBadge.resumeRoute(simulationId: "run-1", name: "Bar")
    #expect(routeFoo == routeBar)
  }

  @Test func resumeRouteIdentityDistinguishesSimulationId() {
    let routeRun1 = FailedRunResumeBadge.resumeRoute(simulationId: "run-1", name: "Foo")
    let routeRun2 = FailedRunResumeBadge.resumeRoute(simulationId: "run-2", name: "Foo")
    #expect(routeRun1 != routeRun2)
  }

  // MARK: - resumeRoundLabel

  @Test func resumeRoundLabelIsNextRound() {
    #expect(FailedRunResumeBadge.resumeRoundLabel(currentRound: 3) == 4)
    #expect(FailedRunResumeBadge.resumeRoundLabel(currentRound: 1) == 2)
  }
}
