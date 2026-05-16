import SwiftUI
import UIKit

/// "Pastoral Drift" — full-screen launch animation for cold starts.
///
/// Composed of two overlapping image layers — **pre-rendered as separate
/// assets** so design elements that straddle the horizontal midline
/// (e.g. the P brandmark dipping into the grass) are not truncated:
/// 1. **Sky layer** (`LaunchIconSky`) — fades in and scales `.94 → 1.00`
///    during the settle phase. Static after settling.
/// 2. **Pasture layer** (`LaunchIconPasture`, grass + hill + 3 sheep)
///    — drifts horizontally `+ sheepDriftDistance → 0` during the drift
///    phase so the entire pasture appears to wander in under the sky.
///
/// A single `UIImpactFeedbackGenerator(.light)` haptic fires at
/// ``LaunchAnimationConfig/hapticDelayRatio`` of the timeline — by design,
/// the same instant the pasture finishes drifting in. The haptic is
/// scheduled via `.task` so it auto-cancels if the view disappears early.
///
/// **Exit phase is owned by the parent.** This view holds at "settled"
/// indefinitely; the README's 72→100 % scale-up + fade-out is expressed as
/// a SwiftUI `.transition` on the parent's `splashKind` removal so that:
/// (a) the splash can extend past the natural duration when initialisation
/// runs slow, and (b) the exit is unified with whatever follow-on view
/// (HomeView, ProgressView fallback) emerges underneath.
///
/// **Reduce Motion:** when `accessibilityReduceMotion` is set, the view
/// degrades to a simple opacity-only fade-in of the combined `LaunchIcon`
/// asset (no sky/pasture split, no scale, no drift). The haptic still
/// fires — Reduce Motion targets visual stimulation, not tactile feedback
/// (per the design handoff's accessibility note).
struct ColdSplashView: View {
  /// Combined launch icon — used as a single layer under Reduce Motion
  /// and as the canonical reference for the static iOS LaunchScreen.
  private static let combinedAssetName = "LaunchIcon"

  /// Top half of the launch icon (P + cream background, transparent
  /// below). Static sky layer of the cold splash.
  private static let skyAssetName = "LaunchIconSky"

  /// Bottom half of the launch icon (grass + hill + 3 sheep, transparent
  /// above). Drifting pasture layer of the cold splash.
  private static let pastureAssetName = "LaunchIconPasture"

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  // Two state flags so sky and pasture run on separate timelines:
  //   sky:     0 % → 18 %  fade-in + scale .94 → 1.00
  //   pasture: 20 % → 65 % fade-in + translateX 32 → 0
  // The 20 % pre-drift hold on the pasture is what makes the drift
  // readable — collapsing it into the sky's 18 % settle window made the
  // motion imperceptible.
  @State private var settled = false
  @State private var sheepArrived = false

  var body: some View {
    ZStack {
      LaunchAnimationConfig.backgroundColor
        .ignoresSafeArea()

      iconStack
        .frame(
          width: LaunchAnimationConfig.iconSize,
          height: LaunchAnimationConfig.iconSize)
    }
    .task { await runAnimation() }
  }

  @ViewBuilder
  private var iconStack: some View {
    if reduceMotion {
      // Reduced-motion path: single combined icon, opacity-only crossfade.
      Image(Self.combinedAssetName)
        .resizable()
        .scaledToFit()
        .opacity(settled ? 1 : 0)
    } else {
      ZStack {
        // Sky layer (P + cream background). Pre-rendered as a separate
        // asset with transparent bottom so the pasture layer can drift
        // underneath without truncating the P or any other element that
        // would otherwise cross a horizontal clip line.
        Image(Self.skyAssetName)
          .resizable()
          .scaledToFit()
          .opacity(settled ? 1 : 0)
          .scaleEffect(settled ? 1.00 : 0.94)

        // Pasture layer (grass + hill + 3 sheep). Drifts in from the
        // right; scale matches the sky layer so the two halves align
        // pixel-perfectly when both settle and form the complete icon.
        Image(Self.pastureAssetName)
          .resizable()
          .scaledToFit()
          .opacity(sheepArrived ? 1 : 0)
          .offset(x: sheepArrived ? 0 : LaunchAnimationConfig.sheepDriftDistance)
          .scaleEffect(settled ? 1.00 : 0.94)
      }
    }
  }

  /// Runs the animation timeline. Phases:
  /// - **0 → 18 %**: base fades in + scales `.94 → 1.00`
  /// - **20 → 65 %**: sheep drifts + fades in (`offset 32 → 0`,
  ///   `opacity 0 → 1`) — gentle ~60 pt/s pastoral wander
  /// - **65 %** (≈ 780 ms at 1.2 s): haptic fires the moment the sheep
  ///   reaches its resting position
  /// - **72 → 100 %**: exit fade — NOT handled here, owned by parent
  ///   transition
  ///
  /// The `.task` modifier on `body` owns this; cancellation on view
  /// disappear propagates out of `Task.sleep(nanoseconds:)` as
  /// `CancellationError`, skipping the remaining phases. Using `try`
  /// (not `try?`) + outer do/catch is load-bearing: `try?` would swallow
  /// the cancellation and fire the haptic into a torn-down view.
  private func runAnimation() async {
    let duration =
      reduceMotion
      ? LaunchAnimationConfig.reducedMotionDuration
      : LaunchAnimationConfig.coldDuration

    // Phase A — base settle (0 → 18 %).
    let settleDuration = duration * 0.18
    withAnimation(LaunchAnimationConfig.easeOutPastoral(duration: settleDuration)) {
      settled = true
    }

    // Reduce Motion bypasses both the sheep drift (no second layer is
    // rendered under `accessibilityReduceMotion`) and the haptic — the
    // compressed timeline doesn't leave room for a believable beat.
    guard !reduceMotion else { return }

    // Phase B — sheep drift. Spec: sheep enters at
    // ``LaunchAnimationConfig/sheepEnterRatio`` of the timeline and
    // arrives at the haptic instant (``hapticDelayRatio``). The pre-drift
    // delay is what makes the drift readable; collapsing it into the
    // sky's settle window made the motion imperceptible. Duration is
    // derived from the two ratios so adjusting either keeps them locked.
    let sheepDelay = duration * LaunchAnimationConfig.sheepEnterRatio
    let sheepDriftDuration =
      duration
      * (LaunchAnimationConfig.hapticDelayRatio
        - LaunchAnimationConfig.sheepEnterRatio)
    do {
      try await Task.sleep(nanoseconds: UInt64(sheepDelay * 1_000_000_000))
      withAnimation(
        LaunchAnimationConfig.easeOutPastoral(duration: sheepDriftDuration)
      ) {
        sheepArrived = true
      }

      // Phase C — haptic at 55 % (sheep landing instant).
      try await Task.sleep(nanoseconds: UInt64(sheepDriftDuration * 1_000_000_000))
      Self.fireLandingHaptic()
    } catch {
      // Task cancelled — view disappeared mid-animation. Intentionally
      // skip the remaining phases including the haptic.
    }
  }

  /// Fires the "landing" haptic. Static so the generator instance doesn't
  /// outlive the view if the parent dismisses early.
  private static func fireLandingHaptic() {
    let generator = UIImpactFeedbackGenerator(style: .light)
    generator.prepare()
    generator.impactOccurred()
  }
}

/// `.transition` describing the cold splash's exit per the README 72→100%
/// keyframes: scale `1.00 → 1.08` + opacity `1 → 0`. Apply on the splash's
/// container at the callsite (`RootView`) so removing `splashKind` plays
/// the exit naturally.
extension AnyTransition {
  static var coldSplashExit: AnyTransition {
    .scale(scale: 1.08, anchor: .center)
      .combined(with: .opacity)
  }
}

#Preview("Cold splash") {
  ColdSplashView()
}

// Reduce-motion variant intentionally not previewed — Swift 6 makes
// `\.accessibilityReduceMotion` read-only, so the override won't compile
// (memory `reference_swift6_accessibility_env_readonly.md`). To verify the
// fallback, toggle Settings → Accessibility → Reduce Motion on the
// simulator and relaunch the app.
