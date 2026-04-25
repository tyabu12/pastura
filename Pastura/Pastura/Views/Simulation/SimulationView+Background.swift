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
      // §2.3: enabled ステータスは moss-dark（DL進捗ドット点灯と同じ「点灯」用途）、
      // disabled は muted（メタ情報の薄色）で消灯感を出す。`.blue / .secondary`
      // はデザインシステムの飽和色禁則（§1）と Pastura パレット非準拠で置換。
      .foregroundStyle(viewModel.isBackgroundContinuationEnabled ? Color.mossDark : Color.muted)
    }
    .accessibilityLabel("Background continuation")
    .accessibilityValue(viewModel.isBackgroundContinuationEnabled ? "enabled" : "disabled")
  }
}
