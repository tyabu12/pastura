import Foundation
import GRDB
import Testing

@testable import Pastura

@Suite(.timeLimit(.minutes(1))) struct ScenarioRepositoryTests {

  private func makeRepo() throws -> GRDBScenarioRepository {
    let manager = try DatabaseManager.inMemory()
    return GRDBScenarioRepository(dbWriter: manager.dbWriter)
  }

  private func makeRecord(
    id: String = "s1",
    name: String = "Test",
    isPreset: Bool = false,
    sourceType: String? = nil,
    sourceId: String? = nil,
    sourceHash: String? = nil
  ) -> ScenarioRecord {
    ScenarioRecord(
      id: id, name: name, yamlDefinition: "yaml: true",
      isPreset: isPreset, createdAt: Date(), updatedAt: Date(),
      sourceType: sourceType, sourceId: sourceId, sourceHash: sourceHash)
  }

  @Test func saveAndFetchById() throws {
    let repo = try makeRepo()
    let record = makeRecord()

    try repo.save(record)
    let fetched = try repo.fetchById("s1")

    #expect(fetched != nil)
    #expect(fetched?.name == "Test")
  }

  @Test func fetchByIdReturnsNilForMissing() throws {
    let repo = try makeRepo()
    let fetched = try repo.fetchById("nonexistent")
    #expect(fetched == nil)
  }

  @Test func fetchAllReturnsAllRecords() throws {
    let repo = try makeRepo()
    for i in 1...3 {
      try repo.save(makeRecord(id: "s\(i)", name: "Scenario \(i)"))
    }

    let all = try repo.fetchAll()
    #expect(all.count == 3)
  }

  @Test func fetchPresetsReturnsOnlyPresets() throws {
    let repo = try makeRepo()
    try repo.save(makeRecord(id: "p1", name: "Preset 1", isPreset: true))
    try repo.save(makeRecord(id: "p2", name: "Preset 2", isPreset: true))
    try repo.save(makeRecord(id: "u1", name: "User 1", isPreset: false))

    let presets = try repo.fetchPresets()
    #expect(presets.count == 2)
    let allPresets = presets.allSatisfy(\.isPreset)
    #expect(allPresets)
  }

  @Test func deleteRemovesRecord() throws {
    let repo = try makeRepo()
    try repo.save(makeRecord())

    try repo.delete("s1")
    let fetched = try repo.fetchById("s1")
    #expect(fetched == nil)
  }

  @Test func deleteNonexistentDoesNotThrow() throws {
    let repo = try makeRepo()
    // Should not throw for missing record
    try repo.delete("nonexistent")
  }

  @Test func saveOverwritesExistingRecord() throws {
    let repo = try makeRepo()
    try repo.save(makeRecord(name: "Original"))

    let updated = makeRecord(name: "Updated")
    try repo.save(updated)

    let fetched = try repo.fetchById("s1")
    #expect(fetched?.name == "Updated")

    let all = try repo.fetchAll()
    #expect(all.count == 1)
  }

  // MARK: - Source provenance

  @Test func fetchBySourceFindsGalleryRow() throws {
    let repo = try makeRepo()
    try repo.save(
      makeRecord(
        id: "s1", sourceType: ScenarioSourceType.gallery, sourceId: "asch_v1", sourceHash: "h1"))
    try repo.save(makeRecord(id: "s2"))  // local, no source

    let hit = try repo.fetchBySource(type: ScenarioSourceType.gallery, id: "asch_v1")
    #expect(hit?.id == "s1")

    let miss = try repo.fetchBySource(type: ScenarioSourceType.gallery, id: "unknown")
    #expect(miss == nil)
  }

  @Test func fetchBySourceIgnoresLocalRows() throws {
    let repo = try makeRepo()
    try repo.save(makeRecord(id: "local"))  // sourceType = nil

    // A nil-sourceType row should not be returned even if sourceId matches
    // (which it cannot, since it's nil — defensive check).
    let hit = try repo.fetchBySource(type: ScenarioSourceType.gallery, id: "local")
    #expect(hit == nil)
  }

  // MARK: - Readonly guard on save()

  @Test func saveRefusesToOverwriteGalleryRowWithLocalPayload() throws {
    let repo = try makeRepo()
    try repo.save(
      makeRecord(
        id: "g1", sourceType: ScenarioSourceType.gallery, sourceId: "asch_v1", sourceHash: "h1"))

    // A local/user edit (sourceType = nil) must be refused.
    let localEdit = makeRecord(id: "g1", name: "Hacked")
    #expect(throws: DataError.readonly(id: "g1")) {
      try repo.save(localEdit)
    }

    // Original row survives untouched.
    let fetched = try repo.fetchById("g1")
    #expect(fetched?.name == "Test")
    #expect(fetched?.sourceType == ScenarioSourceType.gallery)
  }

  @Test func saveAllowsGalleryUpdatePayloadOverGalleryRow() throws {
    let repo = try makeRepo()
    try repo.save(
      makeRecord(
        id: "g1", name: "Old", sourceType: ScenarioSourceType.gallery,
        sourceId: "asch_v1", sourceHash: "h1"))

    // A gallery Update flow passes a gallery-sourced payload — allowed.
    let updated = makeRecord(
      id: "g1", name: "New", sourceType: ScenarioSourceType.gallery,
      sourceId: "asch_v1", sourceHash: "h2")
    try repo.save(updated)

    let fetched = try repo.fetchById("g1")
    #expect(fetched?.name == "New")
    #expect(fetched?.sourceHash == "h2")
  }

  @Test func saveAllowsNewLocalRowWhenNoGalleryExists() throws {
    // Guard must NOT fire when there is no pre-existing row at all.
    let repo = try makeRepo()
    try repo.save(makeRecord(id: "new"))
    #expect(try repo.fetchById("new") != nil)
  }

  @Test func saveAllowsNewGalleryRowWhenNoExistingRow() throws {
    // Symmetric case: a first-time gallery Try with no pre-existing row.
    let repo = try makeRepo()
    try repo.save(
      makeRecord(
        id: "g1", sourceType: ScenarioSourceType.gallery,
        sourceId: "asch_v1", sourceHash: "h1"))
    let fetched = try repo.fetchById("g1")
    #expect(fetched?.sourceType == ScenarioSourceType.gallery)
  }

  @Test func saveRefusesGalleryPayloadWithDifferentSourceIdOverGalleryRow() throws {
    // A gallery payload must not overwrite a gallery row belonging to a
    // different sourceId — sameGallerySource requires sourceId equality.
    let repo = try makeRepo()
    try repo.save(
      makeRecord(
        id: "g1", sourceType: ScenarioSourceType.gallery,
        sourceId: "asch_v1", sourceHash: "h1"))

    let imposter = makeRecord(
      id: "g1", name: "Imposter",
      sourceType: ScenarioSourceType.gallery,
      sourceId: "milgram_v1", sourceHash: "h2")
    #expect(throws: DataError.readonly(id: "g1")) {
      try repo.save(imposter)
    }
  }

  // MARK: - UPDATE (not REPLACE) preserves FK cascade

  @Test func saveUpdatesInPlaceSoSimulationsSurvive() throws {
    // Regression guard: GRDB's save() must issue UPDATE, not DELETE+INSERT.
    // If it were REPLACE, ON DELETE CASCADE on simulations.scenarioId
    // would silently wipe all past results when a scenario is re-saved.
    let manager = try DatabaseManager.inMemory()
    let scenarioRepo = GRDBScenarioRepository(dbWriter: manager.dbWriter)

    let scenario = ScenarioRecord(
      id: "s1", name: "Original", yamlDefinition: "yaml: true",
      isPreset: false, createdAt: Date(), updatedAt: Date())
    try scenarioRepo.save(scenario)

    let now = Date()
    var sim = SimulationRecord(
      id: "sim1", scenarioId: "s1", status: "running",
      currentRound: 0, currentPhaseIndex: 0,
      stateJSON: "{}", configJSON: nil, createdAt: now, updatedAt: now)
    try manager.dbWriter.write { db in
      try sim.insert(db)
    }

    // Re-save scenario (simulates an Update)
    var updated = scenario
    updated.name = "Renamed"
    updated.updatedAt = Date()
    try scenarioRepo.save(updated)

    // Simulation must still exist — if save did DELETE+INSERT, the FK
    // cascade would have wiped it.
    let simStillThere = try manager.dbWriter.read { db in
      try SimulationRecord.fetchOne(db, key: "sim1")
    }
    #expect(simStillThere != nil)
    #expect(simStillThere?.scenarioId == "s1")
  }
}
