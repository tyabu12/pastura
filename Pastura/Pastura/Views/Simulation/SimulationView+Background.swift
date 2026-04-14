import SwiftUI

// MARK: - Background continuation toggle
//
// iOS 26+ only — displayed in the control bar when the VM reports
// canEnableBackgroundContinuation (iOS 26+ AND LlamaCppService backend).
// See ADR-003 for the overall design.

extension SimulationView {

  @available(iOS 26, *)
  func backgroundContinuationToggle(viewModel: SimulationViewModel) -> some View {
    Button {
      if viewModel.isBackgroundContinuationEnabled {
        viewModel.disableBackgroundContinuation()
      } else {
        viewModel.enableBackgroundContinuation(
          title: "Pastura simulation",
          subtitle: scenario?.name ?? "Running in background"
        )
      }
    } label: {
      Image(
        systemName: viewModel.isBackgroundContinuationEnabled
          ? "moon.circle.fill" : "moon.circle"
      )
      .font(.title3)
      .foregroundStyle(viewModel.isBackgroundContinuationEnabled ? .blue : .secondary)
    }
    .accessibilityLabel("Background continuation")
    .accessibilityValue(viewModel.isBackgroundContinuationEnabled ? "enabled" : "disabled")
  }
}
