import Foundation
import PasturaSharedEngine
import Synchronization
import Testing

@testable import Pastura

/// S5-2 PR-A acceptance for ``LLMServiceBackend`` — the Stage-5 adapter that
/// drives Kotlin's `LLMCaller` from a real `LLMService` (#1647).
///
/// The §5.2 clauses asserted here are the ones the gate spike asserts against
/// its scripted backend (`BoundaryContractTests`); here the source is a
/// production `LLMService`, so what is under test is the real
/// `AsyncThrowingStream` → callback relay rather than a canned script.
///
/// Kotlin twins are spelled `PasturaSharedEngine.X`
/// (`.claude/rules/kmp-interop.md` Pattern 1b).
@Suite("LLMService → LLMBackend", .timeLimit(.minutes(1)))
struct LLMServiceBackendTests {

  // MARK: - §5.2 clause 1/2 — chunk-then-terminal shape

  @Test("a completed stream forwards its chunks in order, then one Completed")
  func completedShape() async throws {
    let mock = MockLLMService(responses: [])
    try await mock.loadModel()
    mock.setStreamChunks([["Hel", "lo"]])
    let backend = LLMServiceBackend(service: mock)
    let recorder = RecordingBackendCallbacks()

    _ = backend.generateStream(request: .probe, callbacks: recorder)
    try await recorder.waitForTerminal()

    #expect(recorder.chunks.map(\.delta) == ["Hel", "lo", ""])
    #expect(recorder.chunks.map(\.isFinal) == [false, false, true])
    #expect(recorder.chunks.last?.isFinal == true)
    #expect(recorder.terminals.count == 1)
    #expect(recorder.terminals.first is TerminalStatusCompleted)
  }

  @Test("LLMError.suspended maps to exactly one Suspended terminal")
  func suspendedShape() async throws {
    let mock = MockLLMService(responses: [])
    try await mock.loadModel()
    mock.setStreamChunks([["ignored"]])
    mock.throwSuspendedOnNextGenerate()
    let backend = LLMServiceBackend(service: mock)
    let recorder = RecordingBackendCallbacks()

    _ = backend.generateStream(request: .probe, callbacks: recorder)
    try await recorder.waitForTerminal()

    // Clause 1: a cut-off stream carries no final chunk.
    #expect(recorder.chunks.allSatisfy { !$0.isFinal })
    #expect(recorder.terminals.count == 1)
    #expect(recorder.terminals.first is TerminalStatusSuspended)
  }

  @Test("any other LLMError maps to one Failed carrying a stable code")
  func failedShape() async throws {
    let mock = MockLLMService(responses: [])
    try await mock.loadModel()
    mock.setStreamChunks([["ignored"]])
    mock.throwErrorOnNextGenerate(.generationFailed(description: "boom"))
    let backend = LLMServiceBackend(service: mock)
    let recorder = RecordingBackendCallbacks()

    _ = backend.generateStream(request: .probe, callbacks: recorder)
    try await recorder.waitForTerminal()

    #expect(recorder.terminals.count == 1)
    let failed = try #require(recorder.terminals.first as? TerminalStatusFailed)
    // Pinned as a literal rather than as a call to the mapper: asserting
    // `errorCode(for:)` against itself would pass for any spelling.
    #expect(failed.errorCode == "llm.generationFailed")
    #expect(failed.message?.isEmpty == false)
  }

  // MARK: - §5.2 clause 3 — cancellation composition

  @Test("cancel() delivers no terminal, even after the parked call is released")
  func cancellationDeliversNoTerminal() async throws {
    // Wrap mode on purpose: `BlockGate` gates `generate`, and only wrap-mode
    // `generateStream` goes through it — a `setStreamChunks` script would sail
    // straight past the park. One instance per test, because the gate
    // preconditions on "1 generate = 1 waiter".
    let mock = MockLLMService(responses: ["done"])
    try await mock.loadModel()
    mock.blockGenerateUntilSignal()
    let backend = LLMServiceBackend(service: mock)
    let recorder = RecordingBackendCallbacks()

    let handle = backend.generateStream(request: .probe, callbacks: recorder)
    // Give the drain task a scheduling window to reach the park.
    try await Task.sleep(for: .milliseconds(100))
    #expect(recorder.chunks.isEmpty, "the call must still be parked in the gate")
    #expect(recorder.terminals.isEmpty)

    handle.cancel()
    mock.unblockGenerate()
    try await Task.sleep(for: .milliseconds(300))

    // A cancelled call is an orderly teardown, not a failure: synthesising a
    // terminal here would report a fake error for every cancelled run.
    #expect(recorder.terminals.isEmpty)
  }

  // MARK: - §5.2 clause 4 — serial delivery

  @Test("callbacks never overlap within a call")
  func callbacksAreSerialPerCall() async throws {
    let mock = MockLLMService(responses: [])
    try await mock.loadModel()
    mock.setStreamChunks([Array(repeating: "a", count: 40)])
    let backend = LLMServiceBackend(service: mock)
    let recorder = RecordingBackendCallbacks()

    _ = backend.generateStream(request: .probe, callbacks: recorder)
    try await recorder.waitForTerminal()

    #expect(recorder.maxConcurrentEntries == 1)
    #expect(recorder.chunks.count == 41)
  }

  // MARK: - The request payload

  @Test("the Kotlin schema reaches the service as a Swift OutputSchema")
  func schemaReachesTheService() async throws {
    let mock = MockLLMService(responses: [])
    try await mock.loadModel()
    mock.setStreamChunks([["x"]])
    let backend = LLMServiceBackend(service: mock)
    let recorder = RecordingBackendCallbacks()
    let shared = PasturaSharedEngine.OutputSchema(fields: [
      PasturaSharedEngine.OutputSchema.Field(
        name: "statement", kind: PasturaSharedEngine.OutputSchema.KindStringKind.shared)
    ])

    _ = backend.generateStream(
      request: PasturaSharedEngine.GenerationRequest(
        system: "sys", user: "usr", schema: shared, antiRepetitionSeeds: ["prior"]),
      callbacks: recorder)
    try await recorder.waitForTerminal()

    let captured = try #require(mock.capturedSchemas.first)
    #expect(
      captured == OutputSchema(fields: [OutputSchema.Field(name: "statement", kind: .string)]))
    #expect(mock.capturedPrompts.first?.system == "sys")
    #expect(mock.capturedAntiRepetitionSeeds.first == ["prior"])
  }

  // MARK: - knownTurnMarkers (Pattern 3 — the Kotlin default does not cross)

  @Test("knownTurnMarkers forwards the service's pairs, not a ChatML hardcode")
  func knownTurnMarkersAreForwarded() {
    let stub = StubTurnMarkerService(markers: [
      Pastura.ChatTurnMarkers(start: "<a>", end: "</a>"), .chatML
    ])
    let backend = LLMServiceBackend(service: stub)

    #expect(backend.knownTurnMarkers.map(\.start) == ["<a>", "<|im_start|>"])
    #expect(backend.knownTurnMarkers.map(\.end) == ["</a>", "<|im_end|>"])
  }
}

// MARK: - Helpers

/// Records everything the backend delivers, and detects any overlap.
///
/// `maxConcurrentEntries` is the clause-4 assertion: a plain lock-guarded array
/// would *serialize* the very overlap the clause forbids, making a concurrency
/// bug invisible. Ported from the gate spike's `RecordingCallbacks`.
nonisolated final class RecordingBackendCallbacks: StreamCallbacks, @unchecked Sendable {
  struct Chunk: Sendable, Equatable {
    let delta: String
    let isFinal: Bool
    let completionTokens: Int?
  }

  /// Carries `any TerminalStatus` into the mutex-guarded state: a Kotlin
  /// protocol existential has no Swift `Sendable` conformance and cannot be
  /// given one (`kmp-interop.md` Pattern 1).
  private struct TerminalBox: @unchecked Sendable {
    let value: any TerminalStatus
  }

  private struct State {
    var chunks: [Chunk] = []
    var terminals: [TerminalBox] = []
    var entered = 0
    var maxEntered = 0
  }

  private let state = Mutex(State())

  var chunks: [Chunk] { state.withLock { $0.chunks } }
  var terminals: [any TerminalStatus] { state.withLock { $0.terminals }.map(\.value) }
  var maxConcurrentEntries: Int { state.withLock { $0.maxEntered } }

  func onChunk(delta: String, isFinal: Bool, completionTokens: KotlinInt?) {
    enter()
    let chunk = Chunk(
      delta: delta, isFinal: isFinal,
      completionTokens: completionTokens.map { Int($0.int32Value) })
    state.withLock { $0.chunks.append(chunk) }
    leave()
  }

  func onTerminal(status: any TerminalStatus) {
    enter()
    let boxed = TerminalBox(value: status)
    state.withLock { $0.terminals.append(boxed) }
    leave()
  }

  func waitForTerminal() async throws {
    try await pollUntilBackendCondition { !self.terminals.isEmpty }
  }

  private func enter() {
    state.withLock {
      $0.entered += 1
      $0.maxEntered = max($0.maxEntered, $0.entered)
    }
    // Widen the window a genuine overlap would land in — without it two
    // callbacks could interleave and still never be *simultaneously* inside.
    Thread.sleep(forTimeInterval: 0.0005)
  }

  private func leave() {
    state.withLock { $0.entered -= 1 }
  }
}

/// Polls `condition` until it holds, or fails the test on timeout.
///
/// The boundary is callback-driven with no continuation to await, so polling is
/// the honest primitive. Named distinctly from the gate spike's `pollUntil`
/// because the app test target is one module.
func pollUntilBackendCondition(
  timeout: Duration = .seconds(10),
  interval: Duration = .milliseconds(5),
  _ condition: @Sendable () -> Bool,
  sourceLocation: SourceLocation = #_sourceLocation
) async throws {
  let deadline = ContinuousClock.now.advanced(by: timeout)
  while ContinuousClock.now < deadline {
    if condition() { return }
    try await Task.sleep(for: interval)
  }
  Issue.record("Timed out after \(timeout) waiting for condition", sourceLocation: sourceLocation)
}

/// Minimal `LLMService` whose only interesting member is ``knownTurnMarkers``.
///
/// `MockLLMService` cannot name a model, so it keeps the protocol's ChatML-only
/// default — indistinguishable from a hardcode on the adapter. A non-ChatML
/// pair is the only way to tell forwarding from hardcoding.
/// Swift twins are spelled `Pastura.X` here: both modules are in scope, so a
/// bare `ChatTurnMarkers` / `OutputSchema` is ambiguous in a *type* position
/// (`kmp-interop.md` Pattern 1b, seen from the other side).
nonisolated final class StubTurnMarkerService: LLMService, @unchecked Sendable {
  let knownTurnMarkers: [Pastura.ChatTurnMarkers]

  init(markers: [Pastura.ChatTurnMarkers]) {
    self.knownTurnMarkers = markers
  }

  var isModelLoaded: Bool { true }
  let modelIdentifier = "stub"
  let backendIdentifier = "stub"

  func loadModel() async throws {}
  func unloadModel() async throws {}

  func generate(
    system: String, user: String, schema: Pastura.OutputSchema?,
    antiRepetitionSeeds: [String]
  ) async throws -> String {
    "{}"
  }
}

extension PasturaSharedEngine.GenerationRequest {
  /// A request whose content no assertion depends on.
  ///
  /// Every parameter is spelled: K/N drops Kotlin's default arguments, so the
  /// exported initializer is full-arity (`kmp-interop.md` Pattern 3).
  static var probe: PasturaSharedEngine.GenerationRequest {
    PasturaSharedEngine.GenerationRequest(
      system: "system", user: "user", schema: nil, antiRepetitionSeeds: [])
  }
}
