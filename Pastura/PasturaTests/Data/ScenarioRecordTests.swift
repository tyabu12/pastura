import Foundation
import GRDB
import Testing

@testable import Pastura

@Suite struct ScenarioRecordTests {

  private func makeManager() throws -> DatabaseManager {
    try DatabaseManager.inMemory()
  }

  @Test func insertAndFetchById() throws {
    let manager = try makeManager()
    let now = Date()
    var record = ScenarioRecord(
      id: "s1",
      name: "Test Scenario",
      yamlDefinition: "name: test\nrounds: 1",
      isPreset: false,
      createdAt: now,
      updatedAt: now
    )

    try manager.dbWriter.write { db in
      try record.insert(db)
    }

    let fetched = try manager.dbWriter.read { db in
      try ScenarioRecord.fetchOne(db, key: "s1")
    }

    #expect(fetched != nil)
    #expect(fetched?.name == "Test Scenario")
    #expect(fetched?.yamlDefinition == "name: test\nrounds: 1")
    #expect(fetched?.isPreset == false)
  }

  @Test func presetFlag() throws {
    let manager = try makeManager()
    let now = Date()
    var preset = ScenarioRecord(
      id: "p1", name: "Preset", yamlDefinition: "yaml",
      isPreset: true, createdAt: now, updatedAt: now)
    var userCreated = ScenarioRecord(
      id: "u1", name: "User", yamlDefinition: "yaml",
      isPreset: false, createdAt: now, updatedAt: now)

    try manager.dbWriter.write { db in
      try preset.insert(db)
      try userCreated.insert(db)
    }

    let presets = try manager.dbWriter.read { db in
      try ScenarioRecord.filter(Column("isPreset") == true).fetchAll(db)
    }

    #expect(presets.count == 1)
    #expect(presets.first?.id == "p1")
  }

  @Test func fetchAllReturnsAllRecords() throws {
    let manager = try makeManager()
    let now = Date()

    try manager.dbWriter.write { db in
      for i in 1...3 {
        var record = ScenarioRecord(
          id: "s\(i)", name: "Scenario \(i)", yamlDefinition: "yaml",
          isPreset: false, createdAt: now, updatedAt: now)
        try record.insert(db)
      }
    }

    let all = try manager.dbWriter.read { db in
      try ScenarioRecord.fetchAll(db)
    }
    #expect(all.count == 3)
  }

  @Test func deleteRemovesRecord() throws {
    let manager = try makeManager()
    let now = Date()
    var record = ScenarioRecord(
      id: "s1", name: "Test", yamlDefinition: "yaml",
      isPreset: false, createdAt: now, updatedAt: now)

    try manager.dbWriter.write { db in
      try record.insert(db)
      let deleted = try record.delete(db)
      #expect(deleted)
    }

    let fetched = try manager.dbWriter.read { db in
      try ScenarioRecord.fetchOne(db, key: "s1")
    }
    #expect(fetched == nil)
  }
}
