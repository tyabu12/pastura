import SwiftUI

/// Fullscreen overlay shown while `ReplayViewModel.state == .transitioning`.
///
/// Per `demo-replay-ui.md` §DLCompleteOverlay: ultra-thin material
/// background + pulsing 44 pt dog mark + "Setup complete" +
/// "Tap anywhere to begin". The hint text is now load-bearing — the
/// overlay waits for a user tap before transitioning to `HomeView` so
/// the user gets a clear "setup complete" beat instead of waking up on
/// the home screen mid-task. (Spec §2 decision 6 / 8 originally
/// specified auto-only and called the hint "draft" / removable in copy
/// pass; that proved confusing in real-device QA — a tap acknowledgment
/// is the right UX. ADR-007 §3.3 (d) updated to match.)
///
/// Fade-in is `.easeOut(2.4s, delay: 0.2s)` by default. Under
/// `accessibilityReduceMotion`, the overlay is shown at full opacity
/// immediately and the dog mark does not pulse (handled inside
/// `DogMark.pulsing()`). Tap is enabled from the moment the view
/// appears in either case — a user who wants to skip the fade can
/// tap during it and the transition fires immediately.
///
/// Lives in its own file so `ModelDownloadHostView.swift` stays under
/// swiftlint's 400-line `file_length` cap. Visibility is `internal`
/// (default) so the host view in the same module can reach it.
struct DLCompleteOverlay: View {
  /// Pre-fade hold before the overlay starts animating to opaque. Matches
  /// the reference HTML's tactile "settling" beat.
  static let fadeDelayMs: Int = 200
  /// Ease-out fade-in duration; the overlay is fully opaque at
  /// `fadeDelayMs + fadeDurationMs`.
  static let fadeDurationMs: Int = 2400

  let onTap: () -> Void

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
        Text(String(localized: "Setup complete"))
          .textStyle(Typography.statusComplete)
          .foregroundStyle(Color.mossInk)
        // The tap this line names is how the overlay is dismissed, so it is an
        // instruction the flow does not advance without — off §8's quietude
        // tier. Audit class A2: `docs/design/muted-application-audit.md`.
        //
        // **Argued by direction, not measured**: `.ultraThinMaterial` above
        // composites at render time, so no static ratio exists here and no
        // fixture can pin it. The direction argument is at ledger §3.3; the
        // verdict is ADR-028 gate 4 device QA.
        Text(String(localized: "Tap anywhere to begin"))
          .textStyle(Typography.statusHint)
          .foregroundStyle(Color.inkSecondary)
      }
    }
    .opacity(hasAppeared || reduceMotion ? 1 : 0)
    // Full-area tap: `contentShape(Rectangle())` makes the entire
    // ZStack hit-testable (the `.ultraThinMaterial` Rectangle alone
    // would be tappable, but explicit `contentShape` documents intent
    // and protects against future layout changes).
    .contentShape(Rectangle())
    .onTapGesture { onTap() }
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
    DLCompleteOverlay(onTap: {})
  }
}
