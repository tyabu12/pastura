import Foundation
import Testing

@testable import Pastura

@Suite(.timeLimit(.minutes(1)))
struct ScenarioSnapshotResolverTests {

  private func makeSim(scenarioId: String?, yaml: String?, name: String?) -> SimulationRecord {
    SimulationRecord(
      id: "sim1", scenarioId: scenarioId, status: "completed",
      currentRound: 1, currentPhaseIndex: 0, stateJSON: "{}", configJSON: nil,
      createdAt: Date(), updatedAt: Date(),
      scenarioYamlSnapshot: yaml, scenarioNameSnapshot: name)
  }

  private func liveRecord(_ id: String, name: String, yaml: String) -> ScenarioRecord {
    ScenarioRecord(
      id: id, name: name, yamlDefinition: yaml,
      isPreset: false, createdAt: Date(), updatedAt: Date())
  }

  @Test func prefersSnapshotOverLiveScenario() throws {
    let sim = makeSim(scenarioId: "sc1", yaml: "name: Snapshot\n", name: "Snapshot Name")
    var liveLookupCalled = false
    let resolved = try ScenarioSnapshotResolver.resolve(for: sim) { _ in
      liveLookupCalled = true
      return self.liveRecord("sc1", name: "Edited Live", yaml: "name: Edited Live\n")
    }
    #expect(resolved?.name == "Snapshot Name")
    #expect(resolved?.yamlDefinition == "name: Snapshot\n")
    // The live lookup must NOT fire when a snapshot exists — this is what
    // immunizes past results from later edits to the live scenario.
    #expect(liveLookupCalled == false)
  }

  @Test func synthesizesRecordForOrphanedRunUsingSimId() throws {
    let sim = makeSim(scenarioId: nil, yaml: "name: Orphan\n", name: "Orphan")
    let resolved = try ScenarioSnapshotResolver.resolve(for: sim) { _ in nil }
    #expect(resolved?.id == "sim1")
    #expect(resolved?.name == "Orphan")
    #expect(resolved?.yamlDefinition == "name: Orphan\n")
  }

  @Test func fallsBackToLiveScenarioWhenNoSnapshot() throws {
    let sim = makeSim(scenarioId: "sc1", yaml: nil, name: nil)
    let resolved = try ScenarioSnapshotResolver.resolve(for: sim) { id in
      self.liveRecord(id, name: "Live", yaml: "name: Live\n")
    }
    #expect(resolved?.name == "Live")
  }

  @Test func returnsNilWhenNeitherSnapshotNorScenarioId() throws {
    let sim = makeSim(scenarioId: nil, yaml: nil, name: nil)
    let resolved = try ScenarioSnapshotResolver.resolve(for: sim) { _ in
      self.liveRecord("x", name: "Live", yaml: "")
    }
    #expect(resolved == nil)
  }
}
