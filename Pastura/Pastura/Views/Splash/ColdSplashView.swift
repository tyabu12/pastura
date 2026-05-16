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

  // Single state flag — toggled once on first appearance so SwiftUI's
  // implicit `withAnimation` transitions both layers from their .94 / +36
  // starting values to their resting values.
  @State private var settled = false

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
          .opacity(settled ? 1 : 0)
          .offset(x: settled ? 0 : LaunchAnimationConfig.sheepDriftDistance)
          .scaleEffect(settled ? 1.00 : 0.94)
      }
    }
  }

  /// Runs the animation timeline. Phases match the README keyframes:
  /// - 0 → 18%: base + sheep fade in, base scales .94 → 1.00, sheep drifts
  /// - 55% (~880 ms): haptic fires
  /// - 72 → 100%: exit fade — NOT handled here, owned by parent transition
  ///
  /// The `.task` modifier on `body` owns this; cancellation on view
  /// disappear propagates out of `Task.sleep(nanoseconds:)` as
  /// `CancellationError`, skipping the haptic. Using `try` (not `try?`)
  /// + outer do/catch is load-bearing: `try?` would swallow the
  /// cancellation and fire the haptic into a torn-down view.
  private func runAnimation() async {
    let duration =
      reduceMotion
      ? LaunchAnimationConfig.reducedMotionDuration
      : LaunchAnimationConfig.coldDuration

    // Phase A — settle (0 → 18% of timeline, i.e. ~288 ms at 1.6 s).
    let settleDuration = duration * 0.18
    withAnimation(LaunchAnimationConfig.easeOutPastoral(duration: settleDuration)) {
      settled = true
    }

    // Phase B — haptic landing at 55% (~880 ms at 1.6 s). Skipped under
    // reduce-motion because the compressed timeline doesn't leave a
    // believable "landing" beat for the tactile cue to reinforce.
    if !reduceMotion {
      let hapticDelay = duration * LaunchAnimationConfig.hapticDelayRatio
      let hapticNs = UInt64(hapticDelay * 1_000_000_000)
      do {
        try await Task.sleep(nanoseconds: hapticNs)
        Self.fireLandingHaptic()
      } catch {
        // Task was cancelled — view disappeared before the haptic beat.
        // Intentionally skip the haptic.
      }
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
