import SwiftUI

// Compact language-filter menu for the Browse tab, split out of
// `SharedScenariosListView` to keep the main view under the type_body_length
// budget — mirrors the sibling `+CategoryChips.swift`.
// `languageMenu(viewModel:)` is the only entry point the main file calls; it is
// mounted as a top-trailing toolbar item gated on
// `viewModel.shouldShowLanguageFilter`, so it never appears while the feed
// carries a single language. The per-item helpers stay file-private.
extension SharedScenariosListView {

  /// Compact top-trailing toolbar `Menu` for the language filter. Lists one
  /// button per language actually present in the feed
  /// (``GalleryLanguageFilter/options``) in canonical order, then a divider and
  /// a trailing "All" button that clears the filter (`nil`). Mutates the view
  /// model's `selectedLanguage`; `visibleScenarios` owns the filtering. The
  /// caller gates this on `shouldShowLanguageFilter`, so the menu never appears
  /// while the feed carries a single language.
  func languageMenu(viewModel: SharedScenariosViewModel) -> some View {
    Menu {
      // Languages first (canonical ja, en order), dropping the leading `.all`
      // option — "All" lives below the divider as the filter-clearing choice.
      ForEach(
        GalleryLanguageFilter.options(available: viewModel.availableLanguages)
          .compactMap(\.selectedLanguage), id: \.self
      ) { code in
        languageButton(
          title: LanguageDisplayName.resolve(code), code: code, viewModel: viewModel)
      }
      Divider()
      languageButton(title: String(localized: "All"), code: nil, viewModel: viewModel)
    } label: {
      HStack(spacing: 4) {
        Text(languageMenuLabel(viewModel: viewModel))
        Image(systemName: "chevron.down")
          .font(.caption2)
          // Decorative — the Menu's own accessibilityLabel/Value carry meaning.
          .accessibilityHidden(true)
      }
    }
    // Intentionally keep the default iOS 26 Liquid Glass toolbar capsule (no
    // `hidingPasturaSharedBackground()`): unlike a bare back chevron, this is a
    // standard interactive Menu where the capsule reads as a tappable control.
    // The simulator suppresses the capsule regardless, so verify the capsule +
    // label legibility on a real iOS 26 device (swiftui-traps § Liquid Glass
    // toolbar capsule).
    .accessibilityLabel(String(localized: "Language filter"))
    .accessibilityValue(languageMenuLabel(viewModel: viewModel))
  }

  private func languageButton(
    title: String, code: String?, viewModel: SharedScenariosViewModel
  ) -> some View {
    Button {
      viewModel.selectedLanguage = code
    } label: {
      // Checkmark on the active filter — the Menu's free per-row selection
      // affordance replaces the removed chips' `.isSelected` trait.
      if viewModel.selectedLanguage == code {
        Label(title, systemImage: "checkmark")
      } else {
        Text(title)
      }
    }
  }

  /// The Menu trigger's current-selection label: the selected language's
  /// display name, or "All" when the filter is cleared (`nil`).
  private func languageMenuLabel(viewModel: SharedScenariosViewModel) -> String {
    viewModel.selectedLanguage.map(LanguageDisplayName.resolve)
      ?? String(localized: "All")
  }
}
