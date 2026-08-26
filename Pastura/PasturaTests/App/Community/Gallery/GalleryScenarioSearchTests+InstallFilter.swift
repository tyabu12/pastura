import Foundation
import Testing

@testable import Pastura

/// Install-state coverage for `GalleryScenarioSearch`: `.hideInstalled`
/// filtering, the leading `ordersBefore` sort key, `hiddenInstalledCount`,
/// and the `EmptyReason.allInstalled` precedence.
///
/// Split from `GalleryScenarioSearchTests.swift` as a same-struct extension
/// (never a second `@Suite` — `testing.md` § "Splitting a Suite Across
/// Files") once the struct's body crossed SwiftLint's `type_body_length`.
extension GalleryScenarioSearchTests {

  // MARK: - Install-state filtering

  @Test func hideInstalledDropsInstalledUnchangedIds() {
    let result = GalleryScenarioSearch.filter(
      sample, category: nil, query: "", language: nil,
      installedUnchangedIds: ["pd"], installFilter: .hideInstalled)
    #expect(!result.map(\.id).contains("pd"))
    #expect(result.count == 2)
  }

  @Test func hideInstalledKeepsRowsNotInSet() {
    // "pd" is installed WITH an update available, so it is simply absent
    // from installedUnchangedIds — it must stay visible.
    let result = GalleryScenarioSearch.filter(
      sample, category: nil, query: "", language: nil,
      installedUnchangedIds: ["asch"], installFilter: .hideInstalled)
    #expect(result.map(\.id).contains("pd"))
  }

  @Test func hideInstalledIsBypassedWhileQueryIsNonBlank() {
    // A typed search always searches everything — hiding a match the user
    // just typed because they already have it is confusing; the row's own
    // "Installed" badge disambiguates instead.
    let result = GalleryScenarioSearch.filter(
      sample, category: nil, query: "dilemma", language: nil,
      installedUnchangedIds: ["pd"], installFilter: .hideInstalled)
    #expect(result.map(\.id).contains("pd"))
  }

  @Test func allShowsInstalledButSortsThemLast() {
    // "a" is featured AND installed-unchanged; "c" is unpinned and NOT
    // installed. Even though "a" is pinned, an installed-unchanged row
    // always sorts after every non-installed row.
    let input = [
      sortable(id: "a", featured: 1, addedAt: "2026-01-01"),
      sortable(id: "b", featured: 2, addedAt: "2026-01-01"),
      sortable(id: "c", addedAt: "2026-06-01")
    ]
    let result = GalleryScenarioSearch.filter(
      input, category: nil, query: "", language: nil,
      installedUnchangedIds: ["a", "b"], installFilter: .all)
    // Non-installed "c" first, then the installed group in ADR-025 order
    // (featured ascending: "a" before "b").
    #expect(result.map(\.id) == ["c", "a", "b"])
  }

  // MARK: - hiddenInstalledCount

  @Test func hiddenInstalledCountCountsOnlyHiddenRows() {
    let count = GalleryScenarioSearch.hiddenInstalledCount(
      sample, category: nil, query: "", language: nil, installedUnchangedIds: ["pd", "trolley"])
    #expect(count == 2)
  }

  @Test func hiddenInstalledCountRespectsCategory() {
    let count = GalleryScenarioSearch.hiddenInstalledCount(
      sample, category: .ethics, query: "", language: nil,
      installedUnchangedIds: ["pd", "trolley"])
    #expect(count == 1)
  }

  @Test func hiddenInstalledCountIsZeroWhenQueryNonBlank() {
    let count = GalleryScenarioSearch.hiddenInstalledCount(
      sample, category: nil, query: "dilemma", language: nil,
      installedUnchangedIds: ["pd", "trolley"])
    #expect(count == 0)
  }

  // MARK: - EmptyReason install-state precedence

  @Test func emptyReasonAllInstalledBeatsLanguageAndCategory() {
    let reason = GalleryScenarioSearch.emptyReason(
      allScenariosEmpty: false, category: .ethics, query: "", language: "en",
      hiddenInstalledCount: 3)
    #expect(reason == .allInstalled)
  }

  @Test func emptyReasonQueryBeatsAllInstalled() {
    let reason = GalleryScenarioSearch.emptyReason(
      allScenariosEmpty: false, category: nil, query: "zzz", language: nil,
      hiddenInstalledCount: 3)
    #expect(reason == .noMatchingQuery)
  }

  @Test func emptyReasonGalleryEmptyBeatsAllInstalled() {
    let reason = GalleryScenarioSearch.emptyReason(
      allScenariosEmpty: true, category: nil, query: "", language: nil,
      hiddenInstalledCount: 3)
    #expect(reason == .galleryEmpty)
  }

  @Test func emptyReasonAllInstalledRequiresHiddenCount() {
    // With hiddenInstalledCount == 0 the classification falls through to
    // the existing category/language/galleryEmpty precedence.
    let reason = GalleryScenarioSearch.emptyReason(
      allScenariosEmpty: false, category: .ethics, query: "", language: nil,
      hiddenInstalledCount: 0)
    #expect(reason == .emptyCategory)
  }
}
