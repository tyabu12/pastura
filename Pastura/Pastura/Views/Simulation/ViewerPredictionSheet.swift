import SwiftUI

/// Layout / timing constants for ``ViewerPredictionSheet`` (#915).
///
/// Extracted so the code-review-gated countdown length has a change-detector
/// unit test (`.claude/rules/view-testing.md`) — a failure means the value
/// drifted, not that anything is broken.
nonisolated enum ViewerPredictionSheetLayout {
  /// Seconds before the sheet auto-skips. Kept short so it never stalls the
  /// viewing rhythm the prediction interrupts.
  static let countdownSeconds = 15
}

/// Modal shown before the first vote reveal, asking the viewer to predict the
/// outcome (#915). Resolves exactly once with the picked agent or `.skipped`
/// (explicit skip, or the countdown reaching zero). The ViewModel owns
/// presentation and awaits the resolution to score + persist — see
/// `SimulationViewModel`.
///
/// The countdown decrements a discrete per-second `Int` rather than driving a
/// continuous `CAAnimation`, so it does not trip the XCUITest idle-stall trap
/// (`.claude/rules/xcodebuild-cli.md`).
struct ViewerPredictionSheet: View {
  /// How the viewer resolved the prompt.
  enum Resolution: Equatable {
    case predicted(String)
    case skipped
  }

  let question: ViewerPredictionLogic.Question
  let candidates: [String]
  let onResolve: (Resolution) -> Void

  @State private var remaining = ViewerPredictionSheetLayout.countdownSeconds
  @State private var didResolve = false

  var body: some View {
    VStack(spacing: 24) {
      header
      candidateList
      skipButton
    }
    .padding(24)
    .frame(maxWidth: .infinity)
    .background(Color.page)
    .task { await runCountdown() }
    .interactiveDismissDisabled()
  }

  private var header: some View {
    VStack(spacing: 8) {
      Text(String(localized: "Make your prediction"))
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(Color.muted)
      Text(promptText)
        .font(.title3.weight(.semibold))
        .foregroundStyle(Color.ink)
        .multilineTextAlignment(.center)
      Text(String(format: String(localized: "%lld s left"), remaining))
        .font(.caption.monospacedDigit())
        .foregroundStyle(Color.muted)
        .accessibilityIdentifier("prediction.countdown")
    }
  }

  private var promptText: String {
    switch question {
    case .wolf:
      return String(localized: "Who do you think the wolf is?")
    case .topVote:
      return String(localized: "Who do you think will get the most votes?")
    }
  }

  private var candidateList: some View {
    VStack(spacing: 10) {
      ForEach(Array(candidates.enumerated()), id: \.element) { index, name in
        Button {
          resolve(.predicted(name))
        } label: {
          HStack(spacing: 12) {
            SheepAvatar(character: .forAgent(name, position: index), size: 32)
            Text(name)
              .font(.body.weight(.medium))
              .foregroundStyle(Color.ink)
            Spacer()
          }
          .padding(.horizontal, 16)
          .padding(.vertical, 12)
          .frame(maxWidth: .infinity)
          .background(
            RoundedRectangle(cornerRadius: 14)
              .fill(Color.bubbleBackground)
              .overlay(
                RoundedRectangle(cornerRadius: 14)
                  .strokeBorder(Color.rule, lineWidth: 1))
          )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("prediction.candidate.\(name)")
      }
    }
  }

  private var skipButton: some View {
    Button(String(localized: "Skip")) {
      resolve(.skipped)
    }
    .font(.body.weight(.medium))
    .foregroundStyle(Color.link)
    .accessibilityIdentifier("prediction.skipButton")
  }

  /// Fires `onResolve` at most once — guards the tap-vs-timeout race.
  private func resolve(_ resolution: Resolution) {
    guard !didResolve else { return }
    didResolve = true
    onResolve(resolution)
  }

  /// Ticks the countdown once per second; auto-skips at zero. Cancelled with
  /// the view (`.task`), so dismissing the sheet stops the timer cleanly.
  private func runCountdown() async {
    while remaining > 0 {
      try? await Task.sleep(for: .seconds(1))
      if didResolve || Task.isCancelled { return }
      remaining -= 1
    }
    resolve(.skipped)
  }
}
