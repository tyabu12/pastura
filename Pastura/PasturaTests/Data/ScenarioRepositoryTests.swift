import Foundation
import Testing

@testable import Pastura

@Suite struct ScenarioRepositoryTests {

  private func makeRepo() throws -> GRDBScenarioRepository {
    let manager = try DatabaseManager.inMemory()
    return GRDBScenarioRepository(dbWriter: manager.dbWriter)
  }

  private func makeRecord(
    id: String = "s1",
    name: String = "Test",
    isPreset: Bool = false
  ) -> ScenarioRecord {
    ScenarioRecord(
      id: id, name: name, yamlDefinition: "yaml: true",
      isPreset: isPreset, createdAt: Date(), updatedAt: Date())
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
}
