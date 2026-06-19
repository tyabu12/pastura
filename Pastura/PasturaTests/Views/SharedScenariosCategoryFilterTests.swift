import Testing

@testable import Pastura

/// Unit tests for the Browse tab's category-chip filter projection
/// (ADR-016 P4 layout migration). Covers the genuinely-new chip-options
/// logic — the "All" chip ordering and the option → `selectedCategory`
/// mapping — NOT the category filtering itself, which is already owned by
/// `SharedScenariosViewModelTests.visibleScenariosFilterByCategory`.
/// Asserts logic properties only, never rendered output
/// (ADR-009 / `.claude/rules/view-testing.md`).
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct SharedScenariosCategoryFilterTests {

  // MARK: - Chip ordering / completeness

  @Test func allChipIsFirst() {
    // The "All" (no-filter) chip must lead the row so the default,
    // unfiltered state is the first thing the user lands on. A revert that
    // drops it or moves it after the categories fails here.
    #expect(GalleryCategoryFilter.options.first == .all)
  }

  @Test func optionsCoverEveryCategoryExactlyOnce() {
    let categories = GalleryCategoryFilter.options.compactMap { option -> GalleryCategory? in
      if case .category(let category) = option { return category }
      return nil
    }
    #expect(categories == GalleryCategory.allCases)
    // All chip + one chip per category, no duplicates or omissions.
    #expect(GalleryCategoryFilter.options.count == GalleryCategory.allCases.count + 1)
  }

  // MARK: - Option → selectedCategory mapping

  @Test func allChipMapsToNilSelection() {
    // The "All" chip drives the existing `selectedCategory` binding to nil,
    // which `visibleScenarios` already treats as "show everything".
    #expect(GalleryCategoryFilter.all.selectedCategory == nil)
  }

  @Test func categoryChipMapsToItsCategory() {
    #expect(GalleryCategoryFilter.category(.ethics).selectedCategory == .ethics)
    #expect(GalleryCategoryFilter.category(.gameTheory).selectedCategory == .gameTheory)
  }

  @Test func chipMappingPreservesCategoryOrder() {
    // The category chips, in row order, map back to `allCases` order — a
    // reordering regression (e.g. building options from a Set) fails here.
    let mapped = GalleryCategoryFilter.options.dropFirst().map(\.selectedCategory)
    #expect(mapped == GalleryCategory.allCases.map(Optional.some))
  }
}
