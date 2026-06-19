import Foundation

/// One selectable option in the Browse tab's horizontal category-filter
/// chip row (ADR-016 P4): either the leading "All" chip (no filter) or a
/// single ``GalleryCategory``.
///
/// Kept `nonisolated` and side-effect-free so the chip-options projection
/// — the "All"-first ordering and the option → `selectedCategory` mapping
/// — is unit-testable without rendering (ADR-009 /
/// `.claude/rules/view-testing.md`). The category *filtering* itself stays
/// in `SharedScenariosViewModel.visibleScenarios`; this type only models
/// the chip presentation and how a tapped chip maps onto the existing
/// `selectedCategory` binding.
nonisolated enum GalleryCategoryFilter: Hashable {
  /// The leading chip: clears the filter (shows every scenario).
  case all
  /// A chip scoped to a single gallery category.
  case category(GalleryCategory)

  /// The chip options in row order: the "All" chip first, then one chip per
  /// ``GalleryCategory`` in `allCases` order. "All" leads so the default
  /// unfiltered state is the first chip the user lands on.
  static let options: [GalleryCategoryFilter] =
    [.all] + GalleryCategory.allCases.map(GalleryCategoryFilter.category)

  /// The `selectedCategory` binding value this option represents — `nil`
  /// for ``all`` (which `visibleScenarios` already treats as "show
  /// everything"), or the wrapped category otherwise.
  var selectedCategory: GalleryCategory? {
    switch self {
    case .all: return nil
    case .category(let category): return category
    }
  }
}
