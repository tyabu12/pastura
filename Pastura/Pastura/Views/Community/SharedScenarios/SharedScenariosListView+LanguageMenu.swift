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
      // Mirror the Home `ActiveModelChip` so the two nav-bar chips read as one
      // family: a soft moss capsule (not the iOS 26 Liquid Glass one — the
      // toolbar item opts out via `hidingPasturaSharedBackground()` at the call
      // site), size-13 semibold label, small trailing chevron.
      HStack(spacing: 5) {
        Text(languageMenuLabel(viewModel: viewModel))
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(Color.inkSecondary)
          .lineLimit(1)
          .truncationMode(.tail)
        Spacer(minLength: 4)
        Image(systemName: "chevron.down")
          .font(.system(size: 9, weight: .semibold))
          .foregroundStyle(Color.muted)
          // Decorative — the Menu's own accessibilityLabel/Value carry meaning.
          .accessibilityHidden(true)
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 5)
      // Fixed width so switching language never re-measures the toolbar item:
      // variable-width nav-bar items clip their content for a frame on width
      // change (swiftui-traps § toolbar variable-width clip; ActiveModelChip
      // pins its width for the same reason). Sized to fit "English".
      .frame(width: 104)
      .background(Capsule().fill(Color.mossDark.opacity(0.10)))
    }
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
