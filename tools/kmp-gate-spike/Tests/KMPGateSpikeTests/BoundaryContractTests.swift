import PasturaSharedEngine
import Synchronization
import Testing

@testable import KMPGateSpike

/// Fixes the ADR-023 §5.1 / §5.2 boundary contracts as far as they are
/// *observable* from the Swift side — the Stage-2 gate's correctness half.
///
/// **What "observable" excludes, deliberately.** §5.2's invariant 3
/// (lost-wakeup safety) is a *design* constraint, not a behaviour a test can
/// witness: it holds because `SuspendController` latches `.resumed` with no
/// awaiter and Kotlin's `CompletableDeferred` completes sticky. A test can
/// only sample orderings it happens to schedule, so passing would prove
/// nothing about the constraint in general — and MEASURED, no e2e test here
/// reaches it: `store(handle)` runs a few instructions after `engine.run`
/// returns, while a `.suspended` terminal costs several async hops, so the
/// empty-box window never opens from this direction. Deleting `RunHandleBox`'s
/// `pendingResume` latch leaves every end-to-end test in this suite green.
///
/// So the split is deliberate. The end-to-end tests pin the *relay paths*
/// (``suspensionRelayRoundTrip`` resuming mid-run,
/// ``resumeLatchedBeforeTheRunStartsStillCompletes`` resuming before it). The
/// lost-wakeup window itself is pinned in ``RunHandleBoxLatchTests``, which
/// signals the box directly and does fail under that deletion. Invariant 3 itself is defended by the
/// verbatim-copy drift guard on `SuspendController` — the object under test is
/// byte-identical to the shipping one, so its latch semantics are not a
/// stand-in.
///
/// Note that the *forwarding order* inside `RelayObservingCallbacks` is *not*
/// what makes this work, though an earlier revision of this suite said so.
/// Kotlin's `LLMCaller` arms the relay before issuing the stream, so the
/// deferred spans the entire window regardless of the order used here.
/// The time limit is load-bearing, not hygiene. A broken suspension relay does
/// not make these tests *fail* — it makes them **hang**, because the engine
/// stays parked and the consumer task never returns. Verified by deleting the
/// `notifyLLMResumed()` call: without this trait the run wedges until CI's own
/// job timeout, reporting nothing useful.
///
/// `.serialized` because several tests here drain paced scripts with a real
/// sleep per callback, and the Pattern 6 probe next door asserts MainActor
/// liveness against a tick floor. Letting these overlap each other starves that
/// probe; the suite is sub-second, so serialising costs nothing. Cross-*suite*
/// overlap is not covered by this trait — that is why the package is run with
/// `--no-parallel` (see the README and `kmp-nightly.yml`).
@Suite("§5 boundary contracts", .timeLimit(.minutes(1)), .serialized)
struct BoundaryContractTests {

  // MARK: - §5.2 clause 1/2 — chunk-then-terminal shape

  @Test("a completed call ends with one final chunk, then exactly one Completed")
  func completedShape() async throws {
    let backend = ScriptedStreamingBackend(responses: [
      ScriptedResponse(deltas: ["Hel", "lo"], ending: .completed(completionTokens: 7))
    ])
    let recorder = RecordingCallbacks()

    _ = backend.generateStream(request: .probe, callbacks: recorder)
    try await recorder.waitForTerminal()

    #expect(recorder.chunks.map(\.delta) == ["Hel", "lo", ""])
    // Clause 1: exactly one `isFinal` chunk, and it is last.
    #expect(recorder.chunks.map(\.isFinal) == [false, false, true])
    #expect(recorder.chunks.last?.completionTokens == 7)
    #expect(recorder.terminals.count == 1)
    #expect(recorder.terminals.first is TerminalStatusCompleted)
  }

  @Test("a suspended call carries no final chunk and exactly one Suspended")
  func suspendedShape() async throws {
    let backend = ScriptedStreamingBackend(responses: [
      ScriptedResponse(deltas: ["par"], ending: .suspended)
    ])
    let recorder = RecordingCallbacks()

    _ = backend.generateStream(request: .probe, callbacks: recorder)
    try await recorder.waitForTerminal()

    // Clause 1's "suspended/failed carry none": the partial delta arrives, but
    // nothing claims finality — the call was cut off, not finished.
    #expect(recorder.chunks.map(\.delta) == ["par"])
    #expect(recorder.chunks.allSatisfy { !$0.isFinal })
    #expect(recorder.terminals.count == 1)
    #expect(recorder.terminals.first is TerminalStatusSuspended)
  }

  @Test("a failed call reports its code and message once")
  func failedShape() async throws {
    let backend = ScriptedStreamingBackend(responses: [
      ScriptedResponse(deltas: [], ending: .failed(errorCode: "spike.boom", message: "detail"))
    ])
    let recorder = RecordingCallbacks()

    _ = backend.generateStream(request: .probe, callbacks: recorder)
    try await recorder.waitForTerminal()

    #expect(recorder.chunks.isEmpty)
    #expect(recorder.terminals.count == 1)
    let failed = try #require(recorder.terminals.first as? TerminalStatusFailed)
    #expect(failed.errorCode == "spike.boom")
    #expect(failed.message == "detail")
  }

  @Test("a call past the end of the script fails rather than trapping")
  func scriptExhaustion() async throws {
    let backend = ScriptedStreamingBackend(responses: [])
    let recorder = RecordingCallbacks()

    _ = backend.generateStream(request: .probe, callbacks: recorder)
    try await recorder.waitForTerminal()

    let failed = try #require(recorder.terminals.first as? TerminalStatusFailed)
    #expect(failed.errorCode == ScriptedStreamingBackend.scriptExhaustedErrorCode)
  }

  // MARK: - §5.2 clause 4 — serial delivery

  @Test("callbacks never overlap, even when several calls are in flight")
  func callbacksAreSerialPerCall() async throws {
    // Clause 4 is per-call: `LLMCaller` accumulates deltas into plain fields
    // for the call it issued. Two concurrent calls get two recorders, and each
    // recorder asserts it is never re-entered — which is what would corrupt
    // the accumulation.
    let backend = ScriptedStreamingBackend(responses: [
      ScriptedResponse(
        deltas: Array(repeating: "a", count: 40), ending: .completed(completionTokens: nil),
        chunkDelay: .milliseconds(1)),
      ScriptedResponse(
        deltas: Array(repeating: "b", count: 40), ending: .completed(completionTokens: nil),
        chunkDelay: .milliseconds(1))
    ])
    let first = RecordingCallbacks()
    let second = RecordingCallbacks()

    _ = backend.generateStream(request: .probe, callbacks: first)
    _ = backend.generateStream(request: .probe, callbacks: second)
    try await first.waitForTerminal()
    try await second.waitForTerminal()

    #expect(first.maxConcurrentEntries == 1)
    #expect(second.maxConcurrentEntries == 1)
    #expect(first.chunks.count == 41)
    #expect(second.chunks.count == 41)
    #expect(backend.callCount == 2)
  }

  // MARK: - §5.2 clause 3 — cancellation composition

  @Test("cancel() stops the backing task and delivers no terminal")
  func cancellationStopsTheBackingTask() async throws {
    let backend = ScriptedStreamingBackend(responses: [
      ScriptedResponse(
        deltas: Array(repeating: "tok", count: 50), ending: .completed(completionTokens: nil),
        chunkDelay: .milliseconds(20))
    ])
    let recorder = RecordingCallbacks()

    let handle = backend.generateStream(request: .probe, callbacks: recorder)
    try await recorder.waitForChunk(atLeast: 1)
    handle.cancel()

    try await pollUntil { backend.observedCancellations == 1 }
    let deliveredAtCancel = recorder.chunks.count

    // The negative control for "the task really stopped": if `cancel()` had not
    // reached the Task, this 20-chunk window would have delivered ~20 more.
    try await Task.sleep(for: .milliseconds(400))
    #expect(recorder.chunks.count - deliveredAtCancel <= 1)
    #expect(recorder.terminals.isEmpty)
  }

  @Test("cancel() is idempotent and safe after the stream already ended")
  func cancellationAfterCompletionIsHarmless() async throws {
    let backend = ScriptedStreamingBackend(responses: [
      ScriptedResponse(deltas: ["x"], ending: .completed(completionTokens: nil))
    ])
    let recorder = RecordingCallbacks()

    let handle = backend.generateStream(request: .probe, callbacks: recorder)
    try await recorder.waitForTerminal()
    handle.cancel()
    handle.cancel()

    // The common case per `StreamHandle.cancel`'s doc: a cancelled coroutine
    // whose stream had already completed. It must not retract the terminal or
    // add a cancellation.
    #expect(recorder.terminals.count == 1)
    #expect(backend.observedCancellations == 0)
  }

  // MARK: - §5.1 — event ordering and terminal delivery

  @Test("the reconstructed stream ends on the terminal event and then finishes")
  func eventStreamTerminatesOnTerminalEvent() async throws {
    let runner = SharedEngineRunner()
    let backend = ScriptedStreamingBackend(responses: [.says("Hello"), .says("Hi")])

    var events: [SimulationEvent] = []
    for await event in runner.run(scenario: .oneSpeakAllTurn, backend: backend) {
      events.append(event)
    }

    // The `for await` returning at all is the assertion that matters: an
    // adapter that forwarded events but never called `finish()` would hang
    // here rather than fail.
    let terminals = events.filter(\.isTerminal)
    #expect(terminals.count == 1)
    #expect(events.last is SimulationEvent.SimulationCompleted)
    // One round × two agents.
    #expect(backend.callCount == 2)
  }

  @Test("breaking out of the stream cancels the Kotlin run")
  func earlyTerminationCancelsTheRun() async throws {
    let runner = SharedEngineRunner()
    // Paced so the run is provably mid-flight when the consumer walks away —
    // an instant script can finish before `break` lands, which would make this
    // test pass without exercising cancellation at all.
    let backend = ScriptedStreamingBackend(
      responses: Array(
        repeating: .says("turn", chunkDelay: .milliseconds(30)), count: 4))

    for await _ in runner.run(scenario: .twoSpeakAllTurns, backend: backend) {
      break
    }

    // `onTermination` → `RunHandle.cancel()` → Kotlin cancels the coroutine →
    // `invokeOnCancellation` → `StreamHandle.cancel()` → the Swift task stops.
    // Observing the *far* end of that chain is what makes this a composition
    // test rather than a "did we call cancel" test.
    try await pollUntil { backend.observedCancellations >= 1 }
    #expect(backend.observedCancellations >= 1)
  }

  // MARK: - §5.2 suspension relay

  @Test("a suspended call is re-issued after resume, and the run completes")
  func suspensionRelayRoundTrip() async throws {
    let controller = SuspendController()
    let runner = SharedEngineRunner(suspendController: controller)
    // Call 1 is cut off by the platform; call 2 is the re-issue of the same
    // prompt after resume.
    let backend = ScriptedStreamingBackend(responses: [
      ScriptedResponse(deltas: [], ending: .suspended),
      .says("Hello"),
      .says("Hi")
    ])

    controller.requestSuspend()

    let collected = Mutex<[SimulationEvent]>([])
    let consumer = Task {
      for await event in runner.run(scenario: .oneSpeakAllTurn, backend: backend) {
        collected.withLock { $0.append(event) }
      }
    }

    // Wait until the engine has actually parked on the suspension before
    // resuming — resuming first would let the run complete without the relay
    // ever being exercised, and the test would still pass.
    try await pollUntil { backend.callCount == 1 }
    controller.resume()

    // Poll for the terminal event rather than awaiting the consumer task.
    // `await consumer.value` cannot be rescued by the suite's time limit: the
    // task is unstructured, so cancelling the test task neither propagates to
    // it nor makes a non-throwing `.value` return — a broken relay would wedge
    // the whole run instead of failing. Verified by deleting
    // `notifyLLMResumed()`: the awaiting form hung past 400s, this one fails.
    try await pollUntil { collected.withLock { $0.last } is SimulationEvent.SimulationCompleted }
    consumer.cancel()

    let events = collected.withLock { $0 }
    #expect(events.last is SimulationEvent.SimulationCompleted)
    // Invariant 1, as far as it is observable here: the suspend cycle cost one
    // extra *call*, not a retry-budget slot — two turn calls plus the one
    // re-issue. Had it consumed budget, the remaining scripted responses could
    // not have carried the run to completion.
    #expect(backend.callCount == 3)
  }

  @Test("a resume latched before the run starts still completes it")
  func resumeLatchedBeforeTheRunStartsStillCompletes() async throws {
    // What this pins, precisely: `resume()` landing before `run` is even
    // called. `SuspendController` latches `.resumed`, the first call still
    // ends `.suspended`, and the relay's `awaitResume()` returns immediately —
    // a different path through the relay than `suspensionRelayRoundTrip`,
    // which resumes mid-run.
    //
    // What it does NOT pin, stated because two earlier revisions claimed
    // otherwise: it does not exercise `RunHandleBox`'s resume latch. MEASURED
    // — deleting `pendingResume` leaves this test passing and fails only
    // `RunHandleBoxLatchTests`. `store(handle)` runs a few instructions after
    // `engine.run` returns, while reaching a `.suspended` terminal costs
    // several async hops, so the empty-box window is not reachable from here
    // at any schedule this suite can express. The unit tests are where that
    // window is pinned; this is a relay-path test, not a race test.
    let controller = SuspendController()
    let runner = SharedEngineRunner(suspendController: controller)
    let backend = ScriptedStreamingBackend(responses: [
      ScriptedResponse(deltas: [], ending: .suspended),
      .says("Hello"),
      .says("Hi")
    ])

    controller.requestSuspend()
    // Resume BEFORE the run exists. `SuspendController` latches `.resumed`, so
    // the first call still ends `.suspended` and the relay still fires — but
    // now with no guarantee that the handle has been stored.
    controller.resume()

    let collected = Mutex<[SimulationEvent]>([])
    let consumer = Task {
      for await event in runner.run(scenario: .oneSpeakAllTurn, backend: backend) {
        collected.withLock { $0.append(event) }
      }
    }

    // Polled, not awaited — same reason as the round-trip test above.
    try await pollUntil { collected.withLock { $0.last } is SimulationEvent.SimulationCompleted }
    consumer.cancel()

    // The assertions the previous version lacked. `pollUntil` throwing on
    // timeout already covers the park-forever case, but these pin that the
    // suspended call was genuinely re-issued rather than skipped: one
    // suspended call plus two agent turns.
    #expect(backend.callCount == 3)
    #expect(collected.withLock { $0.last } is SimulationEvent.SimulationCompleted)
  }

  /// The Swift half of §5.2 invariant 3, tested where it is deterministic.
  ///
  /// `SimulationEngine.run` launches the run loop before returning the handle, so
  /// a `.suspended` terminal can drive the relay while `SharedEngineRunner` has
  /// not stored the handle yet. The end-to-end tests cannot force that interleave
  /// — they can only sample whatever the scheduler gives them — but the box that
  /// closes it is a plain object, so the window can be reproduced exactly by
  /// signalling before `store`.
  @Suite("run-handle latch", .timeLimit(.minutes(1)))
  struct RunHandleBoxLatchTests {

    @Test("a resume arriving before the handle is replayed, not dropped")
    func resumeBeforeStoreIsReplayed() {
      let box = RunHandleBox()
      let handle = RecordingRunHandle()

      box.notifyResumed()
      #expect(handle.resumeSignals == 0, "nothing to deliver to yet")

      box.store(handle)
      #expect(handle.resumeSignals == 1, "the latched resume must fire on store")
    }

    @Test("a cancel arriving before the handle is replayed, not dropped")
    func cancelBeforeStoreIsReplayed() {
      let box = RunHandleBox()
      let handle = RecordingRunHandle()

      box.cancel()
      box.store(handle)

      #expect(handle.cancels == 1, "an early consumer break must still tear the run down")
    }

    @Test("signals arriving after the handle go straight through")
    func signalsAfterStorePassThrough() {
      let box = RunHandleBox()
      let handle = RecordingRunHandle()

      box.store(handle)
      box.notifyResumed()
      box.cancel()

      #expect(handle.resumeSignals == 1)
      #expect(handle.cancels == 1)
    }

    @Test("a latched signal fires once, not on every later store")
    func latchIsClearedOnReplay() {
      let box = RunHandleBox()
      let first = RecordingRunHandle()
      let second = RecordingRunHandle()

      box.notifyResumed()
      box.store(first)
      box.store(second)

      #expect(first.resumeSignals == 1)
      #expect(second.resumeSignals == 0, "the latch must not re-fire")
    }

    @Test("both signals latched together are replayed resume-then-cancel")
    func bothLatchedReplayInOrder() {
      // `store(_:)` documents this ordering, and a doc-stated ordering with no
      // test is exactly the assertion class this review round was convened to
      // clean up: swapping the two replay lines passes every other test here.
      let box = RunHandleBox()
      let handle = RecordingRunHandle()

      box.notifyResumed()
      box.cancel()
      box.store(handle)

      #expect(handle.log == ["resume", "cancel"])
    }
  }

  /// A decorator must surface the wrapped backend's pair, not the ChatML value
  /// Kotlin's interface default would have supplied (#1472).
  ///
  /// Without the injected pair this assertion could not exist: every conformer
  /// in the package answers ChatML, so a decorator that hardcoded it would be
  /// indistinguishable from one that forwards — and would go wrong only at
  /// Stage 5, where the leaf becomes `LlamaCppService` and reports its model's
  /// own pair.
  /// The arm that crosses the boundary. Kotlin reads `knownTurnMarkers` off
  /// the backend it was handed — `SuspensionRelayingBackend`, the permanent
  /// §10 adapter — and keys #1422 truncation on it, so a decorator answering
  /// ChatML instead lets the hallucinated continuation through. Nothing in
  /// Swift observes that; only a run does.
  ///
  /// Fixture byte-identical to `JSONResponseParserTurnMarkerTests`'
  /// `fencedHallucination`, whose own negative control fixes both outcomes:
  /// the Gemma pair yields `本物`, ChatML-only yields `偽物`.
  @Test("Kotlin truncates on the markers the relaying decorator forwards")
  func kotlinTruncatesOnForwardedTurnMarkers() async throws {
    let fencedHallucination = """
      {"statement": "本物", "action": "cooperate"}<turn|>
      <|turn>user
      もう一度
      <turn|>
      <|turn>model
      ```json
      {"statement": "偽物", "action": "betray"}
      ```
      """
    let runner = SharedEngineRunner()
    let backend = ScriptedStreamingBackend(
      responses: Array(
        repeating: ScriptedResponse(
          deltas: [fencedHallucination], ending: .completed(completionTokens: nil)),
        count: 2),
      knownTurnMarkers: [
        ChatTurnMarkers(start: "<|turn>", end: "<turn|>"), ChatTurnMarkers.companion.chatML
      ])

    var statements: [String] = []
    for await event in runner.run(scenario: .oneSpeakAllTurn, backend: backend) {
      if let agentOutput = event as? SimulationEvent.AgentOutput {
        statements.append(agentOutput.output.statement ?? "")
      }
    }

    #expect(statements == ["本物", "本物"])
  }

  @Test("a decorator forwards the wrapped backend's turn markers")
  func decoratorForwardsKnownTurnMarkers() {
    // The union form `LLMBackend.knownTurnMarkers` documents — a model's own
    // pair *plus* ChatML — so the fixture is a value a real backend could
    // report. Differing from ChatML is all the assertion needs; excluding it
    // would have discriminated just as well while modelling an illegal one.
    let pair = [
      ChatTurnMarkers(start: "<|turn>", end: "<turn|>"), ChatTurnMarkers.companion.chatML
    ]
    let leaf = ScriptedStreamingBackend(responses: [], knownTurnMarkers: pair)
    let decorated = ThreadObservingBackend(wrapping: leaf, recordingInto: ThreadObservations())

    #expect(decorated.knownTurnMarkers == pair)
  }
}

/// Records what the latch delivers, **in order** — counts alone cannot express
/// `store(_:)`'s resume-before-cancel replay claim.
///
/// `RunHandle` is a Kotlin/Native protocol, so this is also one more instance
/// of the shim class measurement (iii) counts.
///
/// Plain `Sendable`, not `@unchecked`: the only stored property is a `let
/// Mutex`, so the compiler can check it. `@unchecked` here would silently
/// exempt any property a later edit adds.
nonisolated private final class RecordingRunHandle: RunHandle, Sendable {
  private let calls = Mutex<[String]>([])

  /// Delivery order, e.g. `["resume", "cancel"]`.
  var log: [String] { calls.withLock { $0 } }

  var resumeSignals: Int { log.filter { $0 == "resume" }.count }
  var cancels: Int { log.filter { $0 == "cancel" }.count }

  func pause() {}
  func resume() {}
  func cancel() { calls.withLock { $0.append("cancel") } }
  func notifyLLMResumed() { calls.withLock { $0.append("resume") } }
}

// MARK: - Helpers

/// Records everything a backend delivers, and detects any overlap.
///
/// `maxConcurrentEntries` is the §5.2 clause-4 assertion. A plain array plus a
/// lock would make a concurrency bug *invisible* — the lock would serialize the
/// very overlap the clause forbids. The entry counter is what notices.
nonisolated final class RecordingCallbacks: StreamCallbacks, @unchecked Sendable {
  /// Carries `any TerminalStatus` into the mutex-guarded state.
  ///
  /// Another instance of the shim measurement (iii) counts: a Kotlin protocol
  /// existential has no Swift `Sendable` conformance and cannot be given one,
  /// so storing it behind a `Mutex` — whose `withLock` takes `inout sending` —
  /// needs a concrete wrapper.
  private struct TerminalBox: @unchecked Sendable {
    let value: any TerminalStatus
  }

  private struct State {
    var chunks: [ScriptedChunk] = []
    var terminals: [TerminalBox] = []
    var entered = 0
    var maxEntered = 0
  }

  private let state = Mutex(State())

  var chunks: [ScriptedChunk] { state.withLock { $0.chunks } }
  var terminals: [any TerminalStatus] { state.withLock { $0.terminals }.map(\.value) }
  var maxConcurrentEntries: Int { state.withLock { $0.maxEntered } }

  func onChunk(delta: String, isFinal: Bool, completionTokens: KotlinInt?) {
    enter()
    state.withLock {
      $0.chunks.append(
        ScriptedChunk(
          delta: delta, isFinal: isFinal,
          completionTokens: completionTokens.map { Int($0.int32Value) }))
    }
    leave()
  }

  func onTerminal(status: any TerminalStatus) {
    enter()
    let boxed = TerminalBox(value: status)
    state.withLock { $0.terminals.append(boxed) }
    leave()
  }

  func waitForTerminal() async throws {
    try await pollUntil { !self.terminals.isEmpty }
  }

  func waitForChunk(atLeast count: Int) async throws {
    try await pollUntil { self.chunks.count >= count }
  }

  private func enter() {
    state.withLock {
      $0.entered += 1
      $0.maxEntered = max($0.maxEntered, $0.entered)
    }
    // Widen the window a genuine overlap would land in. Without this the two
    // callbacks could interleave and still never be *simultaneously* inside.
    Thread.sleep(forTimeInterval: 0.0005)
  }

  private func leave() {
    state.withLock { $0.entered -= 1 }
  }
}

/// Polls `condition` until it holds, or fails the test on timeout.
///
/// The boundary is callback-driven across a Kotlin worker context, so there is
/// no continuation to await — polling is the honest primitive. A generous
/// timeout keeps CI's slower, contended runners from reading as contract
/// violations.
func pollUntil(
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

extension GenerationRequest {
  /// A request whose content no assertion depends on.
  ///
  /// `antiRepetitionSeeds:` is passed explicitly even though Kotlin declares a
  /// default: K/N exports carry no default-argument values, so the generated
  /// initializer requires every parameter (`.claude/rules/kmp-interop.md`
  /// Pattern 3). Adding a Kotlin property with a default is therefore a
  /// **source-breaking** change on this side.
  static var probe: GenerationRequest {
    GenerationRequest(system: "system", user: "user", schema: nil, antiRepetitionSeeds: [])
  }
}

extension ScriptedResponse {
  /// A completed response carrying one `speak_all` turn's JSON.
  static func says(_ text: String, chunkDelay: Duration? = nil) -> ScriptedResponse {
    ScriptedResponse(
      deltas: ["{\"statement\": \"\(text)\"}"],
      ending: .completed(completionTokens: nil),
      chunkDelay: chunkDelay
    )
  }
}

extension Scenario {
  /// The minimal scenario the gate slice supports: `speak_all`, one phase.
  ///
  /// **Two agents is the floor, not a choice.** The run loop ends a round
  /// early when fewer than two agents are active (`SimulationEngine.kt`, the
  /// `activeCount < 2` guard), so a single-agent scenario reaches
  /// `SimulationCompleted` having issued **zero** LLM calls — it looks like a
  /// clean run and exercises nothing. `speak_all` then issues one call per
  /// agent per round, so call count is `rounds × 2` throughout.
  ///
  /// Every parameter is spelled out because Kotlin/Native does not export
  /// default arguments — one of the ergonomics costs measurement (i) reports.
  static func speakAll(rounds: Int32) -> Scenario {
    Scenario(
      id: "t",
      name: "T",
      description: "d",
      language: "en",
      simulationLanguage: nil,
      agentCount: 2,
      rounds: rounds,
      logWindow: nil,
      context: "A test.",
      personas: [
        Persona(name: "Alice", description: "Alice's persona.", secret: nil),
        Persona(name: "Bob", description: "Bob's persona.", secret: nil)
      ],
      phases: [
        Phase(
          type: PhaseType.speakAll, prompt: "Speak.", outputSchema: ["statement": "string"],
          options: nil, pairing: nil, logic: nil, template: nil, source: nil, target: nil,
          excludeSelf: nil, subRounds: nil, maxSentences: nil, condition: nil, thenPhases: nil,
          elsePhases: nil, probability: nil, eventVariable: nil,
          voteAgainst: nil, actionDeltas: nil, noRepeat: nil, narrator: nil, payoff: nil)
      ],
      extraData: [:]
    )
  }

  /// One agent turn — the smallest run that reaches `SimulationCompleted`.
  static var oneSpeakAllTurn: Scenario { speakAll(rounds: 1) }

  /// Two rounds, so a consumer can walk away while the run is still going.
  static var twoSpeakAllTurns: Scenario { speakAll(rounds: 2) }
}
