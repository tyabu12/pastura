import SwiftUI
import UIKit

/// "Pastoral Drift" — full-screen launch animation for cold starts.
///
/// Composed of two overlapping layers:
/// 1. **Base icon** — fades in and scales `.94 → 1.00` over the settle phase.
/// 2. **Sheep layer** — same icon clipped to the bottom-right region (see
///    ``SheepClipShape``), drifts horizontally `+36 pt → 0` during the
///    settle phase so the sheep silhouette appears to "arrive at the pasture".
///
/// A single `UIImpactFeedbackGenerator(.light)` haptic fires at 55% of the
/// timeline (~880 ms into the default 1.6s playback) — the audible-tactile
/// confirmation that the sheep have landed. The haptic is scheduled via
/// `.task` so it auto-cancels if the view disappears early.
///
/// **Exit phase is owned by the parent.** This view holds at "settled"
/// indefinitely; the README's 72→100% scale-up + fade-out is expressed as
/// a SwiftUI `.transition` on the parent's `splashKind` removal so that:
/// (a) the splash can extend past the natural duration when initialisation
/// runs slow, and (b) the exit is unified with whatever follow-on view
/// (HomeView, ProgressView fallback) emerges underneath.
///
/// **Reduce Motion:** when `accessibilityReduceMotion` is set, the view
/// degrades to a simple opacity-only fade-in with no scale or drift. The
/// haptic still fires — Reduce Motion targets visual stimulation, not
/// tactile feedback (per the design handoff's accessibility note).
struct ColdSplashView: View {
  /// Display name of the launch icon asset (`Assets.xcassets/LaunchIcon.imageset`).
  private static let iconAssetName = "LaunchIcon"

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  // Two state flags so base and sheep can run on separate timelines per
  // the CSS reference's `driftSheep` keyframes:
  //   base:  0 % → 18 %  fade-in + scale .94 → 1.00
  //   sheep: 20 % → 55 % fade-in + translateX 36 → 0
  // The 20 % delay on the sheep is what makes the drift visible — without
  // it the sheep collapses into the same 18 % window as the base and
  // "ふっと現れる" before the user perceives the motion.
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
          .scaleEffect(settled ? 1.00 : 0.94)

        Image(Self.iconAssetName)
          .resizable()
          .scaledToFit()
          .clipShape(SheepClipShape())
          .opacity(sheepArrived ? 1 : 0)
          .offset(x: sheepArrived ? 0 : LaunchAnimationConfig.sheepDriftDistance)
          // Scale matches the base layer so they stay aligned during the
          // brief co-visible window (≈18 → 20 %): base just reached scale
          // 1.00 and sheep is about to begin its drift.
          .scaleEffect(settled ? 1.00 : 0.94)
      }
    }
  }

  /// Runs the animation timeline. Phases match the README keyframes:
  /// - **0 → 18 %**: base fades in + scales `.94 → 1.00`
  /// - **20 → 55 %**: sheep drifts + fades in (`offset 36 → 0`, `opacity 0 → 1`)
  /// - **55 %** (≈ 660 ms at 1.2 s): haptic fires the moment the sheep
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

    // Phase B — sheep drift (20 → 55 % of total timeline). The 20 %
    // pre-drift delay is what makes the drift readable; the previous
    // implementation collapsed sheep into the base's 18 % settle window
    // and the motion was imperceptible.
    let sheepDelay = duration * 0.20
    let sheepDriftDuration = duration * 0.35
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
