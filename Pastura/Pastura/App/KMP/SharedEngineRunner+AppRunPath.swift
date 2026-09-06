import Foundation
import OSLog
import PasturaSharedEngine

// Kotlin types with a Swift twin in this module are spelled
// `PasturaSharedEngine.X` — a bare name binds to the Swift twin
// (`.claude/rules/kmp-interop.md` Pattern 1b). No typealias: an alias would
// hide the shadowing from the next reader.

// `nonisolated` on every member, restated rather than inherited: a type's
// `nonisolated` governs the members declared in its *body*, and this file is a
// sibling-file extension under `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so
// its members default to `@MainActor`. Measured: without it the `AsyncStream`
// build closure below is MainActor-isolated and traps in
// `swift_task_isCurrentExecutor` the first time a nonisolated caller (the test
// suite, and post-S5-4 the off-main run path) reaches it.
extension SharedEngineRunner {

  /// Runs `yaml` on the Kotlin engine and returns the **Swift**
  /// `SimulationEvent` stream `SimulationViewModel` already knows how to
  /// consume — the S5-4 app run path (ADR-023 §6, #1681).
  ///
  /// Since S5-5 this overload — not
  /// `SimulationRunner.run(scenario:llm:suspendController:)` — serves every
  /// production fresh run.
  /// It owns the parse (so a scenario the Kotlin loader rejects arrives as a
  /// `.error(.scenarioValidationFailed)` event rather than a `throws` the
  /// ViewModel has no arm for) and the Kotlin→Swift event translation, leaving
  /// the App-facing surface identical to the Swift runner's.
  ///
  /// **App-module-only by construction — deliberately not mirrored into
  /// `tools/kmp-gate-spike`.** `kmp-interop.md` requires an adapter's
  /// export-facing shape to land in the spike too; that does not apply here,
  /// because both of this overload's own types — the Swift `SimulationEvent`
  /// enum and `LLMService` — have no twin in the spike, which declares neither.
  /// A mirror would have to invent both and would then be testing the
  /// invention. The Kotlin-facing half it delegates to,
  /// ``SharedEngineRunner/run(scenario:backend:)``, *is* mirrored.
  ///
  /// **No resume-from-state.** The Swift runner takes `resumingFrom:` /
  /// `startRound:`; the Kotlin engine exports no seeded-start entry point, so
  /// this path serves **fresh runs only** and `SimulationViewModel.resume`
  /// stays on the Swift runner regardless of the flag.
  ///
  /// **One runner per run.** The `SuspendController` driving the §5.2
  /// suspension relay is the one this runner was constructed with, not a
  /// per-call argument, so the app builds a `SharedEngineRunner` per run rather
  /// than sharing one across runs.
  ///
  /// - Parameters:
  ///   - yaml: The scenario source, parsed by `PasturaSharedEngine.ScenarioLoader`.
  ///   - llm: The inference service, wrapped in ``LLMServiceBackend``.
  /// - Returns: An `AsyncStream` finishing on the run's terminal event, or —
  ///   for a scenario that failed to parse — after a single `.error` event.
  nonisolated func run(yaml: String, llm: any LLMService) -> AsyncStream<SimulationEvent> {
    let scenario: PasturaSharedEngine.Scenario
    do {
      scenario = try PasturaSharedEngine.ScenarioLoader().load(yaml: yaml)
    } catch {
      let message = Self.renderedValidationMessage(for: error)
      return AsyncStream { continuation in
        continuation.yield(.error(.scenarioValidationFailed(message)))
        continuation.finish()
      }
    }

    let inner = run(scenario: scenario, backend: LLMServiceBackend(service: llm))
    return AsyncStream { continuation in
      // A `Task` rather than consuming inline so consumer cancellation can be
      // propagated: `onTermination` cancels this task, which tears down the
      // inner stream's iteration and fires *its* `onTermination` →
      // `RunHandle.cancel()`. Mirrors the shape of
      // `SimulationRunner.run(scenario:llm:suspendController:)`.
      let task = Task {
        var sawTerminal = false
        for await event in inner {
          guard let translated = SimulationEvent(shared: event) else {
            // A Kotlin subclass this build predates
            // (`SimulationEvent+SharedEngine.swift`). Dropped rather than
            // fatal, so a Kotlin bump cannot crash a shipped app — but never
            // silently: only the Kotlin class name is logged, because event
            // payloads carry scenario and agent text (CLAUDE.md § Logger
            // privacy).
            Self.logger.error(
              "dropping an unmappable Kotlin event: \(String(describing: type(of: event)), privacy: .public)"
            )
            continue
          }
          if case .simulationCompleted = translated { sawTerminal = true }
          if case .error = translated { sawTerminal = true }
          continuation.yield(translated)
        }
        // The contract above promises a terminal; if the one Kotlin emitted
        // was the unmappable event just dropped, floor it so the ViewModel
        // does not read a bare stream end as a normal completion.
        if !sawTerminal, !Task.isCancelled {
          continuation.yield(
            .error(
              .llmGenerationFailed(
                description: String(
                  localized: "The shared engine ended without a result."))))
        }
        continuation.finish()
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  /// The Kotlin-**rendered** message behind a `ScenarioLoader.load` throw.
  ///
  /// `localizedDescription` on the bridged `NSError` is the *exception
  /// description* (`SimulationException: …`), not the rendered catalog
  /// message; the S5-4 `ja` acceptance reads the rendered one, so the Kotlin
  /// throwable is unwrapped from `userInfo["KotlinException"]` and its
  /// `SimulationError` mapped through ``SimulationError/init(shared:)``
  /// instead. The fallback covers a throwable that is not a
  /// `SimulationException` at all — nothing K/N exports here should produce
  /// one, so it is a shape guard, not an expected path.
  ///
  /// Not `private`: `SharedEngineDiagnostics.sampleRenderedMessage()` reuses
  /// it for the S5-4 `ja` acceptance row, and `private` is file-scoped. Still
  /// `internal` — no wider than the rest of `App/KMP/`.
  nonisolated static func renderedValidationMessage(for error: any Error) -> String {
    guard
      let exception = (error as NSError).userInfo["KotlinException"]
        as? PasturaSharedEngine.SimulationException,
      let mapped = SimulationError(shared: exception.error)
    else {
      return error.localizedDescription
    }
    // Any `SimulationError` case can reach here in principle; the message is
    // what the App layer shows either way, so the mapped error's own
    // description is used rather than re-matching on the case.
    return mapped.errorDescription ?? error.localizedDescription
  }

  nonisolated private static let logger = Logger(
    subsystem: "app.pastura.Pastura", category: "SharedEngineRunner")
}
