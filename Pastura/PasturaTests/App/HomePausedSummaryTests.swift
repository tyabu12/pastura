import Foundation
import Testing

@testable import Pastura

/// Unit tests for `HomeViewModel.makePausedSummary` — the pure mapping from
/// paused `SimulationRecord`s to the Home resume-card display model
/// (ADR-016 P2, display-only).
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct HomePausedSummaryTests {

  private func pausedRun(
    id: String,
    scenarioId: String?,
    currentRound: Int = 1,
    nameSnapshot: String? = nil
  ) -> SimulationRecord {
    SimulationRecord(
      id: id, scenarioId: scenarioId,
      status: SimulationStatus.paused.rawValue,
      currentRound: currentRound, currentPhaseIndex: 0,
      stateJSON: "{}", configJSON: nil,
      createdAt: Date(timeIntervalSince1970: 1_700_000_000),
      updatedAt: Date(timeIntervalSince1970: 1_700_000_300),
      scenarioNameSnapshot: nameSnapshot)
  }

  private func scenario(id: String, name: String) -> ScenarioRecord {
    ScenarioRecord(
      id: id, name: name, yamlDefinition: "", isPreset: false,
      createdAt: Date(timeIntervalSince1970: 1_700_000_000),
      updatedAt: Date(timeIntervalSince1970: 1_700_000_000))
  }

  @Test func nilWhenNoPausedRuns() {
    #expect(
      HomeViewModel.makePausedSummary(pausedRuns: [], scenariosById: [:], rowMetadata: [:]) == nil)
  }

  @Test func picksMostRecentRunAndResolvesMetadata() {
    // fetchByStatus returns newest-first, so the first run is the most recent.
    let runs = [
      pausedRun(id: "r1", scenarioId: "s1", currentRound: 3),
      pausedRun(id: "r2", scenarioId: "s2", currentRound: 9)
    ]
    let summary = HomeViewModel.makePausedSummary(
      pausedRuns: runs,
      scenariosById: ["s1": scenario(id: "s1", name: "Word Wolf")],
      rowMetadata: [
        "s1": ScenarioRowMetadata(
          name: "Word Wolf", agentCount: 4, rounds: 5, description: "desc")
      ])
    #expect(summary?.runId == "r1")
    #expect(summary?.name == "Word Wolf")
    #expect(summary?.currentRound == 3)
    #expect(summary?.agentCount == 4)
    #expect(summary?.rounds == 5)
    #expect(summary?.description == "desc")
  }

  @Test func orphanedRunFallsBackToSnapshotName() {
    // scenarioId nil (scenario deleted) → name from snapshot, metadata absent.
    let runs = [pausedRun(id: "r1", scenarioId: nil, currentRound: 2, nameSnapshot: "Deleted One")]
    let summary = HomeViewModel.makePausedSummary(
      pausedRuns: runs, scenariosById: [:], rowMetadata: [:])
    #expect(summary?.name == "Deleted One")
    #expect(summary?.scenarioId == nil)
    #expect(summary?.agentCount == nil)
    #expect(summary?.rounds == nil)
  }

  @Test func nilWhenNameUnresolvable() {
    // scenarioId nil AND no snapshot → cannot label the card → hidden.
    let runs = [pausedRun(id: "r1", scenarioId: nil, nameSnapshot: nil)]
    #expect(
      HomeViewModel.makePausedSummary(pausedRuns: runs, scenariosById: [:], rowMetadata: [:]) == nil
    )
  }

  @Test func liveNamePreferredOverSnapshot() {
    let runs = [pausedRun(id: "r1", scenarioId: "s1", nameSnapshot: "Old Name")]
    let summary = HomeViewModel.makePausedSummary(
      pausedRuns: runs,
      scenariosById: ["s1": scenario(id: "s1", name: "Live Name")],
      rowMetadata: [:])
    #expect(summary?.name == "Live Name")
  }
}
