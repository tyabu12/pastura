import Foundation

/// A planned event ready for consumer-driven playback.
///
/// Spec: `docs/specs/demo-replay-spec.md` §4.6.
///
/// Wraps a ``SimulationEvent`` with the minimum classification a consumer
/// needs to pick a pre-yield delay bucket (``ReplayPlaybackConfig`` fields
/// `turnDelayMs` / `codePhaseDelayMs`). Lifecycle events synthesised from
/// YAML metadata carry ``Kind/lifecycle`` and **must** be yielded with
/// zero delay — otherwise the consumer sleeps before announcing the
/// round/phase, which reads wrong.
///
/// Introduced in Issue #169 (C-track PR1) so ``ReplayViewModel`` can own
/// `Task.sleep` per ADR-007 §3.4's resume-from-position contract — the
/// original ``ReplaySource/events()`` API bakes delays into the producer
/// task and cannot surface `remainingDelayMs` to the consumer.
nonisolated public struct PacedEvent: Sendable, Equatable {
  /// Classifies the event so the consumer can pick the right delay bucket.
  public enum Kind: Sendable, Equatable {
    /// LLM-phase agent output (`.agentOutput`). Pre-yield delay =
    /// `ReplayPlaybackConfig.turnDelayMs / playbackSpeed.multiplier`
    /// (consumer also early-returns 0 when `playbackSpeed == .instant`).
    case turn
    /// Code-phase result (`.scoreUpdate` / `.elimination` / `.summary` /
    /// `.voteResults` / `.pairingResult` / `.assignment`). Pre-yield
    /// delay = `ReplayPlaybackConfig.codePhaseDelayMs /
    /// playbackSpeed.multiplier` (`.instant` short-circuits to 0).
    case codePhase
    /// Synthesised round/phase boundary (`.roundStarted` / `.phaseStarted`).
    /// Pre-yield delay = 0 — the marker fires alongside the event it
    /// precedes rather than adding its own sleep.
    case lifecycle
  }

  public let kind: Kind
  public let event: SimulationEvent

  public init(kind: Kind, event: SimulationEvent) {
    self.kind = kind
    self.event = event
  }
}

/// A source of pre-recorded ``SimulationEvent``s replayed back to the UI.
///
/// Spec: `docs/specs/demo-replay-spec.md` §4.3.
///
/// This protocol is introduced as part of the Phase 2 E1 "YAML simulation
/// replay primitive" (Issue #167). The E1 ship concretes only
/// ``YAMLReplaySource``. The DL-time `BundledDemoReplaySource` (spec §4.4)
/// and the future Phase 2.5+ `UserSimulationReplaySource` (spec §4.5) both
/// land in later issues and compose on top of ``YAMLReplaySource``.
///
/// Conforming types **must** be `nonisolated` at the type level: the
/// project's `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` would otherwise
/// infer MainActor for the ``events()`` closure body — which builds an
/// `AsyncStream` + `Task` + `onTermination` and therefore breaks
/// `Sendable` conformance. See `.claude/rules/llm.md` for the diagnostic
/// and the same pattern at ``LLMService/generateStream(system:user:)``.
nonisolated public protocol ReplaySource: Sendable {
  /// Scenario this replay renders against. Supplies persona names, phase
  /// structure, and score-display context to the view layer.
  ///
  /// Concrete sources receive a pre-resolved ``Scenario`` rather than
  /// resolving from a `preset_ref.id` themselves — preset resolution /
  /// SHA drift detection is the wrapper source's concern (spec §4.4).
  var scenario: Scenario { get }

  /// Yields the pre-recorded event sequence in order, with natural
  /// inter-event pacing applied.
  ///
  /// A fresh stream is returned per call so the same source can be played
  /// back multiple times (required for the loop behaviour in spec §4.9).
  ///
  /// - Note: Retained for the E1 primitive contract and round-trip tests
  ///   against ``YAMLReplayExporter``. VM consumers needing
  ///   resume-from-position (ADR-007 §3.4) **must** use
  ///   ``plannedEvents()`` instead — this streaming form bakes pacing
  ///   into the producer task and cannot surface `remainingDelayMs` to
  ///   the consumer. The two APIs emit different event sequences: this
  ///   one does NOT include synthesised `.roundStarted` / `.phaseStarted`
  ///   markers, while ``plannedEvents()`` does.
  func events() -> AsyncStream<SimulationEvent>

  /// Returns the full replay plan as a chronologically-ordered array,
  /// including synthesised `.roundStarted` / `.phaseStarted` lifecycle
  /// events. Consumers own pacing — each ``PacedEvent`` carries a
  /// ``PacedEvent/Kind`` so the consumer can pick the right delay bucket
  /// from ``ReplayPlaybackConfig``.
  ///
  /// Stable across calls: the returned array's identity + order is
  /// memoised inside the source at construction time (required for
  /// resume-from-position: `eventCursor` in a paused state indexes into
  /// this array, so two calls must produce equal indexing).
  ///
  /// Events are merged from YAML `turns` and `code_phase_events` sections
  /// into a single chronological order keyed by `(round, phase_index)`
  /// with stable secondary ordering by source position. Inside each
  /// scenario, the first event of a new round carries a preceding
  /// synthesised `.roundStarted`; the first event of a new phase
  /// (within a round) carries a preceding synthesised `.phaseStarted`.
  ///
  /// **Intentionally NOT synthesised:**
  /// - `.roundCompleted(round:scores:)` — the YAML schema has no slot
  ///   for per-round score snapshots (spec §3.2). A consumer that
  ///   needs a running scoreboard reads `.scoreUpdate` events.
  /// - `.simulationCompleted` — stream-end is signalled by the array
  ///   finishing; a synthesised terminator would race with the
  ///   consumer's own end-of-iteration detection.
  ///
  /// **Known fidelity gap** (matches ``YAMLReplayExporter`` limitation,
  /// see that type's `resolvePhaseIndices` doc): `.phaseStarted.phasePath`
  /// is flattened to `[phaseIndex]`. Sub-phases inside a `conditional`
  /// resolve to the outer conditional's index. Acceptable for Phase 2
  /// linear presets (Word Wolf, Prisoner's Dilemma).
  func plannedEvents() -> [PacedEvent]
}
