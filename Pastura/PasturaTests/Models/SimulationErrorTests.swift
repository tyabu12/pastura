import Foundation
import Testing

@testable import Pastura

@Suite(.timeLimit(.minutes(1)))
struct SimulationErrorTests {
  // MARK: - LocalizedError conformance

  @Test func conformsToLocalizedError() {
    #expect((SimulationError.modelNotLoaded as Any) is LocalizedError)
  }

  // MARK: - errorDescription per case

  @Test func scenarioValidationFailedDescription() {
    let message = "invalid phase type"
    let error = SimulationError.scenarioValidationFailed(message)
    #expect(error.errorDescription?.contains("invalid phase type") ?? false)
  }

  @Test func llmGenerationFailedDescription() {
    let error = SimulationError.llmGenerationFailed(description: "timeout")
    #expect(error.errorDescription?.contains("generation failed") ?? false)
    #expect(error.errorDescription?.contains("timeout") ?? false)
  }

  @Test func jsonParseFailedDescription() {
    let raw = String(repeating: "x", count: 50)
    let error = SimulationError.jsonParseFailed(raw: raw)
    #expect(error.errorDescription?.contains("parse failed") ?? false)
    #expect(error.errorDescription?.contains(raw) ?? false)
  }

  @Test func retriesExhaustedDescription() {
    let error = SimulationError.retriesExhausted
    #expect(error.errorDescription?.contains("retries") ?? false)
  }

  @Test func modelNotLoadedDescription() {
    let error = SimulationError.modelNotLoaded
    #expect(error.errorDescription?.contains("not loaded") ?? false)
  }

  @Test func cancelledDescription() {
    let error = SimulationError.cancelled
    #expect(error.errorDescription?.contains("cancelled") ?? false)
  }

  // MARK: - jsonParseFailed truncation

  @Test func jsonParseFailedTruncatesLongRaw() {
    let longRaw = String(repeating: "a", count: 300)
    let error = SimulationError.jsonParseFailed(raw: longRaw)
    let description = error.errorDescription ?? ""
    // Truncated to 200 chars + "..."
    #expect(description.contains("..."))
    // The raw portion should not exceed 200 + "..." = 203 chars past the prefix
    let prefix = "JSON parse failed: "
    let rawPortion =
      description.hasPrefix(prefix)
      ? String(description.dropFirst(prefix.count))
      : description
    #expect(rawPortion.count <= 203)
  }

  @Test func jsonParseFailedDoesNotTruncateShortRaw() {
    let shortRaw = String(repeating: "b", count: 100)
    let error = SimulationError.jsonParseFailed(raw: shortRaw)
    let description = error.errorDescription ?? ""
    #expect(!description.contains("..."))
    #expect(description.contains(shortRaw))
  }
}
