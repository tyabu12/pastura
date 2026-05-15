import Foundation
import SwiftUI

/// Which launch animation should play next.
///
/// `nonisolated` so the auto-synthesised `Equatable` witness is callable from
/// non-`@MainActor` test suites (and from `nonisolated static` helpers like
/// ``LaunchPhaseCoordinator/nextLaunchKind(now:lastBackgroundedAt:threshold:)``
/// in this file). Without it, the witness inherits the App/ default MainActor
/// isolation and can't be used as a return type in nonisolated contexts —
/// see memory `reference_swift6_autosynth_conformance_actor.md`.
nonisolated public enum LaunchKind: Sendable, Equatable {
  /// "Pastoral Drift" — full brand intro for first-open / process-restarted launches.
  case cold
  /// "Breath" — abbreviated pulse for resume-from-recent-background.
  case warm
}

/// Per-scene coordinator tracking when the app was last backgrounded so the
/// next foreground transition can choose between cold and warm launch
/// animations.
///
/// **Scope:** owns only `lastBackgroundedAt`. The decision logic itself is a
/// pure `static` function so tests can pin `now:` to a fixture `Date` and
/// stay deterministic on the threshold boundary — see memory
/// `feedback_ci_wallclock_test_bounds.md`.
///
/// **Per-scene:** Pastura supports iPad multi-window via `WindowGroup`; each
/// scene's `RootView` holds its own `@State` instance so warm/cold decisions
/// don't bleed across windows.
@Observable
@MainActor
public final class LaunchPhaseCoordinator {
  /// Timestamp of the most recent `scenePhase: .background` observation, or
  /// `nil` if the scene has not been backgrounded this process lifetime.
  ///
  /// Cleared by `clearBackgrounded()` after a warm splash has played so a
  /// subsequent in-process toggle picks up a fresh interval.
  public private(set) var lastBackgroundedAt: Date?

  public init() {}

  /// Records that the scene moved to background at `timestamp`.
  ///
  /// Call from `RootView`'s `scenePhase` observer when transitioning into
  /// `.background`. `.inactive` is intentionally not stored — iOS fires
  /// `.inactive` for transient interruptions (Control Center, incoming
  /// call) that should not retrigger a launch animation on dismissal.
  public func recordBackgrounded(at timestamp: Date = .now) {
    lastBackgroundedAt = timestamp
  }

  /// Clears the stored background timestamp. Called after a warm splash has
  /// played so a same-session repeat (foreground → background → foreground
  /// again) gets its own measurement window.
  public func clearBackgrounded() {
    lastBackgroundedAt = nil
  }

  /// Pure decision: given the current time and the last-backgrounded
  /// timestamp, classify the next launch as cold or warm.
  ///
  /// - Returns: `.cold` when `lastBackgroundedAt` is `nil` (process start)
  ///   or when the elapsed interval exceeds `threshold`. `.warm` when the
  ///   elapsed interval is `≤ threshold` (boundary is inclusive).
  ///
  /// `nonisolated` so tests on a non-`@MainActor` suite can call this
  /// directly without instantiating the class.
  nonisolated public static func nextLaunchKind(
    now: Date,
    lastBackgroundedAt: Date?,
    threshold: TimeInterval
  ) -> LaunchKind {
    guard let lastBg = lastBackgroundedAt else { return .cold }
    let elapsed = now.timeIntervalSince(lastBg)
    return elapsed <= threshold ? .warm : .cold
  }
}
