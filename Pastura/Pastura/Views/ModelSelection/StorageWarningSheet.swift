import SwiftUI

/// A 320pt detent-sized confirmation sheet presented when the user taps
/// "Download" on the picker but free space sits below
/// `modelSize + ModelManager.lowStorageMarginBytes`. Normal flow skips
/// this sheet entirely — only the low-storage path opts in.
///
/// Carries `.deepLinkGated()` on the content root so a `pastura://`
/// deep-link arriving during the sheet queues at `DeepLinkGate`
/// (parity with the cellular consent dialog at `PasturaApp.swift:537`).
struct StorageWarningSheet: View {
  let descriptor: ModelDescriptor
  let onCancel: () -> Void
  let onProceed: () -> Void

  // Reuses `ModelRow.formattedFileSize` so the sheet's body and the row's
  // visible meta line share one source-of-truth for "how the picker
  // formats a model size."
  private var sizeString: String {
    ModelRow.formattedFileSize(descriptor.fileSize)
  }

  private var displayName: String {
    descriptor.shortDisplayName ?? descriptor.displayName
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text(String(localized: "STORAGE"))
        .font(.system(size: 10, weight: .semibold, design: .monospaced))
        .tracking(0.22 * 10)  // letter-spacing 0.22em at 10pt
        .foregroundStyle(Color.mossDark)

      Text(String(localized: "Storage is running low"))
        .font(.system(size: 18, weight: .semibold))
        .foregroundStyle(Color.ink)

      Text(
        String(
          format: String(
            localized: "%@ needs about %@. Continue, or choose a lighter model?"),
          displayName,
          sizeString
        )
      )
      .font(.system(size: 13))
      .lineSpacing(13 * 0.7)  // line-height 1.7 → +0.7 of font size between lines
      .foregroundStyle(Color.inkSecondary)
      .fixedSize(horizontal: false, vertical: true)

      Spacer(minLength: 0)

      Button(action: onProceed) {
        Text(String(localized: "Download anyway"))
          .font(.system(size: 16, weight: .semibold))
          .tracking(0.02 * 16)
          .foregroundStyle(Color.screenBackground)
          .frame(maxWidth: .infinity)
          .frame(height: 52)
          .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
              .fill(Color.mossInk))
      }
      .buttonStyle(.plain)
      .accessibilityLabel(
        String(
          format: String(
            localized: "Download %@ anyway, %@"),
          displayName,
          sizeString))

      Button(action: onCancel) {
        Text(String(localized: "Cancel"))
          .font(.system(size: 15, weight: .medium))
          .foregroundStyle(Color.inkSecondary)
          .frame(maxWidth: .infinity)
          .frame(height: 48)
      }
      .buttonStyle(.plain)
    }
    .padding(.horizontal, 22)
    .padding(.top, 24)
    .padding(.bottom, 36)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.screenBackground)
    .presentationDetents([.height(320)])
    .presentationDragIndicator(.visible)
    .deepLinkGated()
  }
}

#Preview {
  // Bring up the sheet inline so the preview shows the layout without
  // requiring a `.sheet` host. Production presents this via
  // `.sheet(item:)` in `ModelPickerView`.
  StorageWarningSheet(
    descriptor: ModelRegistry.gemma4E2B,
    onCancel: {},
    onProceed: {}
  )
  .environment(DeepLinkGate())
}
