import SwiftUI

/// "Breath" — full-screen launch animation for warm starts (backgrounded < 3 min).
///
/// A single icon layer fades in with a subtle scale pulse that mimics breathing,
/// then dissolves out. Composed of five keyframe segments that together span
/// ``LaunchAnimationConfig/warmDuration`` (0.7 s):
///
/// 1. `0 → 18%` (~126 ms): scale `.97 → 1.00`, opacity `0 → 1` (appear)
/// 2. `18 → 50%` (~126 → 350 ms): scale `1.00 → 1.02` (inhale)
/// 3. `50 → 72%` (~350 → 504 ms): scale `1.02 → 1.00` (exhale)
/// 4. `72 → 100%` (~504 → 700 ms): scale `1.00 → 1.03`, opacity `1 → 0` (dissolve)
///
/// No haptic feedback — the animation plays on every foreground return, so
/// a haptic would become intrusive (per the design handoff spec).
///
/// **Reduce Motion:** when `accessibilityReduceMotion` is set, degrades to a
/// simple 400 ms cross-fade with no scale change.
struct WarmSplashView: View {
  /// Display name of the launch icon asset (`Assets.xcassets/LaunchIcon.imageset`).
  private static let iconAssetName = "LaunchIcon"

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  // MARK: - Animation state

  // Each flag represents one inflection point in the keyframe timeline.
  // They are toggled in sequence inside `runAnimation()` so SwiftUI's
  // implicit `withAnimation` drives each segment with the correct duration.
  @State private var appeared = false  // 0% → 18%: fade-in / scale .97 → 1.00
  @State private var inhaled = false  // 18% → 50%: scale 1.00 → 1.02
  @State private var exhaled = false  // 50% → 72%: scale 1.02 → 1.00
  @State private var dissolved = false  // 72% → 100%: scale 1.00 → 1.03 + fade-out

  var body: some View {
    ZStack {
      LaunchAnimationConfig.backgroundColor
        .ignoresSafeArea()

      Image(Self.iconAssetName)
        .resizable()
        .scaledToFit()
        .clipShape(
          RoundedRectangle(cornerRadius: LaunchAnimationConfig.iconCornerRadius)
        )
        .frame(
          width: LaunchAnimationConfig.iconSize,
          height: LaunchAnimationConfig.iconSize
        )
        .scaleEffect(reduceMotion ? 1 : iconScale)
        .opacity(iconOpacity)
    }
    .task { await runAnimation() }
  }

  // MARK: - Derived animation values

  private var iconScale: CGFloat {
    if dissolved { return 1.03 }  // 100%: dissolve overshoot
    if exhaled { return 1.00 }  // 72%: back to rest after exhale
    if inhaled { return 1.02 }  // 50%: peak inhale
    if appeared { return 1.00 }  // 18%: settled after fade-in
    return 0.97  // 0%: start compressed
  }

  private var iconOpacity: Double {
    if dissolved { return 0 }  // 100%: fully dissolved
    if appeared { return 1 }  // 18%–72%: fully visible
    return 0  // 0%: invisible before appear
  }

  // MARK: - Timeline

  /// Runs the warm-start animation. Phases match the README "Breath" keyframes.
  /// All segments use `easeStandard` (cubic-bezier(.4, 0, .2, 1)) per the spec.
  ///
  /// Reduce-motion path collapses to a single `easeStandard` opacity crossfade
  /// at ``LaunchAnimationConfig/reducedMotionDuration``.
  private func runAnimation() async {
    if reduceMotion {
      await runReducedMotionAnimation()
      return
    }

    let total = LaunchAnimationConfig.warmDuration

    // Segment 1 — appear (0 → 18%, ~126 ms): scale .97 → 1.00, opacity 0 → 1
    let appearDuration = total * 0.18
    withAnimation(LaunchAnimationConfig.easeStandard(duration: appearDuration)) {
      appeared = true
    }

    // Segment 2 — inhale (18 → 50%, ~224 ms): scale 1.00 → 1.02
    let inhaleDuration = total * 0.32
    let inhaleDelay = appearDuration
    let inhaleNs = UInt64(inhaleDelay * 1_000_000_000)
    try? await Task.sleep(nanoseconds: inhaleNs)
    withAnimation(LaunchAnimationConfig.easeStandard(duration: inhaleDuration)) {
      inhaled = true
    }

    // Segment 3 — exhale (50 → 72%, ~154 ms): scale 1.02 → 1.00
    let exhaleDuration = total * 0.22
    let exhaleDelay = inhaleDuration
    let exhaleNs = UInt64(exhaleDelay * 1_000_000_000)
    try? await Task.sleep(nanoseconds: exhaleNs)
    withAnimation(LaunchAnimationConfig.easeStandard(duration: exhaleDuration)) {
      exhaled = true
    }

    // Segment 4 — dissolve (72 → 100%, ~196 ms): scale 1.00 → 1.03, opacity 1 → 0
    let dissolveDuration = total * 0.28
    let dissolveDelay = exhaleDuration
    let dissolveNs = UInt64(dissolveDelay * 1_000_000_000)
    try? await Task.sleep(nanoseconds: dissolveNs)
    withAnimation(LaunchAnimationConfig.easeStandard(duration: dissolveDuration)) {
      dissolved = true
    }
  }

  /// Reduce-motion fallback: single opacity crossfade, no scale.
  private func runReducedMotionAnimation() async {
    let duration = LaunchAnimationConfig.reducedMotionDuration

    // Fade in over first half, hold, then fade out.
    withAnimation(LaunchAnimationConfig.easeStandard(duration: duration * 0.5)) {
      appeared = true
    }

    let holdNs = UInt64(duration * 0.5 * 1_000_000_000)
    try? await Task.sleep(nanoseconds: holdNs)
    withAnimation(LaunchAnimationConfig.easeStandard(duration: duration * 0.5)) {
      dissolved = true
    }
  }
}

#Preview("Warm splash") {
  WarmSplashView()
}

// Reduce-motion variant intentionally not previewed — Swift 6 makes
// `\.accessibilityReduceMotion` read-only, so the override won't compile
// (memory `reference_swift6_accessibility_env_readonly.md`). To verify the
// fallback, toggle Settings → Accessibility → Reduce Motion on the
// simulator and relaunch the app.
