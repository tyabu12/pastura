import SwiftUI

/// "Breath" — full-screen launch animation for warm starts (backgrounded < 3 min).
///
/// A single icon layer fades in with a subtle scale pulse that mimics breathing.
/// Composed of three internal keyframe segments:
///
/// 1. `0 → 18%` (~126 ms): scale `.97 → 1.00`, opacity `0 → 1` (appear)
/// 2. `18 → 50%` (~126 → 350 ms): scale `1.00 → 1.02` (inhale)
/// 3. `50 → 72%` (~350 → 504 ms): scale `1.02 → 1.00` (exhale)
///
/// **Exit phase is owned by the parent** via ``AnyTransition/warmSplashExit``
/// — README's 72→100% scale `1.00 → 1.03` + fade-out maps to a SwiftUI
/// `.transition` on `splashKind` removal so the dissolve overlaps cleanly
/// with the post-warm view (typically `HomeView`) becoming interactive.
///
/// No haptic feedback — the animation plays on every foreground return, so
/// a haptic would become intrusive (per the design handoff spec).
///
/// **Reduce Motion:** when `accessibilityReduceMotion` is set, degrades to
/// a simple opacity-only fade-in with no scale change.
struct WarmSplashView: View {
  /// Display name of the launch icon asset (`Assets.xcassets/LaunchIcon.imageset`).
  private static let iconAssetName = "LaunchIcon"

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  // MARK: - Animation state

  // Each flag represents one inflection point in the keyframe timeline.
  // They are toggled in sequence inside `runAnimation()` so SwiftUI's
  // implicit `withAnimation` drives each segment with the correct duration.
  // The dissolve (72→100%) is NOT modelled here — it's the parent's
  // `.transition(.warmSplashExit)` on view removal.
  @State private var appeared = false  // 0% → 18%: fade-in / scale .97 → 1.00
  @State private var inhaled = false  // 18% → 50%: scale 1.00 → 1.02
  @State private var exhaled = false  // 50% → 72%: scale 1.02 → 1.00

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
        .opacity(appeared ? 1 : 0)
    }
    .task { await runAnimation() }
  }

  // MARK: - Derived animation values

  private var iconScale: CGFloat {
    if exhaled { return 1.00 }  // 72%: back to rest after exhale (final hold)
    if inhaled { return 1.02 }  // 50%: peak inhale
    if appeared { return 1.00 }  // 18%: settled after fade-in
    return 0.97  // 0%: start compressed
  }

  // MARK: - Timeline

  /// Runs the warm-start animation. Phases match the README "Breath"
  /// keyframes, EXCLUDING the 72→100% dissolve (delegated to the parent
  /// via ``AnyTransition/warmSplashExit``). All segments use easeStandard
  /// (cubic-bezier(.4, 0, .2, 1)) per the spec.
  ///
  /// Reduce-motion path collapses to a single easeStandard opacity fade-in
  /// at ``LaunchAnimationConfig/reducedMotionDuration`` — the dissolve is
  /// still the parent's responsibility.
  private func runAnimation() async {
    if reduceMotion {
      withAnimation(
        LaunchAnimationConfig.easeStandard(
          duration: LaunchAnimationConfig.reducedMotionDuration)
      ) {
        appeared = true
      }
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
    let inhaleDelayNs = UInt64(appearDuration * 1_000_000_000)
    try? await Task.sleep(nanoseconds: inhaleDelayNs)
    withAnimation(LaunchAnimationConfig.easeStandard(duration: inhaleDuration)) {
      inhaled = true
    }

    // Segment 3 — exhale (50 → 72%, ~154 ms): scale 1.02 → 1.00
    let exhaleDuration = total * 0.22
    let exhaleDelayNs = UInt64(inhaleDuration * 1_000_000_000)
    try? await Task.sleep(nanoseconds: exhaleDelayNs)
    withAnimation(LaunchAnimationConfig.easeStandard(duration: exhaleDuration)) {
      exhaled = true
    }

    // Segment 4 — dissolve (72 → 100%) is parent-owned (.warmSplashExit).
  }
}

/// `.transition` describing the warm splash's dissolve per the README
/// 72→100% keyframes: scale `1.00 → 1.03` + opacity `1 → 0`. Apply at the
/// callsite (`RootView`) so removing `splashKind` plays the dissolve.
extension AnyTransition {
  static var warmSplashExit: AnyTransition {
    .scale(scale: 1.03, anchor: .center)
      .combined(with: .opacity)
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
