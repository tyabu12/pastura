import Foundation

/// Pure helper that computes when the launch splash should dismiss given a
/// minimum-display guarantee and a maximum extension window.
///
/// The launch animation has a "minimum guaranteed playback time" semantic:
/// when app initialisation completes faster than the splash's natural
/// duration, the splash is held to its full minimum so the user perceives a
/// complete animation rather than a flash. When initialisation is slow, the
/// splash extends by up to `maxExtension` seconds before giving up so the
/// user is never left staring at the splash indefinitely — past the hard
/// deadline, a generic loading affordance takes over.
///
/// **All computations are in seconds relative to the splash start instant.**
/// The caller owns wall-clock translation; this type stays pure for tests.
///
/// **Why `nonisolated`:** `App/` types inherit MainActor isolation by default
/// (`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`), which would force callers
/// and tests onto the main actor. The struct is pure value-state with no
/// data-race surface — see `LaunchAnimationConfig` and `LocaleResolver` for
/// the same pattern in this layer.
nonisolated public struct LaunchSplashTimer: Sendable, Equatable {
  /// Minimum seconds the splash must remain visible before dismissal is
  /// eligible, even if initialisation already completed.
  public let minDuration: TimeInterval

  /// Maximum seconds beyond `minDuration` the splash may remain visible
  /// while waiting for a slow initialisation. After `minDuration +
  /// maxExtension`, the splash dismisses regardless of init state.
  public let maxExtension: TimeInterval

  public init(minDuration: TimeInterval, maxExtension: TimeInterval) {
    self.minDuration = minDuration
    self.maxExtension = maxExtension
  }

  /// The absolute upper bound (in seconds since splash start) past which
  /// the splash dismisses regardless of init progress.
  public var hardDeadline: TimeInterval { minDuration + maxExtension }

  /// Computes when the splash should dismiss.
  ///
  /// - Parameters:
  ///   - minDuration: minimum visible time before dismissal is eligible.
  ///   - maxExtension: extra time the splash may wait for a slow init.
  ///   - readyAt: seconds (from splash start) at which initialisation
  ///     reached a non-initializing state, or `nil` if still initializing.
  /// - Returns: seconds (from splash start) at which the splash should
  ///   dismiss.
  ///
  /// Rules:
  /// - `readyAt <= minDuration` → dismiss at `minDuration` (hold to floor).
  /// - `minDuration < readyAt <= minDuration + maxExtension` → dismiss at
  ///   `readyAt` (init done within extension window — release immediately).
  /// - `readyAt > minDuration + maxExtension` or `nil` → dismiss at
  ///   `minDuration + maxExtension` (cap — caller surfaces a loading UI).
  public static func dismissalTime(
    minDuration: TimeInterval,
    maxExtension: TimeInterval,
    readyAt: TimeInterval?
  ) -> TimeInterval {
    let hardDeadline = minDuration + maxExtension
    guard let readyAt else { return hardDeadline }
    if readyAt <= minDuration { return minDuration }
    if readyAt <= hardDeadline { return readyAt }
    return hardDeadline
  }
}
