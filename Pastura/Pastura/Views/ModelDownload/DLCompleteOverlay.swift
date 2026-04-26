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
  /// Time the overlay holds at full opacity *after* the fade-in completes,
  /// so the user can perceive "準備ができました" before `HomeView` swaps
  /// in. Without this dwell, ease-out's slow approach to 1.0 means the
  /// overlay reaches full opacity at the same instant it gets unmounted,
  /// leaving the user with no visible "Ready" beat.
  static let dwellMs: Int = 1500
  /// Total time the overlay needs to be visually held before unmounting
  /// is safe — used by `DemoReplayHostView` to gate the ready-handoff so
  /// `RootView` doesn't swap in `HomeView` while the overlay is fading
  /// in or before the dwell completes. Single source of truth for both
  /// the animation literals here and the upstream wait.
  static let totalAnimationMs: Int = fadeDelayMs + fadeDurationMs + dwellMs
  /// Wait used when `accessibilityReduceMotion` is on: the overlay shows
  /// at full opacity instantly, so the long fade timing is suppressed.
  /// We hold for `dwellMs` so the perceptible "Ready" beat matches the
  /// non-reduce-motion path's dwell — accessibility users still get
  /// time to read the copy, just without the fade animation.
  static let reducedMotionHoldMs: Int = dwellMs

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
