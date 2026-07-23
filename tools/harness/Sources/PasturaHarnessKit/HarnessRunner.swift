import Foundation
import PasturaCore

/// Outcome summary of one harness run (up to two attempts).
package struct RunSummary: Sendable, Equatable {
  package let status: RunStatus
  package let attempts: Int
  package let durationSec: Double
  package let error: String?
}

/// Thrown by the timeout child to abort a wedged attempt.
private struct HarnessTimeoutError: Error {}

/// Drives one scenario through the Engine headlessly: streams
/// `SimulationEvent`s into JSONL lines, enforces a wall-clock timeout, and
/// retries a failed attempt exactly once with a FRESH `LLMService` — a
/// cancelled llama.cpp context is not guaranteed reusable.
package final class HarnessRunner: Sendable {
  /// Produces a fresh LLM service per attempt.
  package typealias LLMFactory = @Sendable () -> any LLMService
  /// Produces the simulation event stream — injectable for tests; the
  /// production default wraps `SimulationRunner.run`.
  package typealias StreamFactory =
    @Sendable (
      Scenario, any LLMService, SuspendController
    ) -> AsyncStream<SimulationEvent>

  private let llmFactory: LLMFactory
  private let writer: any RunLogWriting
  private let timeoutSeconds: Int
  private let streamFactory: StreamFactory
  private let progress: (@Sendable (String) -> Void)?
  /// The logger `execute` stamps the attempt on. `nil` only when a caller
  /// injects a `streamFactory` without a logger — i.e. opts out of Engine
  /// diagnostics.
  private let diagLogger: StderrEngineLogger?

  /// - Parameters:
  ///   - streamFactory: Overrides the production stream. `nil` builds one over
  ///     `SimulationRunner` wired to `diagLogger`.
  ///   - diagLogger: Receives Engine diagnostics. `nil` builds a stderr logger
  ///     when `streamFactory` is also `nil`. Injectable so a test can hold the
  ///     same instance `execute` stamps attempts on — otherwise the stamp is
  ///     unreachable from any test that supplies its own `streamFactory`.
  package init(
    llmFactory: @escaping LLMFactory,
    writer: any RunLogWriting,
    timeoutSeconds: Int,
    streamFactory: StreamFactory? = nil,
    diagLogger: StderrEngineLogger? = nil,
    progress: (@Sendable (String) -> Void)? = nil
  ) {
    self.llmFactory = llmFactory
    self.writer = writer
    self.timeoutSeconds = timeoutSeconds
    self.progress = progress

    // Resolved here rather than as a default argument: the default expression
    // cannot reference instance state, and the production stream must capture
    // the very logger `execute` stamps attempts on.
    if let streamFactory {
      self.streamFactory = streamFactory
      self.diagLogger = diagLogger
    } else {
      let logger = diagLogger ?? StderrEngineLogger()
      self.diagLogger = logger
      self.streamFactory = { scenario, llm, controller in
        // Inject a real detector so the ADR-010 Step E language-adherence
        // check is live (production wires `NLLanguageDetector` at the View
        // boundary; App/ is out of the harness sources, so the harness owns
        // its own `HarnessLanguageDetector`). Without it `language_mismatch`
        // is 0 by construction in every harness run (#1234).
        SimulationRunner(detector: HarnessLanguageDetector(), logger: logger).run(
          scenario: scenario, llm: llm, suspendController: controller)
      }
    }
  }

  /// Runs the scenario, writing `run_start` / `event` / `run_end` lines.
  /// Never throws — failures are recorded in the returned summary and the
  /// `run_end` line so a nightly batch moves on to the next scenario.
  package func execute(
    scenario: Scenario, runID: String, startDate: String, modelName: String
  ) async -> RunSummary {
    let clock = ContinuousClock()
    let started = clock.now
    try? writer.append(
      JSONL.encode(
        RunStartLine(
          runId: runID, date: startDate, scenarioId: scenario.id,
          scenarioName: scenario.name, language: scenario.language,
          model: modelName, timeoutSec: timeoutSeconds,
          estimatedInferences: ScenarioLoader.estimateInferenceCount(scenario))))

    var status = RunStatus.error
    var lastError: String?
    var attempts = 0
    for attempt in 1...2 {
      attempts = attempt
      // Stamp before the stream starts: a retried scenario replays every
      // diagnostic, and only this field separates the two passes.
      diagLogger?.beginAttempt(attempt)
      switch await runAttempt(scenario: scenario, attempt: attempt) {
      case .completed:
        status = .ok
        lastError = nil
      case .failed(let message):
        status = .error
        lastError = message
        progress?("attempt \(attempt) failed: \(message)")
      }
      if status == .ok { break }
    }

    let durationSec = Double(milliseconds: started.duration(to: clock.now))
    try? writer.append(
      JSONL.encode(
        RunEndLine(
          runId: runID, status: status, attempts: attempts,
          durationSec: durationSec, error: lastError)))
    return RunSummary(
      status: status, attempts: attempts, durationSec: durationSec,
      error: lastError)
  }

  // MARK: - Attempt machinery

  private enum AttemptOutcome: Sendable {
    case completed
    case failed(String)
  }

  private func runAttempt(scenario: Scenario, attempt: Int) async -> AttemptOutcome {
    let llm = llmFactory()
    do {
      try await llm.loadModel()
    } catch {
      return .failed("model load failed: \(error)")
    }

    let outcome: AttemptOutcome
    do {
      outcome = try await withThrowingTaskGroup(of: AttemptOutcome.self) { group in
        group.addTask {
          await self.consume(
            stream: self.streamFactory(scenario, llm, SuspendController()),
            attempt: attempt)
        }
        group.addTask {
          try await Task.sleep(for: .seconds(self.timeoutSeconds))
          throw HarnessTimeoutError()
        }
        // First child to finish wins; leaving the group cancels the other.
        guard let first = try await group.next() else {
          return .failed("task group returned no result")
        }
        group.cancelAll()
        return first
      }
    } catch is HarnessTimeoutError {
      // Ordering invariant: withThrowingTaskGroup awaits its (cancelled)
      // children before rethrowing out of the closure, so by the time this
      // catch runs the consumer has fully drained — unloadModel() below
      // cannot race an in-flight stream. Don't restructure in a way that
      // unloads before group exit.
      outcome = .failed("timeout after \(timeoutSeconds)s")
    } catch {
      outcome = .failed(String(describing: error))
    }

    try? await llm.unloadModel()
    return outcome
  }

  private func consume(
    stream: AsyncStream<SimulationEvent>, attempt: Int
  ) async -> AttemptOutcome {
    let clock = ContinuousClock()
    let started = clock.now
    var sawCompleted = false
    var streamError: String?
    for await event in stream {
      let elapsed = Double(milliseconds: started.duration(to: clock.now))
      if let line = EventLineMapper.map(event, t: elapsed, attempt: attempt) {
        do {
          try writer.append(JSONL.encode(line))
        } catch {
          return .failed("log write failed: \(error)")
        }
        progress?(line.event)
      }
      if case .simulationCompleted = event { sawCompleted = true }
      if case .error(let simulationError) = event {
        streamError = String(describing: simulationError)
      }
    }
    if sawCompleted, streamError == nil { return .completed }
    return .failed(streamError ?? "stream ended without simulation_completed")
  }
}

extension Double {
  /// Converts a `Duration` to fractional seconds (millisecond precision —
  /// plenty for run logs).
  fileprivate init(milliseconds duration: Duration) {
    let (seconds, attoseconds) = duration.components
    self = Double(seconds) + Double(attoseconds) / 1e18
  }
}
