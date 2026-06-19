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
    id: String, title: String, description: String, category: GalleryCategory
  ) -> GalleryScenario {
    GalleryScenario(
      id: id, title: title, category: category,
      description: description, author: "Author",
      recommendedModel: ModelRegistry.gemma4E2B.id, estimatedInferences: 10,
      // swiftlint:disable:next force_unwrapping
      yamlURL: URL(string: "https://example.com/\(id).yaml")!,
      yamlSHA256: "hash", addedAt: "2026-01-01")
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
    let result = GalleryScenarioSearch.filter(sample, category: nil, query: "")
    #expect(result.count == 3)
  }

  @Test func categoryNarrowsToThatCategory() {
    let result = GalleryScenarioSearch.filter(sample, category: .gameTheory, query: "")
    #expect(result.map(\.id) == ["pd"])
  }

  // MARK: - Query filtering

  @Test func queryMatchesTitleSubstring() {
    let result = GalleryScenarioSearch.filter(sample, category: nil, query: "trolley")
    #expect(result.map(\.id) == ["trolley"])
  }

  @Test func queryMatchesDescriptionSubstring() {
    let result = GalleryScenarioSearch.filter(sample, category: nil, query: "defect")
    #expect(result.map(\.id) == ["pd"])
  }

  @Test func queryIsCaseInsensitive() {
    let result = GalleryScenarioSearch.filter(sample, category: nil, query: "ASCH")
    #expect(result.map(\.id) == ["asch"])
  }

  @Test func whitespaceOnlyQueryAppliesNoTextFilter() {
    // A whitespace-only query must not collapse the list to empty — it is
    // treated as "no query", so the category filter alone decides the result.
    let result = GalleryScenarioSearch.filter(sample, category: .ethics, query: "   ")
    #expect(result.map(\.id) == ["trolley"])
  }

  @Test func categoryAndQueryCombineWithAnd() {
    // "dilemma" matches Prisoner's Dilemma (title) AND Trolley Problem
    // (description), but the .ethics category narrows it to just Trolley.
    let result = GalleryScenarioSearch.filter(sample, category: .ethics, query: "dilemma")
    #expect(result.map(\.id) == ["trolley"])
  }

  @Test func nonMatchingQueryReturnsEmpty() {
    let result = GalleryScenarioSearch.filter(sample, category: nil, query: "zzzznomatch")
    #expect(result.isEmpty)
  }

  // MARK: - EmptyReason classification

  @Test func emptyReasonIsNoMatchingQueryWhenQueryPresent() {
    let reason = GalleryScenarioSearch.emptyReason(
      allScenariosEmpty: false, category: nil, query: "zzz")
    #expect(reason == .noMatchingQuery)
  }

  @Test func emptyReasonIsNoMatchingQueryEvenWithCategory() {
    // A present query takes precedence over category in the empty-state copy.
    let reason = GalleryScenarioSearch.emptyReason(
      allScenariosEmpty: false, category: .ethics, query: "zzz")
    #expect(reason == .noMatchingQuery)
  }

  @Test func emptyReasonIsEmptyCategoryWhenCategoryFilteredAll() {
    let reason = GalleryScenarioSearch.emptyReason(
      allScenariosEmpty: false, category: .creative, query: "")
    #expect(reason == .emptyCategory)
  }

  @Test func emptyReasonIsGalleryEmptyWhenNoQueryNoCategory() {
    let reason = GalleryScenarioSearch.emptyReason(
      allScenariosEmpty: true, category: nil, query: "")
    #expect(reason == .galleryEmpty)
  }

  @Test func emptyReasonIsGalleryEmptyWhenGalleryEmptyTakesPrecedence() {
    // When the curated gallery itself shipped zero scenarios, that fact
    // dominates over any category/query the user happens to have set.
    let reason = GalleryScenarioSearch.emptyReason(
      allScenariosEmpty: true, category: .ethics, query: "anything")
    #expect(reason == .galleryEmpty)
  }
}
