import Foundation
import PasturaSharedEngine
import Testing

@testable import Pastura

/// ADR-021 D3 failure classification at the §5.2 boundary (#1689).
///
/// A sibling file rather than more of `LLMServiceBackendTests.swift`, which is at
/// SwiftLint's `file_length` budget — the same split the Engine suite uses for
/// `SpeakAllHandlerTests+TurnDegradation.swift`.
///
/// What these pin: Kotlin decides whether a failed generation kills the run or
/// degrades one turn by reading `TerminalStatus.Failed.kind`, and that field is
/// supplied *here* — K/N drops Kotlin's default, so nothing on the Kotlin side can
/// fill it in (`kmp-interop.md` Pattern 3).
///
/// `StreamFailureKind` is a Kotlin enum, which K/N exports as a **class** with
/// static instances (compare with `EngineLogLevel` in `EngineLoggerBridge.swift`),
/// hence `===` rather than `==`.
extension LLMServiceBackendTests {

  @Test("failureKind maps the two systemic LLMError cases, everything else transient")
  func failureKindClassification() {
    // The unit half. Pinned case by case rather than by calling the Swift twin
    // `streamFailureError`, which would assert the mapping against itself.
    #expect(LLMServiceBackend.failureKind(for: LLMError.notLoaded) === StreamFailureKind.systemic)
    #expect(
      LLMServiceBackend.failureKind(for: LLMError.invalidGrammar(description: "bad grammar"))
        === StreamFailureKind.systemic)
    #expect(
      LLMServiceBackend.failureKind(for: LLMError.generationFailed(description: "boom"))
        === StreamFailureKind.transient)

    struct Boom: Error {}
    #expect(LLMServiceBackend.failureKind(for: Boom()) === StreamFailureKind.transient)
  }

  @Test("a systemic LLMError reaches Kotlin as Failed(kind: .systemic)")
  func systemicFailureCrossesTheBoundary() async throws {
    // The drain-path half, and the one that reddens if `drain` ever hard-codes
    // `.transient`: Kotlin branches the whole run on this field, so a stuck
    // `.transient` would silently restore the pre-#1689 behaviour where a
    // model-less backend degraded turn by turn instead of aborting.
    let mock = MockLLMService(responses: [])
    try await mock.loadModel()
    mock.setStreamChunks([["ignored"]])
    mock.throwErrorOnNextGenerate(.notLoaded)
    let backend = LLMServiceBackend(service: mock)
    let recorder = RecordingBackendCallbacks()

    _ = backend.generateStream(request: .probe, callbacks: recorder)
    try await recorder.waitForTerminal()

    #expect(recorder.terminals.count == 1)
    let failed = try #require(recorder.terminals.first as? TerminalStatusFailed)
    #expect(failed.kind === StreamFailureKind.systemic)
    #expect(failed.errorCode == "llm.notLoaded")
  }

  @Test("a transient LLMError reaches Kotlin as Failed(kind: .transient)")
  func transientFailureCrossesTheBoundary() async throws {
    let mock = MockLLMService(responses: [])
    try await mock.loadModel()
    mock.setStreamChunks([["ignored"]])
    mock.throwErrorOnNextGenerate(.generationFailed(description: "boom"))
    let backend = LLMServiceBackend(service: mock)
    let recorder = RecordingBackendCallbacks()

    _ = backend.generateStream(request: .probe, callbacks: recorder)
    try await recorder.waitForTerminal()

    let failed = try #require(recorder.terminals.first as? TerminalStatusFailed)
    #expect(failed.kind === StreamFailureKind.transient)
  }
}
