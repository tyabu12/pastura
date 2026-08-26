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

  /// Whether the Browse listing hides scenarios already installed with no
  /// pending update.
  enum InstallFilter: Equatable, Sendable {
    /// Drop scenarios whose id is in the caller's `installedUnchangedIds` set
    /// (when the search query is blank — see `filter`'s doc comment). The
    /// Browse default: a scenario the user already has adds no value to a
    /// discovery listing.
    case hideInstalled
    /// No install-state narrowing — show everything the category/language/
    /// query filters admit.
    case all
  }

  /// Returns the scenarios matching the category filter, the language filter,
  /// the search query, and (optionally) the install-state filter.
  ///
  /// - `category == nil` means "all categories" (no category narrowing).
  /// - `language == nil` means "all languages" (no language narrowing).
  /// - A blank or whitespace-only `query` applies no text filter; otherwise
  ///   a scenario matches when the query is a substring of its `title` or
  ///   `description`. Matching uses `localizedStandardContains` — the
  ///   Finder-like case- and diacritic-insensitive comparison appropriate
  ///   for user-facing search.
  /// - `installedUnchangedIds` are ids installed locally whose local hash
  ///   equals the gallery hash (installed AND no update available).
  /// - `installFilter == .hideInstalled` drops those ids, but **only when
  ///   the query is blank**: once the user has typed a search, they are
  ///   looking for something specific, and hiding a match they just typed
  ///   because they happen to already have it is confusing — the row's own
  ///   "Installed" badge disambiguates instead.
  static func filter(
    _ scenarios: [GalleryScenario], category: GalleryCategory?, query: String,
    language: String?, installedUnchangedIds: Set<String> = [],
    installFilter: InstallFilter = .all
  ) -> [GalleryScenario] {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    let matched = scenarios.filter { scenario in
      guard matches(scenario, category: category, language: language, trimmedQuery: trimmed)
      else { return false }
      if installFilter == .hideInstalled, trimmed.isEmpty,
        installedUnchangedIds.contains(scenario.id) {
        return false
      }
      return true
    }
    return matched.sorted { ordersBefore($0, $1, installedUnchangedIds: installedUnchangedIds) }
  }

  /// Number of scenarios that `filter` would show under `.all` but hides
  /// under `.hideInstalled` for the same category/language/query — lets the
  /// ViewModel compute the hidden count without duplicating the matching
  /// predicate or re-running the sort.
  static func hiddenInstalledCount(
    _ scenarios: [GalleryScenario], category: GalleryCategory?, query: String,
    language: String?, installedUnchangedIds: Set<String>
  ) -> Int {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.isEmpty else { return 0 }
    return scenarios.count { scenario in
      matches(scenario, category: category, language: language, trimmedQuery: trimmed)
        && installedUnchangedIds.contains(scenario.id)
    }
  }

  /// Shared category/language/query predicate behind `filter` and
  /// `hiddenInstalledCount`, so the two never drift apart.
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
    /// Every scenario the category/language narrowing left is installed and
    /// unchanged, and the hide-installed filter removed it — only meaningful
    /// when `hiddenInstalledCount > 0`.
    case allInstalled
    /// The gallery itself is empty (no query, no category narrowing).
    case galleryEmpty
  }

  /// Classifies why a filtered-empty Browse list is empty.
  ///
  /// Precedence: a genuinely empty gallery dominates (the user's
  /// language/category/query is moot when there is nothing to filter), then
  /// a present query, then the hide-installed filter having hidden
  /// everything left, then a selected language, then a selected category.
  /// `allInstalled` outranks language/category because, with e.g. a category
  /// selected and every row in it installed, "No scenarios in this
  /// category." would be false — the rows exist, the install filter hid
  /// them.
  static func emptyReason(
    allScenariosEmpty: Bool, category: GalleryCategory?, query: String,
    language: String?, hiddenInstalledCount: Int = 0
  ) -> EmptyReason {
    if allScenariosEmpty { return .galleryEmpty }
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmed.isEmpty { return .noMatchingQuery }
    if hiddenInstalledCount > 0 { return .allInstalled }
    if language != nil { return .emptyLanguage }
    if category != nil { return .emptyCategory }
    return .galleryEmpty
  }
}
