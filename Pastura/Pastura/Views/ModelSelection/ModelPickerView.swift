import SwiftUI

/// First-launch model picker. Shown when `AppState == .needsModelSelection`.
///
/// Gated by `ModelManager.shouldShowInitialModelPicker` — a returning user
/// with any persisted active id bypasses this screen entirely, as do
/// unsupported-device users (they fall through to the existing
/// `.needsModelDownload` unsupported UI).
///
/// ## Hosting
///
/// Rendered directly inside `RootView.mainContent` — **outside** the root
/// `NavigationStack`. Per `.claude/rules/navigation.md`, any view pushed
/// onto the root stack must not add its own `navigationDestination`;
/// this picker sidesteps the constraint by not being pushed at all.
///
/// ## Interaction
///
/// Tapping a row's "Start with this model" button calls `onSelect` with
/// the descriptor id. The caller (PasturaApp's RootView) persists the
/// selection via `modelManager.setActiveModel(_:)` and transitions
/// `AppState` to `.needsModelDownload`, which starts the chosen model's
/// download.
///
/// ## Design system
///
/// Styled per `docs/design/design-system.md` — moss accent for the CTA,
/// Warm Gray ink for text, file size / vendor surfaced openly
/// ("technology honesty" — don't hide the ~3 GB download behind euphemism).
struct ModelPickerView: View {
  let modelManager: ModelManager
  let onSelect: (ModelID) -> Void

  var body: some View {
    ZStack {
      Color.screenBackground.ignoresSafeArea()
      ScrollView {
        VStack(alignment: .leading, spacing: Spacing.xl) {
          header
          VStack(spacing: Spacing.s) {
            ForEach(modelManager.catalog, id: \.id) { descriptor in
              ModelPickerRow(descriptor: descriptor) {
                onSelect(descriptor.id)
              }
            }
          }
          footer
        }
        .padding(.horizontal, Spacing.l)
        .padding(.vertical, Spacing.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: Spacing.xs) {
      Text(String(localized: "Choose a model to start"))
        .font(.system(size: 22, weight: .semibold))
        .foregroundStyle(Color.ink)
      Text(
        String(
          localized:
            "Pastura runs the conversation on your iPhone. Pick the model you'd like to download first — you can add the other one later from Settings."
        )
      )
      .textStyle(Typography.bodyPromo)
      .foregroundStyle(Color.inkSecondary)
    }
  }

  private var footer: some View {
    Text(String(localized: "Nothing is sent to a server. The model lives on this device."))
      .textStyle(Typography.bodyPromo)
      .foregroundStyle(Color.muted)
  }
}

// MARK: - Row

private struct ModelPickerRow: View {
  let descriptor: ModelDescriptor
  let onSelect: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.s) {
      VStack(alignment: .leading, spacing: Spacing.xxs) {
        Text(descriptor.displayName)
          .font(.system(size: 17, weight: .semibold))
          .foregroundStyle(Color.ink)
        HStack(spacing: Spacing.xs) {
          Text(descriptor.vendor)
            .textStyle(Typography.bodyPromo)
            .foregroundStyle(Color.inkSecondary)
          // Use a low-key interpunct rather than a slash — softer visual
          // separator that matches the "quietude" principle.
          Text("·")
            .foregroundStyle(Color.muted)
          Text(Self.formattedFileSize(descriptor.fileSize))
            .textStyle(Typography.metaValue)
            .foregroundStyle(Color.metaStrongL3)
        }
      }
      if let hint = Self.hint(for: descriptor) {
        Text(hint)
          .textStyle(Typography.bodyPromo)
          .foregroundStyle(Color.inkSecondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      Button(action: onSelect) {
        Text(String(localized: "Start with this model"))
          .font(.system(size: 14, weight: .semibold))
          .foregroundStyle(Color.white)
          .frame(maxWidth: .infinity)
          .padding(.vertical, Spacing.s)
          .background(
            RoundedRectangle(cornerRadius: Radius.button)
              .fill(Color.moss))
      }
      .buttonStyle(.plain)
      .accessibilityLabel(
        String(
          localized:
            "Start with \(descriptor.displayName), \(Self.formattedFileSize(descriptor.fileSize)) download"
        ))
    }
    .padding(Spacing.l)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      RoundedRectangle(cornerRadius: Radius.promo)
        .fill(Color.bubbleBackground)
    )
    .overlay(
      RoundedRectangle(cornerRadius: Radius.promo)
        .stroke(Color.rule, lineWidth: 1))
  }

  /// Decimal GB with 1 decimal (e.g. "3.1 GB"). `ByteCountFormatter` with
  /// `.file` picks user-intuitive units and is what iOS surfaces in
  /// Settings → General → Storage.
  private static func formattedFileSize(_ bytes: Int64) -> String {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    formatter.allowedUnits = [.useGB]
    formatter.includesUnit = true
    return formatter.string(fromByteCount: bytes)
  }

  /// Surface a single descriptor-driven hint below the meta row. Today
  /// only Qwen carries `/no_think`; future descriptors without it get
  /// no hint rather than generic filler.
  private static func hint(for descriptor: ModelDescriptor) -> String? {
    if descriptor.systemPromptSuffix == "/no_think" {
      return String(
        localized: "Lightweight reasoning mode — faster responses, leaner footprint.")
    }
    return nil
  }
}
