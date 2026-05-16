import SwiftUI
import UIKit

/// "Pastoral Drift" — full-screen launch animation for cold starts.
///
/// Composed of two overlapping layers:
/// 1. **Base icon** — fades in and scales `.94 → 1.00`, then fades out at
///    `1.00 → 1.08` for the exit.
/// 2. **Sheep layer** — same icon clipped to the bottom-right region (see
///    ``SheepClipShape``), drifts horizontally `+36 pt → 0` during the
///    middle of the timeline so the sheep silhouette appears to "arrive
///    at the pasture".
///
/// A single `UIImpactFeedbackGenerator(.light)` haptic fires at 55% of the
/// timeline (~880 ms into the default 1.6s playback) — the audible-tactile
/// confirmation that the sheep have landed. The haptic is scheduled via
/// `.task` so it auto-cancels if the view disappears early (e.g. fast
/// init resolution).
///
/// **Reduce Motion:** when `accessibilityReduceMotion` is set, the view
/// degrades to a simple 400 ms cross-fade with no scale or drift. The
/// haptic still fires — Reduce Motion targets visual stimulation, not
/// tactile feedback (per the design handoff's accessibility note).
struct ColdSplashView: View {
  /// Display name of the launch icon asset added in item 6
  /// (`Assets.xcassets/LaunchIcon.imageset`). Until that asset exists,
  /// `Image(_)` falls back to a placeholder — the integration test plan
  /// covers the wiring in item 7's manual QA.
  private static let iconAssetName = "LaunchIcon"

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  // Animation state — toggled once on first appearance so SwiftUI's implicit
  // `withAnimation` transitions both layers from their .94 / +36 starting
  // values to their resting values. Held flags drive the exit phase.
  @State private var settled = false
  @State private var exiting = false

  var body: some View {
    ZStack {
      LaunchAnimationConfig.backgroundColor
        .ignoresSafeArea()

      iconStack
        .frame(
          width: LaunchAnimationConfig.iconSize,
          height: LaunchAnimationConfig.iconSize)
    }
    .opacity(exiting ? 0 : 1)
    .task { await runAnimation() }
  }

  @ViewBuilder
  private var iconStack: some View {
    if reduceMotion {
      // Reduced-motion path: single icon, opacity-only crossfade.
      Image(Self.iconAssetName)
        .resizable()
        .scaledToFit()
        .clipShape(
          RoundedRectangle(cornerRadius: LaunchAnimationConfig.iconCornerRadius)
        )
        .opacity(settled ? 1 : 0)
    } else {
      ZStack {
        Image(Self.iconAssetName)
          .resizable()
          .scaledToFit()
          .clipShape(
            RoundedRectangle(cornerRadius: LaunchAnimationConfig.iconCornerRadius)
          )
          .opacity(settled ? 1 : 0)
          .scaleEffect(driftBaseScale)

        Image(Self.iconAssetName)
          .resizable()
          .scaledToFit()
          .clipShape(SheepClipShape())
          .opacity(settled ? 1 : 0)
          .offset(x: settled ? 0 : LaunchAnimationConfig.sheepDriftDistance)
          .scaleEffect(driftBaseScale)
      }
    }
  }

  private var driftBaseScale: CGFloat {
    if exiting { return 1.08 }  // exit overshoot per `driftBase` keyframes
    if settled { return 1.00 }  // resting
    return 0.94  // 0% start
  }

  /// Runs the animation timeline. Phases match the README keyframes:
  /// - 0 → 18%: base + sheep fade in, base scales .94 → 1.00, sheep drifts
  /// - 55% (~880ms): haptic fires
  /// - 72 → 100%: exit fade + scale 1.00 → 1.08
  ///
  /// The `.task` modifier on `body` owns this; cancellation on view
  /// disappear stops both the haptic and the exit-phase transition.
  private func runAnimation() async {
    let duration =
      reduceMotion
      ? LaunchAnimationConfig.reducedMotionDuration
      : LaunchAnimationConfig.coldDuration

    // Phase A — settle (0 → 18% of timeline, i.e. ~288ms at 1.6s).
    let settleDuration = duration * 0.18
    withAnimation(LaunchAnimationConfig.easeOutPastoral(duration: settleDuration)) {
      settled = true
    }

    // Phase B — haptic landing at 55% (~880ms at 1.6s). Skipped for the
    // reduce-motion path because its timeline is too compressed for the
    // beat to read as a "landing".
    if !reduceMotion {
      let hapticDelay = duration * LaunchAnimationConfig.hapticDelayRatio
      let hapticNs = UInt64(hapticDelay * 1_000_000_000)
      try? await Task.sleep(nanoseconds: hapticNs)
      Self.fireLandingHaptic()
    }

    // Phase C — exit (72 → 100% of timeline). Computed as the remainder of
    // the duration after the haptic. For reduce-motion we just wait the
    // full duration before starting the fade-out.
    let elapsedSoFar =
      reduceMotion
      ? 0
      : duration * LaunchAnimationConfig.hapticDelayRatio
    let remainder = duration - elapsedSoFar
    let exitPortion = reduceMotion ? remainder : duration * 0.28
    let preExitHold = remainder - exitPortion

    if preExitHold > 0 {
      let holdNs = UInt64(preExitHold * 1_000_000_000)
      try? await Task.sleep(nanoseconds: holdNs)
    }
    withAnimation(LaunchAnimationConfig.easeStandard(duration: exitPortion)) {
      exiting = true
    }
  }

  /// Fires the "landing" haptic. Wrapped as a `static` so a faster init
  /// can dismiss the view before this is reached without leaking a
  /// generator instance.
  private static func fireLandingHaptic() {
    let generator = UIImpactFeedbackGenerator(style: .light)
    generator.prepare()
    generator.impactOccurred()
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
