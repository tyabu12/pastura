import SwiftUI

/// A single "unused file" row inside the Settings → Models section,
/// rendered for each `OrphanedModelFile` (a `.gguf` on disk that matches
/// no current catalog entry — typically a superseded model's leftover).
///
/// Layout mirrors `ModelSettingsRow`: a leading title + meta stack and a
/// trailing direct trash button. There is only one action (delete), so a
/// direct icon button is used rather than the catalog row's ellipsis Menu.
/// The destructive confirmation is owned by the parent `SettingsView`
/// (`pendingOrphanDelete`), matching the per-model delete flow.
struct OrphanedModelFileRow: View {
  let file: OrphanedModelFile
  let onRequestDelete: () -> Void

  var body: some View {
    HStack(alignment: .top, spacing: Spacing.s) {
      VStack(alignment: .leading, spacing: Spacing.xxs) {
        Text(String(localized: "Unused model file"))
          .font(.system(size: 15, weight: .semibold))
          .foregroundStyle(Color.ink)
        Text(file.fileName)
          .font(.system(size: 12, design: .monospaced))
          .foregroundStyle(Color.muted)
          .lineLimit(1)
          .truncationMode(.middle)
        Text(ModelSettingsRow.formattedFileSize(file.sizeBytes))
          .textStyle(Typography.metaValue)
          .foregroundStyle(Color.metaStrongL3)
          .padding(.top, 2)
      }
      Spacer(minLength: 0)
      Button {
        onRequestDelete()
      } label: {
        Image(systemName: "trash")
          .font(.system(size: 18))
          .padding(.top, 2)
      }
      .buttonStyle(.borderless)
      .foregroundStyle(Color.inkSecondary)
      .accessibilityLabel(
        String(
          format: String(localized: "Delete unused model file, %@"),
          ModelSettingsRow.formattedFileSize(file.sizeBytes)))
    }
    .padding(.vertical, Spacing.xxs)
  }
}
