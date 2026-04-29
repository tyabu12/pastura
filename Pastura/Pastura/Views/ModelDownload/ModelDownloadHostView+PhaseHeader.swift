import SwiftUI

/// Demo-side composition of the shared `PhaseHeader` component. Lifted
/// into a sibling file so the host view's `chatStream(_:)` body and
/// the host file itself stay under SwiftLint's `function_body_length`
/// and `file_length` ceilings.
///
/// `extendsIntoTopSafeArea: true` is intentional — the demo is
/// presented inside `.fullScreenCover` / the `.needsModelDownload`
/// slot with no system nav bar above it, so the frosted material
/// needs to fill behind the status bar / Dynamic Island. Sim/Results
/// stay at the default `false` because their NavigationStack-pushed
/// nav bar already paints the top safe area. See
/// `Views/Components/PhaseHeader.swift` for the contract.
extension ModelDownloadHostView {

  @ViewBuilder
  func phaseHeader(viewModel: ReplayViewModel) -> some View {
    PhaseHeader(extendsIntoTopSafeArea: true) {
      HStack(alignment: .center, spacing: Spacing.xs) {
        // A 6pt square rotated 45° renders as a diamond. No dedicated shape
        // exists in SwiftUI for a filled diamond, so this is the idiomatic approach.
        Rectangle()
          .fill(Color.moss.opacity(0.7))
          .frame(width: 6, height: 6)
          .rotationEffect(.degrees(45))

        VStack(alignment: .leading, spacing: 3) {
          Text(currentPresetName(viewModel: viewModel).uppercased())
            .textStyle(Typography.tagPhase)
            .foregroundStyle(Color.moss)

          Text(currentPhaseLabel(viewModel: viewModel))
            .textStyle(Typography.titlePhase)
            .foregroundStyle(Color.ink)
        }
      }
    } trailing: {
      Text("DEMO中")
        .textStyle(Typography.metaLabel)
        .foregroundStyle(Color.moss)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
          RoundedRectangle(cornerRadius: Radius.button)
            .fill(Color.moss.opacity(0.1))
        )
    }
  }
}
