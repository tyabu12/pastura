import Foundation

/// Playback policy applied by a ``ReplaySource`` consumer (the future
/// `ReplayViewModel`, landing in Issue #C).
///
/// Spec: `docs/specs/demo-replay-spec.md` §4.6.
///
/// Shipped as part of the Phase 2 E1 primitive so the DL-time
/// `BundledDemoReplaySource` (#C) and future `UserSimulationReplaySource`
/// (Phase 2.5+, spec §4.5) can pick the appropriate preset without
/// introducing a second config type.
nonisolated public struct ReplayPlaybackConfig: Sendable, Equatable {
  /// Multiplier applied to recorded `delay_ms_before` values. `2.0` means
  /// twice as fast — a recorded 1000 ms gap plays as 500 ms of sleep.
  public var speedMultiplier: Double

  /// What the consumer does after the last event of the current source.
  public var loopBehaviour: LoopBehaviour

  /// What the consumer does once playback has nothing left to play.
  public var onComplete: CompletionAction

  public enum LoopBehaviour: Sendable, Equatable {
    /// Rewind to the first event and keep playing — DL-time demo default.
    case loop
    /// Stop after the last event — future user-initiated replay default.
    case stopAfterLast
  }

  public enum CompletionAction: Sendable, Equatable {
    /// Hold the "done" state until an external signal (e.g. the
    /// download-complete trigger) arrives. DL-time demo default.
    case awaitTransitionSignal
    /// Tear down immediately once playback ends. Future user-replay
    /// default.
    case stopPlayback
  }

  public init(
    speedMultiplier: Double,
    loopBehaviour: LoopBehaviour,
    onComplete: CompletionAction
  ) {
    self.speedMultiplier = speedMultiplier
    self.loopBehaviour = loopBehaviour
    self.onComplete = onComplete
  }

  /// Preset for the DL-time demo host: 2× speed, loop forever, wait for
  /// the download-complete transition signal.
  public static let demoDefault = ReplayPlaybackConfig(
    speedMultiplier: 2.0,
    loopBehaviour: .loop,
    onComplete: .awaitTransitionSignal)
}
