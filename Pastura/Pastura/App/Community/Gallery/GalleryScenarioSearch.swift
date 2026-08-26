import Foundation

/// Pure, side-effect-free search/filter projection for the Browse (さがす)
/// tab's curated gallery. Drives `SharedScenariosViewModel.visibleScenarios`
/// and `.emptyReason`.
///
/// Kept `nonisolated` and dependency-free (plain `[GalleryScenario]` +
/// category + query inputs, no ViewModel reference) so the filtering and the
/// empty-state classification are unit-testable without rendering or a
/// `@MainActor` hop (ADR-009 / `.claude/rules/view-testing.md`). Counterpart
/// to `GalleryCategoryFilter` (in `Views/`, which models the chip
/// presentation); this type models the actual data filtering those chips
/// (plus the search field) feed.
nonisolated enum GalleryScenarioSearch {

  /// Returns the scenarios matching the category filter, the language filter,
  /// and the search query.
  ///
  /// - `category == nil` means "all categories" (no category narrowing).
  /// - `language == nil` means "all languages" (no language narrowing).
  /// - A blank or whitespace-only `query` applies no text filter; otherwise
  ///   a scenario matches when the query is a substring of its `title` or
  ///   `description`. Matching uses `localizedStandardContains` — the
  ///   Finder-like case- and diacritic-insensitive comparison appropriate
  ///   for user-facing search.
  /// - `installedUnchangedIds` are ids installed locally whose local hash
  ///   equals the gallery hash (installed AND no update available). They are
  ///   never dropped from the result — a scenario the user already has is
  ///   still reachable from Browse — but the sort (below) demotes them to
  ///   the bottom of the list, since Home already surfaces installed
  ///   scenarios and Browse's job is discovering new ones.
  static func filter(
    _ scenarios: [GalleryScenario], category: GalleryCategory?, query: String,
    language: String?, installedUnchangedIds: Set<String> = []
  ) -> [GalleryScenario] {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    let matched = scenarios.filter {
      matches($0, category: category, language: language, trimmedQuery: trimmed)
    }
    return matched.sorted { ordersBefore($0, $1, installedUnchangedIds: installedUnchangedIds) }
  }

  /// Category/language/query predicate behind `filter`.
  private static func matches(
    _ scenario: GalleryScenario, category: GalleryCategory?, language: String?,
    trimmedQuery: String
  ) -> Bool {
    if let category, scenario.category != category { return false }
    if let language, scenario.effectiveLanguage != language { return false }
    guard !trimmedQuery.isEmpty else { return true }
    return scenario.title.localizedStandardContains(trimmedQuery)
      || scenario.description.localizedStandardContains(trimmedQuery)
  }

  /// Total ordering for the Browse listing, applied after filtering (ADR-025):
  ///
  /// 0. Installed-and-unchanged scenarios (in `installedUnchangedIds`) sort
  ///    **after** every scenario not in the set, regardless of `featured` —
  ///    a curator pin is a discovery aid, and the user already has the
  ///    scenario, so it does not need the promotion.
  /// 1. Then curator-pinned `featured` first, ascending rank (`nil` sorts
  ///    **last** — an unpinned entry never outranks a pinned one).
  /// 2. Then newest first by `added_at`. The field is a fixed-width
  ///    `YYYY-MM-DD` string, so a raw **string** comparison is
  ///    lexicographically == chronological — no `Date` parse (and no
  ///    `ISO8601DateFormatter`, whose default expects a full timestamp and
  ///    returns `nil` on a date-only value).
  /// 3. Then `id` ascending as a stable tie-break — `id` is unique, so this
  ///    makes the order total and deterministic (Swift's `sorted(by:)` is not
  ///    guaranteed stable).
  private static func ordersBefore(
    _ lhs: GalleryScenario, _ rhs: GalleryScenario, installedUnchangedIds: Set<String>
  ) -> Bool {
    let lInstalled = installedUnchangedIds.contains(lhs.id)
    let rInstalled = installedUnchangedIds.contains(rhs.id)
    if lInstalled != rInstalled { return !lInstalled }
    // `nil` featured → sort last: map to `Int.max` so pinned ranks float up
    // and today's all-`nil` corpus falls straight through to the date order.
    let lRank = lhs.featured ?? Int.max
    let rRank = rhs.featured ?? Int.max
    if lRank != rRank { return lRank < rRank }
    if lhs.addedAt != rhs.addedAt { return lhs.addedAt > rhs.addedAt }
    return lhs.id < rhs.id
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
    /// A selected language contains no scenarios (no active query).
    case emptyLanguage
    /// The gallery itself is empty (no query, no category narrowing).
    case galleryEmpty
  }

  /// Classifies why a filtered-empty Browse list is empty.
  ///
  /// Precedence: a genuinely empty gallery dominates (the user's
  /// language/category/query is moot when there is nothing to filter), then
  /// a present query, then a selected language, then a selected category.
  static func emptyReason(
    allScenariosEmpty: Bool, category: GalleryCategory?, query: String,
    language: String?
  ) -> EmptyReason {
    if allScenariosEmpty { return .galleryEmpty }
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmed.isEmpty { return .noMatchingQuery }
    if language != nil { return .emptyLanguage }
    if category != nil { return .emptyCategory }
    return .galleryEmpty
  }
}
