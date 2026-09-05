import PasturaSharedEngine
import Testing

@testable import Pastura

/// Split out of `SimulationEventBridgeTests.swift` to stay under SwiftLint's
/// `type_body_length` cap (`.claude/rules/testing.md` § "Splitting a Suite
/// Across Files") — an `extension` of the same `@Suite` struct, not a second
/// suite, so these tests still run under that file's `.timeLimit` and are
/// never race-prone against it.
extension SimulationEventBridgeTests {

  // MARK: - Errors

  @Test("ErrorEvent(Cancelled) converts")
  func convertsErrorCancelled() {
    let shared = PasturaSharedEngine.SimulationEvent.ErrorEvent(
      error: PasturaSharedEngine.SimulationError.Cancelled.shared)
    #expect(SimulationEvent(shared: shared) == .error(.cancelled))
  }

  @Test("ErrorEvent(JsonParseFailed) converts")
  func convertsErrorJsonParseFailed() {
    let shared = PasturaSharedEngine.SimulationEvent.ErrorEvent(
      error: PasturaSharedEngine.SimulationError.JsonParseFailed(raw: "{bad"))
    #expect(SimulationEvent(shared: shared) == .error(.jsonParseFailed(raw: "{bad")))
  }

  @Test("ErrorEvent(LlmGenerationFailed) converts, description_ maps to description")
  func convertsErrorLlmGenerationFailed() {
    let shared = PasturaSharedEngine.SimulationEvent.ErrorEvent(
      error: PasturaSharedEngine.SimulationError.LlmGenerationFailed(description: "boom"))
    #expect(
      SimulationEvent(shared: shared) == .error(.llmGenerationFailed(description: "boom")))
  }

  @Test("ErrorEvent(ModelNotLoaded) converts")
  func convertsErrorModelNotLoaded() {
    let shared = PasturaSharedEngine.SimulationEvent.ErrorEvent(
      error: PasturaSharedEngine.SimulationError.ModelNotLoaded.shared)
    #expect(SimulationEvent(shared: shared) == .error(.modelNotLoaded))
  }

  @Test("ErrorEvent(RetriesExhausted) converts")
  func convertsErrorRetriesExhausted() {
    let shared = PasturaSharedEngine.SimulationEvent.ErrorEvent(
      error: PasturaSharedEngine.SimulationError.RetriesExhausted.shared)
    #expect(SimulationEvent(shared: shared) == .error(.retriesExhausted))
  }

  @Test("ErrorEvent(ScenarioValidationFailed) converts")
  func convertsErrorScenarioValidationFailed() {
    let shared = PasturaSharedEngine.SimulationEvent.ErrorEvent(
      error: PasturaSharedEngine.SimulationError.ScenarioValidationFailed(message: "bad scenario"))
    #expect(
      SimulationEvent(shared: shared)
        == .error(.scenarioValidationFailed("bad scenario")))
  }

  @Test("ErrorEvent(TurnFailureLimitReached) converts")
  func convertsErrorTurnFailureLimitReached() {
    let shared = PasturaSharedEngine.SimulationEvent.ErrorEvent(
      error: PasturaSharedEngine.SimulationError.TurnFailureLimitReached(consecutiveCount: 4))
    #expect(
      SimulationEvent(shared: shared) == .error(.turnFailureLimitReached(consecutiveCount: 4)))
  }

  // MARK: - PhaseType roster

  @Test("every Kotlin PhaseType entry maps to a non-nil Swift PhaseType")
  func phaseTypeRosterMapsCompletely() {
    let entries = PasturaSharedEngine.PhaseType.entries
    // Roster pin (Pattern 4 wording): counted by hand against
    // `PhaseType.swift`'s 14 cases on 2026-09-05, not a proof this list
    // stays exhaustive after a Kotlin bump.
    #expect(entries.count == 14)
    for entry in entries {
      #expect(PhaseType(shared: entry) != nil, "no Swift mapping for \(entry.name)")
    }
  }

  // MARK: - TurnOutput

  @Test("TurnOutput conversion always yields a nil rawText")
  func turnOutputHasNilRawText() {
    let shared = PasturaSharedEngine.TurnOutput(fields: ["statement": "hi"])
    let converted = TurnOutput(shared: shared)
    #expect(converted.fields == ["statement": "hi"])
    #expect(converted.rawText == nil)
  }
}
