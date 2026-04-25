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
      withAnimation(.easeOut(duration: 2.4).delay(0.2)) {
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
