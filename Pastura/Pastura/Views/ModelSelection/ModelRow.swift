import SwiftUI

/// A single tappable row in the model picker. The row IS the selection
/// affordance — tapping anywhere on the row body flips `selected` to this
/// descriptor's id. The download CTA is a separate, screen-bottom Sticky
/// Band element owned by `ModelPickerView`.
///
/// Visual structure (per design-handoff):
///
/// ```
///  ┌───────────────────────────────────────────────────┐
///  │ ┃ [sheep]  Gemma 4 E2B  [推奨]                  ◉ │
///  │ ┃          Google · 3.1 GB                        │
///  │ ┃          Balanced choice. Rich, considered…    │
///  └───────────────────────────────────────────────────┘
/// ```
///
/// The left selection tab (┃) is moss-colored when `isSelected`, hidden
/// otherwise. The trailing `CheckBadge` echoes the same state.
///
/// Accessibility: the row is a single combined element with
/// `.isButton` always and `.isSelected` when selected — VoiceOver
/// announces displayName + size + (optional) "Recommended" tag +
/// tagline as one unit. The decorative SheepAvatar, LeafGlyph-style
/// recommended-tag dot, and CheckBadge are all `.accessibilityHidden`.
struct ModelRow: View {
  let descriptor: ModelDescriptor
  let isSelected: Bool
  let isRecommended: Bool
  let onTap: () -> Void

  // MARK: - Body

  var body: some View {
    HStack(alignment: .top, spacing: 14) {
      avatar
      content
      Spacer(minLength: 8)
      CheckBadge(filled: isSelected)
        .padding(.top, 2)  // optical centering with title baseline
    }
    .padding(.leading, 16)
    .padding(.trailing, 18)
    .padding(.vertical, 18)
    .frame(minHeight: 80, alignment: .top)
    .background(
      isSelected
        ? Color.moss.opacity(0.06)
        : Color.clear
    )
    .overlay(alignment: .leading) {
      // 3pt left selection tab — only visible when selected. 12pt vertical
      // inset so the tab doesn't touch the divider lines above/below.
      if isSelected {
        RoundedRectangle(cornerRadius: 1, style: .continuous)
          .fill(Color.moss)
          .frame(width: 3)
          .padding(.vertical, 12)
      }
    }
    .contentShape(Rectangle())
    .onTapGesture {
      onTap()
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(
      Self.accessibilityLabel(
        for: descriptor,
        sizeFormatted: Self.formattedFileSize(descriptor.fileSize),
        isRecommended: isRecommended)
    )
    .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
  }

  // MARK: - Subviews

  /// Avatar: 48pt circle with a 40pt sheep silhouette inside. Existing
  /// `SheepAvatar` is reused — Gemma → cream wool (.alice), Qwen →
  /// sage wool (.bob). Other descriptors fall back to a name-derived
  /// character via the existing `forAgent` resolver.
  private var avatar: some View {
    ZStack {
      Circle()
        .fill(Color.moss.opacity(0.08))
      SheepAvatar(character: Self.character(for: descriptor), size: 40)
    }
    .frame(width: 48, height: 48)
    .accessibilityHidden(true)
  }

  /// Title + meta + (optional) tagline. Tagline row is suppressed when
  /// empty so the VStack spacing doesn't leave a blank line beneath
  /// the meta — fixture / test descriptors that don't set `tagline`
  /// shouldn't visually look "almost like" a production row.
  private var content: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Text(descriptor.shortDisplayName ?? descriptor.displayName)
          .font(.system(size: 16, weight: .semibold))
          .tracking(-0.005 * 16)
          .foregroundStyle(Color.ink)
          .lineLimit(1)
        if isRecommended {
          recommendedTag
        }
      }
      HStack(spacing: 4) {
        Text(descriptor.vendor)
        Text(verbatim: "·").opacity(0.5)
        Text(Self.formattedFileSize(descriptor.fileSize))
      }
      .font(.system(size: 11.5, design: .monospaced))
      .foregroundStyle(Color.muted)

      if !descriptor.tagline.isEmpty {
        Text(descriptor.tagline)
          .font(.system(size: 12.5))
          .lineSpacing(12.5 * 0.55)  // line-height 1.55
          .foregroundStyle(Color.inkSecondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  /// The "推奨" tag. Reuses the existing `tagPhase` typography token
  /// (mono 9.5pt, 0.22em tracking, uppercase) from DesignTokens. Color
  /// `mossOnWash` over a `moss` @0.12 chip on the card ground — `mossDark` was the
  /// original choice but measured ≈4.23:1 in light, under the 4.5:1 bar at
  /// this size; the role token reads ≈6.24:1 (#1327).
  private var recommendedTag: some View {
    Text(String(localized: "Recommended"))
      .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
      .tracking(0.22 * 9.5)
      .textCase(.uppercase)
      .foregroundStyle(Color.mossOnWash)
      .padding(.horizontal, 7)
      .padding(.vertical, 2)
      .background(
        RoundedRectangle(cornerRadius: 4, style: .continuous)
          .fill(Color.moss.opacity(0.12))
      )
      .accessibilityHidden(true)  // surfaced via the row's combined a11y label
  }

  // MARK: - Pure helpers (extracted for unit-tests)

  /// Builds the combined VoiceOver label for a row. Pure-input so
  /// tests can assert the label contains both displayName and size
  /// without rendering the View (ADR-009 — no ViewInspector).
  ///
  /// The label is ordered: displayName, [Recommended if isRecommended],
  /// size, tagline (if non-empty). VoiceOver users hear the primary
  /// identity first, then context.
  nonisolated static func accessibilityLabel(
    for descriptor: ModelDescriptor,
    sizeFormatted: String,
    isRecommended: Bool
  ) -> String {
    var fragments: [String] = [descriptor.shortDisplayName ?? descriptor.displayName]
    if isRecommended {
      fragments.append(String(localized: "Recommended"))
    }
    fragments.append(sizeFormatted)
    if !descriptor.tagline.isEmpty {
      fragments.append(descriptor.tagline)
    }
    return fragments.joined(separator: ", ")
  }

  /// Decimal-GB size formatted via `ByteCountFormatter` — matches the
  /// format the row's visible meta line uses, so VoiceOver and visual
  /// stay aligned ("3.1 GB" not "3,106,735,776 bytes").
  nonisolated static func formattedFileSize(_ bytes: Int64) -> String {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    formatter.allowedUnits = [.useGB]
    formatter.includesUnit = true
    return formatter.string(fromByteCount: bytes)
  }

  /// Maps a descriptor to one of the existing SheepAvatar character
  /// palettes. Gemma → cream wool (.alice), Qwen → sage wool (.bob).
  /// Unknown descriptors fall back to a name-derived character via
  /// the existing `forAgent` resolver so the row never renders a
  /// missing avatar.
  nonisolated static func character(for descriptor: ModelDescriptor) -> SheepAvatar.Character {
    switch descriptor.id {
    case ModelRegistry.gemma4E2B.id: return .alice
    case ModelRegistry.qwen34B.id: return .bob
    default: return SheepAvatar.Character.forAgent(descriptor.displayName)
    }
  }
}

// MARK: - Previews

#Preview("Selected — recommended") {
  ModelRow(
    descriptor: ModelRegistry.gemma4E2B,
    isSelected: true,
    isRecommended: true,
    onTap: {}
  )
  .background(Color.bubbleBackground)
}

#Preview("Unselected — not recommended") {
  ModelRow(
    descriptor: ModelRegistry.qwen34B,
    isSelected: false,
    isRecommended: false,
    onTap: {}
  )
  .background(Color.bubbleBackground)
}

#Preview("Empty tagline (test fixture shape)") {
  // A descriptor without tagline shouldn't leave a blank line below the
  // meta row. Preview proves the conditional gate works visually.
  let bare = ModelDescriptor(
    id: "test-bare",
    displayName: "Test Bare Model (Q4_K_M)",
    vendor: "Test",
    vendorURL: URL(string: "https://example.com")!,
    downloadURL: URL(string: "https://example.com/bare.gguf")!,
    fileName: "bare.gguf",
    fileSize: 1_000_000_000,
    sha256: "",
    stopSequence: "<|im_end|>",
    minRAM: 6_500_000_000,
    modelInfoURL: URL(string: "https://example.com")!,
    systemPromptSuffix: nil
  )
  return ModelRow(
    descriptor: bare,
    isSelected: false,
    isRecommended: false,
    onTap: {}
  )
  .background(Color.bubbleBackground)
}
