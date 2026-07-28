import SwiftUI

// Language-filter chip row, split out of `SharedScenariosListView` to keep the
// main view under the type_body_length budget — mirrors the sibling
// `+CategoryChips.swift`. `languageChips` is the only entry point the main
// file calls (gated on `viewModel.shouldShowLanguageFilter`, so it's dormant
// while the gallery is single-language); the per-chip helpers stay file-private.
extension SharedScenariosListView {

  /// Horizontal, scrollable language-filter chip row. Mirrors `categoryChips`:
  /// the leading "All" chip clears the filter (`nil`), then one chip per
  /// language actually present in the feed (``GalleryLanguageFilter/options``).
  /// Drives the `selectedLanguage` binding; `visibleScenarios` owns the
  /// filtering. The caller gates this on `shouldShowLanguageFilter`, so the row
  /// never appears while the feed carries a single language.
  func languageChips(
    available: Set<String>, selection: Binding<String?>
  ) -> some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 8) {
        ForEach(GalleryLanguageFilter.options(available: available), id: \.self) { option in
          languageChip(option, selection: selection)
        }
      }
      .padding(.horizontal, PasturaCardMetrics.horizontalMargin)
    }
  }

  private func languageChip(
    _ option: GalleryLanguageFilter, selection: Binding<String?>
  ) -> some View {
    let isSelected = option.selectedLanguage == selection.wrappedValue
    return Button {
      selection.wrappedValue = option.selectedLanguage
    } label: {
      Text(languageChipTitle(option))
        .font(.subheadline.weight(isSelected ? .semibold : .regular))
        // Same contrast-passing pair as the category chips: white-on-mossDark
        // clears WCAG AA where white-on-moss does not (see +CategoryChips).
        .foregroundStyle(isSelected ? Color.inkOnAccent : Color.ink)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(isSelected ? Color.mossDark : Color.bubbleBackground, in: Capsule())
        .overlay(
          Capsule().strokeBorder(
            isSelected ? Color.clear : Color.rule,
            lineWidth: PasturaCardMetrics.chipBorderWidth))
    }
    .buttonStyle(.plain)
    // Mirror the category chips: announce the active filter to VoiceOver since
    // the hand-rolled chips don't get a Picker's free selection announcement.
    .accessibilityAddTraits(isSelected ? [.isSelected] : [])
  }

  private func languageChipTitle(_ option: GalleryLanguageFilter) -> String {
    switch option {
    case .all: return String(localized: "All")
    case .language(let code): return LanguageDisplayName.resolve(code)
    }
  }
}
