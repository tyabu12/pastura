import Foundation
import PasturaSharedEngine
import Synchronization

/// ADR-023 §6 measurement (ii) — what the inference boundary costs at runtime.
///
/// Two figures, both taken against the real Kotlin engine rather than a Swift
/// stand-in, because the number that matters is the *crossing*:
///
/// - **Per-chunk relay overhead.** Taken differentially: the same run is timed
///   with a long script and with a short one, and the per-chunk cost is the
///   slope between them. A single absolute timing would fold in engine setup,
///   scenario construction, and the run loop — all of which are paid once and
///   none of which are the boundary.
/// - **Suspension round-trip.** Wall time from `resume()` to the re-issued
///   inference call, i.e. the full `SuspendController` → relay task →
///   `notifyLLMResumed()` → Kotlin park release → new `generateStream` path.
///
/// **Host-bound.** ADR-023 §6 marks only this measurement's *absolutes* as
/// host-sensitive. These are macOS-host figures; iOS-device absolutes belong to
/// Stage-5 QA. The abort criteria do not turn on them — §5.2 already frames
/// per-chunk crossing at 10–50 tok/s as orders of magnitude below K/N
/// call-overhead concern, and what this measurement can do is falsify that.
public enum RelayBenchmark {

  /// One timing, with the sample count that produced it.
  public struct Timing: Sendable {
    public let samples: Int
    /// Fastest observed — the least contaminated by scheduler noise.
    public let best: Duration
    /// Median, reported alongside so a suspiciously fast `best` is visible.
    public let median: Duration
  }

  public struct Result: Sendable {
    public let shortScriptRun: Timing
    public let longScriptRun: Timing
    public let chunksPerShortRun: Int
    public let chunksPerLongRun: Int
    public let suspensionRoundTrip: Timing

    /// Slope between the two script lengths — the marginal cost of one chunk
    /// crossing Swift → Kotlin.
    public var perChunkOverhead: Duration {
      let extra = chunksPerLongRun - chunksPerShortRun
      guard extra > 0 else { return .zero }
      return (longScriptRun.best - shortScriptRun.best) / extra
    }

    /// Token rate the per-chunk figure implies if crossing were the only cost.
    ///
    /// Context for §5.2's "orders of magnitude below concern": real generation
    /// runs at 10–50 tok/s, so this number should be enormous by comparison.
    public var impliedCeilingTokensPerSecond: Double {
      let seconds =
        Double(perChunkOverhead.components.attoseconds) / 1e18
        + Double(perChunkOverhead.components.seconds)
      guard seconds > 0 else { return .infinity }
      return 1 / seconds
    }
  }

  /// Runs both measurements.
  public static func run(iterations: Int = 7) async throws -> Result {
    let shortChunks = 1
    let longChunks = 40

    let shortTiming = try await time(iterations: iterations) {
      try await timeOneRun(deltasPerCall: shortChunks)
    }
    let longTiming = try await time(iterations: iterations) {
      try await timeOneRun(deltasPerCall: longChunks)
    }
    let suspension = try await time(iterations: iterations) {
      try await timeSuspensionRoundTrip()
    }

    // One `speak_all` round over two agents = two calls, each carrying the
    // scripted deltas plus the final chunk.
    return Result(
      shortScriptRun: shortTiming,
      longScriptRun: longTiming,
      chunksPerShortRun: (shortChunks + 1) * 2,
      chunksPerLongRun: (longChunks + 1) * 2,
      suspensionRoundTrip: suspension
    )
  }

  /// Times one full engine run whose calls each carry `deltasPerCall` chunks.
  private static func timeOneRun(deltasPerCall: Int) async throws -> Duration {
    let runner = SharedEngineRunner()
    let backend = ScriptedStreamingBackend(
      responses: Array(repeating: .benchTurn(deltas: deltasPerCall), count: 2))

    let clock = ContinuousClock()
    let start = clock.now
    for await _ in runner.run(scenario: .benchSpeakAll, backend: backend) {}
    return clock.now - start
  }

  /// Times `resume()` → the re-issued call landing at the backend.
  private static func timeSuspensionRoundTrip() async throws -> Duration {
    let controller = SuspendController()
    let runner = SharedEngineRunner(suspendController: controller)
    let backend = ScriptedStreamingBackend(responses: [
      ScriptedResponse(deltas: [], ending: .suspended),
      .benchTurn(deltas: 1),
      .benchTurn(deltas: 1)
    ])

    controller.requestSuspend()
    let consumer = Task {
      for await _ in runner.run(scenario: .benchSpeakAll, backend: backend) {}
    }
    defer { consumer.cancel() }

    // Wait for the suspended call to have reached the backend before starting
    // the clock. This is a lower bound by construction: if `resume()` lands
    // before Kotlin has finished parking, `SuspendController` latches and the
    // relay fires on arrival, so the figure can under-report the park/unpark
    // half. It never over-reports.
    try await poll("the first call to reach the backend") { backend.callCount >= 1 }

    let clock = ContinuousClock()
    let start = clock.now
    controller.resume()
    // `>=`, not `==`. The re-issued call and the second agent's call both land
    // unpaced, so an exact-equality wait can step straight over 2 between polls
    // and never observe it — which reads as "the relay is broken" while the run
    // completes normally behind it. Measured: instrumenting the event stream
    // showed a full SimulationCompleted while this poll was still waiting.
    try await poll("the re-issued call") { backend.callCount >= 2 }
    return clock.now - start
  }

  private static func time(
    iterations: Int,
    _ body: () async throws -> Duration
  ) async rethrows -> Timing {
    var samples: [Duration] = []
    for _ in 0..<iterations {
      samples.append(try await body())
    }
    samples.sort()
    return Timing(
      samples: iterations,
      best: samples[0],
      median: samples[samples.count / 2])
  }

  /// Polls until `condition` holds. Throws rather than hanging — an unbounded
  /// wait here would wedge the CI step instead of reporting a broken relay.
  private static func poll(
    _ label: String,
    timeout: Duration = .seconds(10),
    _ condition: @Sendable () -> Bool
  ) async throws {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while ContinuousClock.now < deadline {
      if condition() { return }
      try await Task.sleep(for: .milliseconds(1))
    }
    throw RelayBenchmarkError.timedOut(label)
  }
}

/// Why a benchmark could not complete.
public enum RelayBenchmarkError: Error, CustomStringConvertible {
  /// The run never reached the state the benchmark was waiting for.
  case timedOut(String)

  public var description: String {
    {
    guard case .timedOut(let label) = self else { return "" }
    return "relay benchmark timed out waiting for \(label)"
  }()
  }
}

extension ScriptedResponse {
  /// A completed turn carrying `deltas` non-final chunks before its final one.
  ///
  /// Unpaced on purpose: `chunkDelay` would measure the sleep, not the
  /// crossing. The JSON is split so the deltas are real accumulation work for
  /// Kotlin's `LLMCaller` rather than discardable noise.
  static func benchTurn(deltas: Int) -> ScriptedResponse {
    var pieces = ["{\"statement\": \""]
    pieces.append(contentsOf: Array(repeating: "tok ", count: max(0, deltas - 2)))
    pieces.append("done\"}")
    return ScriptedResponse(
      deltas: pieces,
      ending: .completed(completionTokens: nil),
      chunkDelay: nil)
  }
}

extension Scenario {
  /// Two agents, one round — the floor that still issues LLM calls.
  ///
  /// The run loop ends a round early below two active agents, so a
  /// single-agent scenario would complete having issued none, and every
  /// figure here would be measuring an empty run.
  ///
  /// Every argument is spelled out because Kotlin/Native does not export
  /// default arguments — itself one of the measurement (i) ergonomics costs.
  static var benchSpeakAll: Scenario {
    Scenario(
      id: "bench",
      name: "Bench",
      description: "d",
      language: "en",
      simulationLanguage: nil,
      agentCount: 2,
      rounds: 1,
      logWindow: nil,
      context: "A benchmark.",
      personas: [
        Persona(name: "Alice", description: "Alice's persona.", secret: nil),
        Persona(name: "Bob", description: "Bob's persona.", secret: nil)
      ],
      phases: [
        Phase(
          type: PhaseType.speakAll, prompt: "Speak.", outputSchema: ["statement": "string"],
          options: nil, pairing: nil, logic: nil, template: nil, source: nil, target: nil,
          excludeSelf: nil, subRounds: nil, maxSentences: nil, condition: nil, thenPhases: nil,
          elsePhases: nil, probability: nil, eventVariable: nil)
      ],
      extraData: [:]
    )
  }
}
