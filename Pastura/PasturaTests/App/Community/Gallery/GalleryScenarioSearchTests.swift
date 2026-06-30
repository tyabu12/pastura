import Foundation
import Testing

@testable import Pastura

/// Unit tests for the Browse tab's pure search/filter projection
/// (`GalleryScenarioSearch`). Covers the category-AND-query filtering and
/// the `EmptyReason` classification that drives the empty-card copy.
/// Asserts logic properties only, never rendered output
/// (ADR-009 / `.claude/rules/view-testing.md`).
///
/// `@MainActor` on the suite sidesteps swift-isolation Pattern 5: a
/// nonisolated test calling `==` on the auto-synthesized `Equatable`
/// `EmptyReason` enum would otherwise fail the MainActor-isolated
/// conformance-lookup check. Matches `SharedScenariosCategoryFilterTests`.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct GalleryScenarioSearchTests {

  // MARK: - Fixtures

  private func scenario(
    id: String, title: String, description: String, category: GalleryCategory,
    language: String? = nil
  ) -> GalleryScenario {
    GalleryScenario(
      id: id, title: title, category: category,
      description: description, author: "Author",
      recommendedModel: ModelRegistry.gemma4E2B.id, estimatedInferences: 10,
      // swiftlint:disable:next force_unwrapping
      yamlURL: URL(string: "https://example.com/\(id).yaml")!,
      yamlSHA256: "hash", addedAt: "2026-01-01",
      language: language)
  }

  private var sample: [GalleryScenario] {
    [
      scenario(
        id: "asch", title: "Asch Conformity",
        description: "Conformity under social pressure", category: .socialPsychology),
      scenario(
        id: "pd", title: "Prisoner's Dilemma",
        description: "Cooperate or defect", category: .gameTheory),
      scenario(
        id: "trolley", title: "Trolley Problem",
        description: "An ethical dilemma about sacrifice", category: .ethics)
    ]
  }

  // MARK: - Category filtering

  @Test func nilCategoryReturnsEverythingWhenNoQuery() {
    let result = GalleryScenarioSearch.filter(sample, category: nil, query: "", language: nil)
    #expect(result.count == 3)
  }

  @Test func categoryNarrowsToThatCategory() {
    let result = GalleryScenarioSearch.filter(
      sample, category: .gameTheory, query: "", language: nil)
    #expect(result.map(\.id) == ["pd"])
  }

  // MARK: - Query filtering

  @Test func queryMatchesTitleSubstring() {
    let result = GalleryScenarioSearch.filter(
      sample, category: nil, query: "trolley", language: nil)
    #expect(result.map(\.id) == ["trolley"])
  }

  @Test func queryMatchesDescriptionSubstring() {
    let result = GalleryScenarioSearch.filter(
      sample, category: nil, query: "defect", language: nil)
    #expect(result.map(\.id) == ["pd"])
  }

  @Test func queryIsCaseInsensitive() {
    let result = GalleryScenarioSearch.filter(
      sample, category: nil, query: "ASCH", language: nil)
    #expect(result.map(\.id) == ["asch"])
  }

  @Test func whitespaceOnlyQueryAppliesNoTextFilter() {
    // A whitespace-only query must not collapse the list to empty — it is
    // treated as "no query", so the category filter alone decides the result.
    let result = GalleryScenarioSearch.filter(
      sample, category: .ethics, query: "   ", language: nil)
    #expect(result.map(\.id) == ["trolley"])
  }

  @Test func categoryAndQueryCombineWithAnd() {
    // "dilemma" matches Prisoner's Dilemma (title) AND Trolley Problem
    // (description), but the .ethics category narrows it to just Trolley.
    let result = GalleryScenarioSearch.filter(
      sample, category: .ethics, query: "dilemma", language: nil)
    #expect(result.map(\.id) == ["trolley"])
  }

  @Test func nonMatchingQueryReturnsEmpty() {
    let result = GalleryScenarioSearch.filter(
      sample, category: nil, query: "zzzznomatch", language: nil)
    #expect(result.isEmpty)
  }

  // MARK: - EmptyReason classification

  @Test func emptyReasonIsNoMatchingQueryWhenQueryPresent() {
    let reason = GalleryScenarioSearch.emptyReason(
      allScenariosEmpty: false, category: nil, query: "zzz", language: nil)
    #expect(reason == .noMatchingQuery)
  }

  @Test func emptyReasonIsNoMatchingQueryEvenWithCategory() {
    // A present query takes precedence over category in the empty-state copy.
    let reason = GalleryScenarioSearch.emptyReason(
      allScenariosEmpty: false, category: .ethics, query: "zzz", language: nil)
    #expect(reason == .noMatchingQuery)
  }

  @Test func emptyReasonIsEmptyCategoryWhenCategoryFilteredAll() {
    let reason = GalleryScenarioSearch.emptyReason(
      allScenariosEmpty: false, category: .creative, query: "", language: nil)
    #expect(reason == .emptyCategory)
  }

  @Test func emptyReasonIsGalleryEmptyWhenNoQueryNoCategory() {
    let reason = GalleryScenarioSearch.emptyReason(
      allScenariosEmpty: true, category: nil, query: "", language: nil)
    #expect(reason == .galleryEmpty)
  }

  @Test func emptyReasonIsGalleryEmptyWhenGalleryEmptyTakesPrecedence() {
    // When the curated gallery itself shipped zero scenarios, that fact
    // dominates over any category/query the user happens to have set.
    let reason = GalleryScenarioSearch.emptyReason(
      allScenariosEmpty: true, category: .ethics, query: "anything", language: nil)
    #expect(reason == .galleryEmpty)
  }

  // MARK: - Language filtering

  private var jaOnlySample: [GalleryScenario] {
    [
      scenario(
        id: "ja1", title: "Test A", description: "Japanese scenario A",
        category: .socialPsychology, language: "ja"),
      scenario(
        id: "ja2", title: "Test B", description: "Japanese scenario B",
        category: .gameTheory, language: "ja")
    ]
  }

  @Test func languageFilterMatchesExplicitLanguage() {
    let result = GalleryScenarioSearch.filter(
      jaOnlySample, category: nil, query: "", language: "ja")
    #expect(result.map(\.id) == ["ja1", "ja2"])
  }

  @Test func languageFilterExcludesNonMatchingLanguage() {
    let result = GalleryScenarioSearch.filter(
      jaOnlySample, category: nil, query: "", language: "en")
    #expect(result.isEmpty)
  }

  @Test func nilLanguageReturnsAll() {
    // language == nil means "all languages" — no language narrowing applied.
    let result = GalleryScenarioSearch.filter(
      jaOnlySample, category: nil, query: "", language: nil)
    #expect(result.count == 2)
  }

  @Test func languageAndCategoryBothApplied() {
    // Language AND category must both match — only "ja" + .gameTheory passes.
    let result = GalleryScenarioSearch.filter(
      jaOnlySample, category: .gameTheory, query: "", language: "ja")
    #expect(result.map(\.id) == ["ja2"])
  }

  @Test func languageAndQueryBothApplied() {
    // Language AND query must both match — language "ja", query "Test A"
    // (matches ja1's title "Test A" but not "Test B").
    let result = GalleryScenarioSearch.filter(
      jaOnlySample, category: nil, query: "Test A", language: "ja")
    #expect(result.map(\.id) == ["ja1"])
  }

  // MARK: - EmptyReason language precedence

  @Test func emptyReasonIsEmptyLanguageWhenLanguageFiltersAll() {
    // A language filter with blank query → .emptyLanguage (before .emptyCategory).
    let reason = GalleryScenarioSearch.emptyReason(
      allScenariosEmpty: false, category: nil, query: "", language: "en")
    #expect(reason == .emptyLanguage)
  }

  @Test func emptyReasonQueryDominatesLanguage() {
    // A non-blank query takes precedence over a language filter in the copy.
    let reason = GalleryScenarioSearch.emptyReason(
      allScenariosEmpty: false, category: nil, query: "zzz", language: "en")
    #expect(reason == .noMatchingQuery)
  }

  @Test func emptyReasonLanguageDominatesCategory() {
    // Language takes precedence over category when both are non-nil.
    let reason = GalleryScenarioSearch.emptyReason(
      allScenariosEmpty: false, category: .ethics, query: "", language: "en")
    #expect(reason == .emptyLanguage)
  }

  @Test func emptyReasonNilLanguageFallsThroughToCategory() {
    // language == nil: classification falls through to category.
    let reason = GalleryScenarioSearch.emptyReason(
      allScenariosEmpty: false, category: .creative, query: "", language: nil)
    #expect(reason == .emptyCategory)
  }

  @Test func emptyReasonGalleryEmptyDominatesLanguage() {
    // galleryEmpty always wins regardless of language filter.
    let reason = GalleryScenarioSearch.emptyReason(
      allScenariosEmpty: true, category: nil, query: "", language: "en")
    #expect(reason == .galleryEmpty)
  }
}
