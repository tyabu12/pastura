import Foundation

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
  func events() -> AsyncStream<SimulationEvent>
}
