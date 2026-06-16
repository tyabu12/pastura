import Foundation
import Testing

@testable import Pastura

/// Pure-logic test for `HomePausedCard`'s resume dispatch (ADR-009 /
/// `.claude/rules/view-testing.md` — extract view logic, assert pure
/// properties). `@MainActor` because `Route` is a default-MainActor enum whose
/// auto-synthesized `Equatable` conformance lookup is MainActor-isolated
/// (swift-isolation.md Pattern 5).
@Suite(.timeLimit(.minutes(1)))
@MainActor
struct HomePausedCardTests {

  private func makeSummary(
    runId: String = "run-123", name: String = "Prisoner's Dilemma"
  ) -> PausedScenarioSummary {
    PausedScenarioSummary(
      runId: runId, scenarioId: "scn-1", name: name,
      agentCount: 2, rounds: 5, currentRound: 2, description: "desc")
  }

  @Test func resumeRouteTargetsResumeSimulationWithRunId() {
    let summary = makeSummary(runId: "run-abc")
    let route = HomePausedCard.resumeRoute(for: summary)

    guard case .resumeSimulation(let simulationId, _) = route else {
      Issue.record("expected .resumeSimulation, got \(route)")
      return
    }
    #expect(simulationId == "run-abc")
  }

  @Test func resumeRouteIdentityMatchesOnRunIdRegardlessOfName() {
    // RouteHint is identity-neutral (ADR-008), so the name hint must not affect
    // Route identity — a `pushIfOnTop`-style guard written without the hint
    // still matches.
    let route = HomePausedCard.resumeRoute(for: makeSummary(runId: "run-x", name: "Whatever"))
    #expect(route == .resumeSimulation(simulationId: "run-x"))
  }
}
