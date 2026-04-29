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
  /// Speed tier applied to ``turnDelayMs`` / ``codePhaseDelayMs`` via
  /// ``PlaybackSpeed/multiplier``. `.normal` plays at the nominal
  /// rhythm; `.slow` doubles delays, `.fast` shortens them by 1/1.5×;
  /// `.instant` collapses the per-event sleep to 0ms (every consumer
  /// special-cases `.instant` rather than relying on the sentinel
  /// `.infinity` multiplier).
  ///
  /// Replaces the `speedMultiplier: Double` knob (#290 / PR 1b of
  /// #273): Sim and replay now share the same `.slow / .normal /
  /// .fast / .instant` vocabulary, eliminating the replay-only
  /// coefficient.
  ///
  /// Test fixtures: `100.0` → `.instant`; `1.0` → `.normal`. See
  /// `ReplayViewModelTests.fastConfig` for the canonical example.
  public var playbackSpeed: PlaybackSpeed

  /// Nominal delay inserted before each agent turn (`agentOutput`
  /// event). At ``PlaybackSpeed/normal`` this is the perceived "one
  /// agent speaks, next agent reacts" rhythm of a live simulation.
  ///
  /// Stored on the config — not on each recorded event — because
  /// per-event pacing would baker per-turn LLM inference time into
  /// the recording, which is dead time on replay. Keeping pacing
  /// consumer-side also lets a future `UserSimulationReplaySource`
  /// pick a different rhythm without re-recording.
  public var turnDelayMs: Int

  /// Nominal delay before each code-phase event (score updates,
  /// eliminations, vote tallies). Shorter than ``turnDelayMs`` so
  /// the view reads as "agents speak, then the game ticks, then
  /// back to agents" without stalling on the tick.
  public var codePhaseDelayMs: Int

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
    playbackSpeed: PlaybackSpeed = .normal,
    turnDelayMs: Int = 1200,
    codePhaseDelayMs: Int = 500,
    loopBehaviour: LoopBehaviour,
    onComplete: CompletionAction
  ) {
    self.playbackSpeed = playbackSpeed
    self.turnDelayMs = turnDelayMs
    self.codePhaseDelayMs = codePhaseDelayMs
    self.loopBehaviour = loopBehaviour
    self.onComplete = onComplete
  }

  /// Preset for the DL-time demo host: nominal speed, loop forever,
  /// wait for the download-complete transition signal.
  ///
  /// Speed history: originally 2× per spec §2 decision 5, revised to
  /// `.normal` (1×) when #170 manual QA on bundled demos found 2× too
  /// fast to follow. Spec §2 decision 5 was updated in the same PR.
  public static let demoDefault = ReplayPlaybackConfig(
    playbackSpeed: .normal,
    loopBehaviour: .loop,
    onComplete: .awaitTransitionSignal)
}
