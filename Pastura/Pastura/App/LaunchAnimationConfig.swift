import SwiftUI

/// Design tokens and easing-curve factories for the app-launch animation.
///
/// All members are `static` — this enum is a pure namespace with no instances.
/// Values are sourced from the Claude Design handoff for the launch sequence.
///
/// **Why `public`:** Referenced from `Views/` (animation implementation) and
/// `PasturaTests/` (design-token fidelity assertions). The enum carries only
/// value-type constants and pure factory functions — no actor-isolation
/// implications.
///
/// **Why `nonisolated`:** `App/` targets inherit `SWIFT_DEFAULT_ACTOR_ISOLATION
/// = MainActor`, which would bind all static members to the main actor.
/// These are pure compile-time constants with no mutable state, so there is no
/// data-race risk — `nonisolated` lifts the unnecessary restriction so tests
/// and `nonisolated` callers can read them without an `await`.
nonisolated public enum LaunchAnimationConfig {

  // MARK: - Duration tokens

  /// Full animation duration for a cold launch (first open / background-evicted).
  public static let coldDuration: TimeInterval = 1.2

  /// Abbreviated animation duration for a warm launch (recently backgrounded).
  public static let warmDuration: TimeInterval = 0.7

  /// If the app was last foregrounded within this many seconds, treat the
  /// launch as warm and use ``warmDuration`` instead of ``coldDuration``.
  public static let warmThreshold: TimeInterval = 180

  /// Fraction of ``coldDuration`` at which the sheep begins drifting
  /// into the pasture. The pre-drift hold (0 → this ratio) keeps the
  /// motion readable; collapsing it into the sky's settle window made
  /// the drift imperceptible. Must be strictly less than
  /// ``hapticDelayRatio`` so `sheepDriftDuration` stays positive.
  public static let sheepEnterRatio: Double = 0.20

  /// Fraction of ``coldDuration`` at which the haptic feedback fires —
  /// the moment the sheep reaches its resting position.
  /// E.g. `1.2 s × 0.65 = 0.78 s`. Also defines the sheep-drift end
  /// instant for the cold splash; the sheep enters at
  /// ``sheepEnterRatio`` and arrives at this ratio.
  public static let hapticDelayRatio: Double = 0.65

  /// Animation duration when the user has enabled Reduce Motion. Kept short
  /// to respect the accessibility preference while still providing a minimal
  /// fade-in cue.
  public static let reducedMotionDuration: TimeInterval = 0.4

  // MARK: - Color tokens

  /// Splash background — design-handoff "cream" (`#F1ECDC`).
  ///
  /// Slightly more saturated than the runtime ``Color/page`` token
  /// (`#F3EFE7`). The launch experience pivots on this specific value
  /// matching the asset-catalog `launchScreenBackground` ColorSet read by
  /// the Info.plist `UILaunchScreen` dict — keep the literal RGB and the
  /// catalog entry in lock-step.
  public static let backgroundColor = Color(
    red: 241.0 / 255.0, green: 236.0 / 255.0, blue: 220.0 / 255.0)

  // MARK: - Layout tokens

  /// Icon display size (width & height) in points.
  ///
  /// The Claude Design handoff specified 132 pt; we use 106 pt (~80 %) to
  /// reduce visual weight in the launch sequence. The
  /// `LaunchIcon.imageset` is rendered at the matching 106/212/318 px so
  /// the static iOS LaunchScreen and the SwiftUI splash render at the
  /// same on-screen size with no jump at the cold-splash 0 % frame.
  public static let iconSize: CGFloat = 106

  /// Icon corner radius in points, per design handoff.
  public static let iconCornerRadius: CGFloat = 30

  /// Horizontal drift distance for the sheep silhouette entrance, in points.
  /// The sheep starts offset by this amount and slides to its resting
  /// position. Average drift speed (with the current `coldDuration` /
  /// `hapticDelayRatio` of 1.2 s / 0.65) ≈ 60 pt/s, slow enough to read
  /// as pastoral wandering.
  public static let sheepDriftDistance: CGFloat = 32

  // MARK: - Easing curves

  /// Pastoral ease-out curve — cubic-bezier(.22, .61, .36, 1).
  /// Use for the icon settle and sheep drift, where an unhurried deceleration
  /// matches the pastoral character of the product.
  public static func easeOutPastoral(duration: TimeInterval) -> Animation {
    .timingCurve(0.22, 0.61, 0.36, 1.0, duration: duration)
  }

  /// Material Design "Standard" ease — cubic-bezier(.4, 0, .2, 1).
  /// Use for elements that need a familiar, neutral motion feel (e.g., fade
  /// transitions on supporting UI elements).
  public static func easeStandard(duration: TimeInterval) -> Animation {
    .timingCurve(0.4, 0.0, 0.2, 1.0, duration: duration)
  }
}
