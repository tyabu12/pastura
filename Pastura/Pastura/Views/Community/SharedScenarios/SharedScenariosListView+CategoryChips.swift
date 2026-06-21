import SwiftUI

// Category-filter chip row, split out of `SharedScenariosListView` to keep the
// main view under the type_body_length budget (#731). `categoryChips` is the
// only entry point the main file calls, so it is module-internal; the per-chip
// helpers stay file-private to this sibling.
extension SharedScenariosListView {

  /// Horizontal, scrollable category-filter chip row (ADR-016 P4). Replaces
  /// the menu `Picker`: every category is one tap inline, matching the D3
  /// Browse mock. Drives the existing `selectedCategory` binding (nil =
  /// "All"); `visibleScenarios` still owns the actual filtering.
  func categoryChips(selection: Binding<GalleryCategory?>) -> some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 8) {
        ForEach(GalleryCategoryFilter.options, id: \.self) { option in
          categoryChip(option, selection: selection)
        }
      }
      .padding(.horizontal, PasturaCardMetrics.horizontalMargin)
    }
  }

  private func categoryChip(
    _ option: GalleryCategoryFilter, selection: Binding<GalleryCategory?>
  ) -> some View {
    let isSelected = option.selectedCategory == selection.wrappedValue
    return Button {
      selection.wrappedValue = option.selectedCategory
    } label: {
      Text(chipTitle(option))
        .font(.subheadline.weight(isSelected ? .semibold : .regular))
        // Selected uses `mossDark`, not base `moss`: white-on-mossDark clears
        // WCAG AA (≈4.76:1) whereas white-on-moss is only ≈3.0:1
        // (PasturaPrimaryButtonStyle §2.3). White-on-accent is the
        // contrast-passing pair, distinct from §1's avoid-white-surfaces rule.
        .foregroundStyle(isSelected ? Color.white : Color.ink)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(isSelected ? Color.mossDark : Color.bubbleBackground, in: Capsule())
        .overlay(
          Capsule().strokeBorder(
            isSelected ? Color.clear : Color.rule,
            lineWidth: PasturaCardMetrics.chipBorderWidth))
    }
    .buttonStyle(.plain)
    // The menu Picker announced its selection for free; rebuild that on the
    // hand-rolled chips so VoiceOver still reads which filter is active.
    .accessibilityAddTraits(isSelected ? [.isSelected] : [])
  }

  private func chipTitle(_ option: GalleryCategoryFilter) -> String {
    switch option {
    case .all: return String(localized: "All")
    case .category(let category): return category.displayName
    }
  }
}
