import Foundation
import PasturaCore
import Synchronization

/// Emits the ADR-023 Stage-4 cross-language parity fixtures: for one scenario
/// and one scripted-response plan, the scenario, the exact model answers, and
/// the Swift Engine's resulting event transcript, frozen as Kotlin constants.
///
/// **Why the transcript is `EventLine`, not `SimulationEvent`.** Swift's
/// `SimulationEvent` is `Sendable, Equatable` — it has no `Codable`
/// conformance, and adding one for a harness would put a wire contract on a
/// callback-boundary type that nothing in production serializes (ADR-023 §12
/// PR0-b, and the condition-1 tag-form ruling). ``EventLineMapper`` already
/// defines this repo's transcript surface, is already reviewed, and already
/// carries a compile-time canary — so the parity harness reuses it rather than
/// authoring a second projection.
///
/// **Why it is deterministic.** `EventLineMapper.map` takes `t` and `attempt`
/// as parameters rather than reading a clock, so pinning both to zero removes
/// every timestamp and identity source from the transcript. The two events the
/// mapper drops are dropped for cause, not convenience: both engines emit
/// `agentOutputStream` whose snapshot sequence tracks the backend's chunking
/// (a per-backend, non-deterministic boundary, even though both engines now
/// run the same partial-output extractor per chunk), and both emit
/// `roundCheckpoint` carrying a full `SimulationState` whose parity the Models
/// rung already covers.
///
/// **Why the scenario crosses as JSON.** `ScenarioLoader` has no Kotlin port
/// yet (ADR-023 Stage 3), so re-parsing the YAML on the Kotlin side would
/// measure a loader that does not exist. Encoding the loaded `Scenario`
/// isolates Stage 4 from that gap; loader parity becomes its own obligation
/// when the port lands.
package enum ParityFixtureEmitter {

  /// One scenario plus the response plan that drives it.
  package struct FixtureSpec: Sendable {
    /// Kotlin constant prefix and test label.
    package let name: String
    /// Repo-relative scenario path, resolved against the current directory.
    package let scenarioPath: String
    /// What this fixture is for, carried into the generated file.
    package let purpose: String
    /// Answers replacing the derived one at a given 0-based call index — see
    /// ``RecordingResponder``. Empty for a nominal run.
    package let overrides: [Int: String]
    /// The SplitMix64 seed both engines are given (ADR-023 S3b).
    ///
    /// `nil` means the fixture draws nothing and runs on the system source,
    /// which is what every RNG-free fixture asserts by construction: with no
    /// handler drawing, the source is unobservable, so seeding it would freeze
    /// a claim the transcript cannot check. A non-`nil` seed is what a fixture
    /// exercising `assign random_one` / `event_inject` needs, so the Kotlin
    /// replay consumes the identical stream in the identical order.
    package let seed: UInt64?
    /// Cancel the run the moment a `phaseCompleted` with this `phasePath` is
    /// emitted. `nil` (the default) never cancels.
    ///
    /// **The trigger is an emitted-event position, deliberately not a backend
    /// call index.** A call-indexed cancel lands at *different logical points*
    /// on the two engines: Kotlin's `LLMCaller` observes cancellation from
    /// inside a backend call (`ensureActive()`, `suspendCancellableCoroutine`),
    /// while the Swift responder does not observe it at all — so "cancel
    /// before call N" would abort Kotlin mid-turn and Swift only at its next
    /// poll, and the transcripts would diverge about *where the harness cut*
    /// rather than about how the engines unwind.
    ///
    /// Cancelling on an emitted `phaseCompleted` removes that: both engines are
    /// at the same place when the event fires — the head of
    /// `ConditionalHandler`'s sub-phase loop is the next thing either runs, and
    /// both check there (Swift's `Task.isCancelled` poll, Kotlin's `pauseCheck`
    /// → `ensureActive()`). The path is therefore the contract; a run that
    /// never emits it fails loudly with ``ParityFixtureError/cancelTriggerNeverFired``
    /// rather than silently running to completion and freezing a golden that
    /// measures nothing.
    package let cancelAfterPhaseCompleted: [Int]?
    /// Suspend cycles to schedule before a given response index — keyed the
    /// same way as ``overrides``, the 0-based index into ``Fixture/responses``
    /// rather than a raw backend-call index.
    ///
    /// **Why a response index.** A suspend re-issue is counted in
    /// ``RecordingResponder/callCount`` but never answered, so a raw call
    /// index would drift out of step with `overrides` the moment any index
    /// scheduled a suspend. Carried into the generated Kotlin so
    /// `EngineParityTests` scripts a `TerminalStatus.Suspended` cycle before
    /// the matching answer.
    package let suspendBeforeResponse: [Int: Int]

    package init(
      name: String, scenarioPath: String, purpose: String, overrides: [Int: String] = [:],
      seed: UInt64? = nil, cancelAfterPhaseCompleted: [Int]? = nil,
      suspendBeforeResponse: [Int: Int] = [:]
    ) {
      self.name = name
      self.scenarioPath = scenarioPath
      self.purpose = purpose
      self.overrides = overrides
      self.seed = seed
      self.cancelAfterPhaseCompleted = cancelAfterPhaseCompleted
      self.suspendBeforeResponse = suspendBeforeResponse
    }
  }

  /// A completed Swift-side run, ready to freeze.
  package struct Fixture: Sendable, Equatable {
    package let name: String
    package let purpose: String
    /// The loaded `Scenario`, JSON-encoded with sorted keys.
    package let scenarioJSON: String
    /// Model answers in call order — what Kotlin's `ScriptedLLMBackend` replays.
    ///
    /// **Positional, with no per-call alignment key.** If the two engines
    /// issue different call counts mid-run, every later answer shifts and the
    /// downstream transcript diff becomes noise about alignment rather than
    /// about the engines.
    ///
    /// A parallel *tag* list (`<agent>/<phase>/<attempt>`) was once planned to
    /// localize the first drift; it is deliberately not implemented, because a
    /// tag labels the drift rather than preventing it, and localization already
    /// exists — `TranscriptComparator` sets `Report.desynced` at the first
    /// uncovered structural difference and leads its report with "fix the first
    /// one and re-run", while ``callCount`` catches the total. The real
    /// constraint, found while re-arming the structural control (#1458), is
    /// that a surplus must be **reabsorbed**: either the divergent turn is the
    /// run's last, so the extra calls fall into the replay padding, or the
    /// following indices deliberately burn a matching surplus on the other
    /// engine. Keying responses by `<agent>/<phase>/<attempt>` instead of by
    /// position would fix that; tagging would not. It is a schema change.
    package let responses: [String]
    /// One JSON object per surviving event, in emission order.
    package let transcript: [String]
    /// Backend calls the Swift Engine issued. A first-class field because a
    /// divergence where one engine retries and the other does not is a
    /// retry-count divergence the transcript alone cannot show — today the
    /// multi-object salvage, before ADR-021's Amendment the schema guard.
    package let callCount: Int
    /// The seed the Swift run was given, carried into the generated Kotlin so
    /// the replay can rebuild the same stream. `nil` for an RNG-free fixture —
    /// see ``FixtureSpec/seed``.
    package let seed: UInt64?
    /// The `phaseCompleted` path the Swift run was cancelled on, carried into
    /// the generated Kotlin so the replay cuts at the identical event. `nil`
    /// for a fixture that runs to completion — see
    /// ``FixtureSpec/cancelAfterPhaseCompleted`` for why the trigger is an
    /// event position rather than a call index.
    package let cancelAfterPhaseCompleted: [Int]?
    /// Suspend cycles delivered before a given response index, carried into
    /// the generated Kotlin so the replay scripts the same cycles at the
    /// same indices — see ``FixtureSpec/suspendBeforeResponse``. Empty for a
    /// fixture that never suspends.
    package let suspendBeforeResponse: [Int: Int]

    /// Explicit because the implicit memberwise init is `internal`, and the
    /// raw-string safety guard is tested from the sibling test module.
    package init(
      name: String, purpose: String, scenarioJSON: String,
      responses: [String], transcript: [String], callCount: Int, seed: UInt64? = nil,
      cancelAfterPhaseCompleted: [Int]? = nil, suspendBeforeResponse: [Int: Int] = [:]
    ) {
      self.name = name
      self.purpose = purpose
      self.scenarioJSON = scenarioJSON
      self.responses = responses
      self.transcript = transcript
      self.callCount = callCount
      self.seed = seed
      self.cancelAfterPhaseCompleted = cancelAfterPhaseCompleted
      self.suspendBeforeResponse = suspendBeforeResponse
    }
  }

  /// A completed run plus what the frozen ``Fixture`` deliberately leaves
  /// out: the schema each backend call declared.
  ///
  /// Kept beside the fixture rather than inside it because the golden freezes
  /// *inputs and outputs* — the schemas are an Engine-internal detail the
  /// Kotlin replay derives for itself from the same `Phase`. The tests need
  /// them to check that a hand-pinned override landed on the turn its payload
  /// answers; nothing else does.
  package struct Run: Sendable {
    /// What `parity-emit` freezes — identical to what ``run(_:)`` returns.
    package let fixture: Fixture
    /// Field names of the schema at each call index — see
    /// `RecordingResponder.recordedSchemaFields`.
    package let answeredFields: [[String]]
  }

  /// Runs one spec through the Swift Engine.
  package static func run(_ spec: FixtureSpec) async throws -> Fixture {
    try await exercise(spec).fixture
  }

  /// Runs one spec through the Swift Engine, keeping the per-call schemas.
  package static func exercise(_ spec: FixtureSpec) async throws -> Run {
    let yaml = try String(contentsOfFile: spec.scenarioPath, encoding: .utf8)
    let scenario = try ScenarioLoader().load(yaml: yaml)
    let responder = RecordingResponder(
      personas: scenario.personas.map(\.name),
      choiceOptions: try choiceOptions(in: scenario),
      overrides: spec.overrides,
      suspendBeforeResponse: spec.suspendBeforeResponse)

    // No `detector:` — deliberate, and the inverse of what `HarnessRunner` does
    // eleven files away (it injects one precisely so `language_mismatch` is not
    // 0 by construction, #1234). Two reasons it must stay omitted here:
    // `HarnessLanguageDetector` wraps `NLLanguageRecognizer`, an OS-version-
    // dependent classifier that would make the golden vary by host; and it has
    // no Kotlin counterpart yet, so any event it produced would be a divergence
    // about the harness rather than about the engines. `parityRunEmitsNoLanguageMismatch`
    // guards the omission.
    // A seeded spec must hand the Swift run the exact stream the Kotlin replay
    // rebuilds from `Fixture.seed`; an unseeded one draws nothing, so the
    // system source is unobservable and stays the default.
    let random: any RandomSource =
      spec.seed.map { SplitMix64RandomSource(seed: $0) as any RandomSource } ?? SystemRandomSource()
    let sink = Mutex(CancelSink())
    // Both the cancelling and the non-cancelling path run through the
    // `emitter:` overload, so nothing about a nominal fixture's transcript
    // depends on which arm was taken — verified by `parity-emit --check`
    // reporting no drift on the seven pre-existing fixtures when this landed.
    // The `AsyncStream` overload cannot serve the cancelling arm at all: its
    // only cancel path terminates the stream, which drops the very
    // `.error(.cancelled)` tail this fixture exists to freeze.
    let emitter: @Sendable (SimulationEvent) -> Void = { event in
      let pending = sink.withLock { $0.record(event, cancelPath: spec.cancelAfterPhaseCompleted) }
      // Cancelled outside the lock (lock discipline: `Task.cancel` runs
      // arbitrary cancellation handlers, including the runner's pause-gate
      // one, which takes a lock of its own).
      pending?.cancel()
    }

    let runner = SimulationRunner(random: random)
    if spec.cancelAfterPhaseCompleted == nil {
      await runner.run(
        scenario: scenario, llm: responder, suspendController: SuspendController(),
        emitter: emitter)
    } else {
      let task = Task {
        await runner.run(
          scenario: scenario, llm: responder, suspendController: SuspendController(),
          emitter: emitter)
      }
      // The emitter may fire before this assignment — `Task` starts running
      // immediately — so the sink records a *request* when it has no handle
      // yet and hands it back here. Without this arm a fixture whose trigger
      // is the run's first event would never be cancelled.
      let pending = sink.withLock { $0.adopt(task) }
      pending?.cancel()
      await task.value
    }

    let (recordedLines, triggerFired) = sink.withLock { ($0.lines, $0.triggerFired) }
    if let path = spec.cancelAfterPhaseCompleted, !triggerFired {
      throw ParityFixtureError.cancelTriggerNeverFired(spec.name, path)
    }
    // Same failure shape as the cancel-trigger guard above: an unreached
    // schedule entry would otherwise pass silently and freeze a golden that
    // measures no suspend at all.
    let remainingSuspends = responder.remainingSuspends
    if remainingSuspends > 0 {
      throw ParityFixtureError.suspendNeverFired(name: spec.name, remaining: remainingSuspends)
    }

    let fixture = Fixture(
      name: spec.name,
      purpose: spec.purpose,
      scenarioJSON: try encodeScenario(scenario),
      responses: responder.recordedResponses,
      transcript: try recordedLines.map { try JSONL.encode($0) },
      callCount: responder.callCount,
      seed: spec.seed,
      cancelAfterPhaseCompleted: spec.cancelAfterPhaseCompleted,
      suspendBeforeResponse: spec.suspendBeforeResponse)
    return Run(fixture: fixture, answeredFields: responder.recordedSchemaFields)
  }

  /// Transcript accumulator plus the cancel trigger's one-shot latch.
  ///
  /// One `Mutex`-guarded value rather than two, because the decision to cancel
  /// is made *while* appending the event that triggers it: two locks would
  /// admit an ordering where a second `phaseCompleted` slips between the
  /// append and the latch and cancels twice.
  ///
  /// Lines are kept as ``EventLine`` and encoded after the run: `JSONL.encode`
  /// throws, and the emitter is a non-throwing `@Sendable` closure. Mapping
  /// stays inside the emitter so the transcript order is the emission order
  /// even on the cancelling arm.
  private struct CancelSink {
    var lines: [EventLine] = []
    private var task: Task<Void, Never>?
    private var cancelRequested = false
    /// Whether the trigger path was ever seen — the guard against a spec whose
    /// path no run emits.
    private(set) var triggerFired = false

    /// Maps and appends `event`, returning the task to cancel when it is the
    /// trigger and a handle is already available.
    mutating func record(_ event: SimulationEvent, cancelPath: [Int]?) -> Task<Void, Never>? {
      if let line = EventLineMapper.map(ParityFixtureEmitter.normalize(event), t: 0, attempt: 0) {
        lines.append(line)
      }
      guard let cancelPath, !triggerFired,
        case .phaseCompleted(_, let path) = event, path == cancelPath
      else { return nil }
      triggerFired = true
      guard let task else {
        cancelRequested = true
        return nil
      }
      return task
    }

    /// Stores the run's handle, returning it when the trigger already fired.
    mutating func adopt(_ task: Task<Void, Never>) -> Task<Void, Never>? {
      self.task = task
      return cancelRequested ? task : nil
    }
  }

  /// The option menu a scenario's `choose` phases offer, for the responder to
  /// answer `.choice` fields from.
  ///
  /// **Why it must be unambiguous.** ``RecordingResponder`` reads the schema
  /// and nothing else — it cannot see which phase is calling — so a scenario
  /// declaring two different menus has no single right answer, and picking one
  /// would silently answer the other phase off-menu, where
  /// `ChooseHandler.validateAction` drops the pairing. Throwing here turns that
  /// into a generation-time failure with the scenario named, rather than a
  /// fixture that runs and scores nothing.
  ///
  /// Nested branches are walked because a `conditional`'s `thenPhases` /
  /// `elsePhases` may hold a `choose`; an options-less `choose` contributes
  /// nothing, matching `OutputSchema.from`, which only marks a field `.choice`
  /// when the phase has options.
  ///
  /// `package` rather than `private` so the ambiguity guard is testable without
  /// authoring a throwaway scenario file on disk.
  package static func choiceOptions(in scenario: Scenario) throws -> [String] {
    var menus: [[String]] = []
    func walk(_ phases: [Phase]) {
      for phase in phases {
        if phase.type == .choose, let options = phase.options, !options.isEmpty,
          !menus.contains(options) {
          menus.append(options)
        }
        walk(phase.thenPhases ?? [])
        walk(phase.elsePhases ?? [])
      }
    }
    walk(scenario.phases)
    guard menus.count <= 1 else {
      throw ParityFixtureError.ambiguousChoiceOptions(scenario.id, menus)
    }
    return menus.first ?? []
  }

  /// Repo-relative path of the generated Kotlin file, named once so the CLI,
  /// the drift gate, and the docs cannot disagree.
  package static let generatedPath =
    "shared/engine/src/commonTest/kotlin/com/pastura/engine/ParityGolden.kt"

  /// The command that regenerates it, quoted in the file header and in the
  /// drift-gate failure message.
  package static let regenerateCommand = "swift run pastura-harness parity-emit --write"

  /// Encodes the scenario with sorted keys so `--check` reports real drift
  /// rather than dictionary-order churn.
  private static func encodeScenario(_ scenario: Scenario) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let data = try encoder.encode(scenario)
    guard let json = String(data: data, encoding: .utf8) else {
      throw ParityFixtureError.notUTF8(scenario.id)
    }
    return json
  }
}
