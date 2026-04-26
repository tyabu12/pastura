import SwiftUI

/// Fullscreen overlay shown while `ReplayViewModel.state == .transitioning`.
///
/// Per `demo-replay-ui.md` §DLCompleteOverlay: ultra-thin material
/// background + pulsing 44 pt dog mark + "準備ができました" +
/// "tap anywhere to begin". Spec §2 decision 6 / 8 makes the transition
/// auto-only — the hint text is visual only and no tap handler is wired.
///
/// Fade-in is `.easeOut(2.4s, delay: 0.2s)` by default. Under
/// `accessibilityReduceMotion`, the overlay is shown at full opacity
/// immediately and the dog mark does not pulse (handled inside
/// `DogMark.pulsing()`).
///
/// Lives in its own file so `DemoReplayHostView.swift` stays under
/// swiftlint's 400-line `file_length` cap. Visibility is `internal`
/// (default) so the host view in the same module can reach it.
struct DLCompleteOverlay: View {
  /// Pre-fade hold before the overlay starts animating to opaque. Matches
  /// the reference HTML's tactile "settling" beat.
  static let fadeDelayMs: Int = 200
  /// Ease-out fade-in duration; the overlay is fully opaque at
  /// `fadeDelayMs + fadeDurationMs`.
  static let fadeDurationMs: Int = 2400
  /// Total time the overlay needs to be visually held before unmounting
  /// is safe — used by `DemoReplayHostView` to gate the ready-handoff
  /// so `RootView` doesn't swap in `HomeView` mid-fade. Single source of
  /// truth for both the animation literals here and the upstream wait.
  static let totalAnimationMs: Int = fadeDelayMs + fadeDurationMs
  /// Wait used when `accessibilityReduceMotion` is on: the overlay shows
  /// at full opacity instantly, so the long fade timing is meaningless,
  /// but a brief perceptible hold is still needed so the overlay doesn't
  /// snap-show-snap. Value chosen by UX judgment — not in any spec.
  static let reducedMotionHoldMs: Int = 600

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var hasAppeared = false

  var body: some View {
    ZStack {
      Rectangle()
        .fill(.ultraThinMaterial)
        .ignoresSafeArea()

      VStack(spacing: Spacing.s) {
        DogMark(size: 44)
          .pulsing()
        Text("準備ができました")
          .textStyle(Typography.statusComplete)
          .foregroundStyle(Color.mossInk)
        Text("tap anywhere to begin")
          .textStyle(Typography.statusHint)
          .foregroundStyle(Color.muted)
      }
    }
    .opacity(hasAppeared || reduceMotion ? 1 : 0)
    .onAppear {
      guard !reduceMotion else {
        hasAppeared = true
        return
      }
      withAnimation(
        .easeOut(duration: Double(Self.fadeDurationMs) / 1000)
          .delay(Double(Self.fadeDelayMs) / 1000)
      ) {
        hasAppeared = true
      }
    }
  }
}

#Preview("DLCompleteOverlay") {
  ZStack {
    Color.screenBackground.ignoresSafeArea()
    DLCompleteOverlay()
  }
}
