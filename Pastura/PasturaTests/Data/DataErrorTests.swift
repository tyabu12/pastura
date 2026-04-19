import Foundation
import Testing

@testable import Pastura

@Suite(.timeLimit(.minutes(1)))
struct DataErrorLocalizedErrorTests {
  // MARK: - LocalizedError conformance

  @Test func conformsToLocalizedError() {
    #expect((DataError.readonly(id: "x") as Any) is LocalizedError)
  }

  // MARK: - errorDescription per case

  @Test func databaseOpenFailedDescription() {
    let error = DataError.databaseOpenFailed(description: "file missing")
    #expect(error.errorDescription?.contains("open failed") ?? false)
    #expect(error.errorDescription?.contains("file missing") ?? false)
  }

  @Test func migrationFailedDescription() {
    let error = DataError.migrationFailed(description: "v2 schema conflict")
    #expect(error.errorDescription?.contains("migration failed") ?? false)
    #expect(error.errorDescription?.contains("v2 schema conflict") ?? false)
  }

  @Test func recordNotFoundDescription() {
    let error = DataError.recordNotFound(type: "ScenarioRecord", id: "abc-123")
    #expect(error.errorDescription?.contains("ScenarioRecord") ?? false)
    #expect(error.errorDescription?.contains("abc-123") ?? false)
  }

  @Test func encodingFailedDescription() {
    let error = DataError.encodingFailed(description: "nil value")
    #expect(error.errorDescription?.contains("Encoding failed") ?? false)
    #expect(error.errorDescription?.contains("nil value") ?? false)
  }

  @Test func decodingFailedDescription() {
    let error = DataError.decodingFailed(description: "unexpected key")
    #expect(error.errorDescription?.contains("Decoding failed") ?? false)
    #expect(error.errorDescription?.contains("unexpected key") ?? false)
  }

  @Test func readonlyDescription() {
    let error = DataError.readonly(id: "scenario-42")
    #expect(error.errorDescription?.contains("read-only") ?? false)
    #expect(error.errorDescription?.contains("scenario-42") ?? false)
  }
}
