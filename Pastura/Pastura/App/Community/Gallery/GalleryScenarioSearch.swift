import Foundation

/// Pure, side-effect-free search/filter projection for the Browse (さがす)
/// tab's curated gallery. Drives `SharedScenariosViewModel.visibleScenarios`
/// and `.emptyReason`.
///
/// Kept `nonisolated` and dependency-free (plain `[GalleryScenario]` +
/// category + query inputs, no ViewModel reference) so the filtering and the
/// empty-state classification are unit-testable without rendering or a
/// `@MainActor` hop (ADR-009 / `.claude/rules/view-testing.md`). Sibling of
/// `GalleryCategoryFilter`, which models the chip presentation; this type
/// models the actual data filtering those chips (plus the search field) feed.
nonisolated enum GalleryScenarioSearch {

  /// Returns the scenarios matching both the category filter and the search
  /// query.
  ///
  /// - `category == nil` means "all categories" (no category narrowing).
  /// - A blank or whitespace-only `query` applies no text filter; otherwise
  ///   a scenario matches when the query is a substring of its `title` or
  ///   `description`. Matching uses `localizedStandardContains` — the
  ///   Finder-like case- and diacritic-insensitive comparison appropriate
  ///   for user-facing search.
  static func filter(
    _ scenarios: [GalleryScenario], category: GalleryCategory?, query: String
  ) -> [GalleryScenario] {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    return scenarios.filter { scenario in
      if let category, scenario.category != category { return false }
      guard !trimmed.isEmpty else { return true }
      return scenario.title.localizedStandardContains(trimmed)
        || scenario.description.localizedStandardContains(trimmed)
    }
  }

  /// Why the filtered list came back empty — selects the empty-card copy.
  ///
  /// Only meaningful when `filter(...)` actually returned an empty result.
  /// `galleryEmpty` (the curated gallery loaded successfully but shipped
  /// zero scenarios) is deliberately distinct from
  /// `SharedScenariosViewModel.LoadState.empty` (network-down, no cache),
  /// which is rendered by the top-level state switch — not the card — so a
  /// reader must not conflate the two.
  enum EmptyReason: Equatable, Sendable {
    /// A non-blank search query matched nothing.
    case noMatchingQuery
    /// A selected category contains no scenarios (no active query).
    case emptyCategory
    /// The gallery itself is empty (no query, no category narrowing).
    case galleryEmpty
  }

  /// Classifies why a filtered-empty Browse list is empty.
  ///
  /// Precedence: a genuinely empty gallery dominates (the user's
  /// category/query is moot when there is nothing to filter), then a present
  /// query, then a selected category.
  static func emptyReason(
    allScenariosEmpty: Bool, category: GalleryCategory?, query: String
  ) -> EmptyReason {
    if allScenariosEmpty { return .galleryEmpty }
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmed.isEmpty { return .noMatchingQuery }
    if category != nil { return .emptyCategory }
    return .galleryEmpty
  }
}
