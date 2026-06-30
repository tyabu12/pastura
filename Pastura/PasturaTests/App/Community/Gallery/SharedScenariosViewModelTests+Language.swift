import Foundation
import Testing

@testable import Pastura

// Sibling-file split of `SharedScenariosViewModelTests` for the ADR-010
// language-filter dimension. An `extension` (NOT a new `@Suite`) per
// `.claude/rules/testing.md`; reuses the original suite's internal helpers
// (`makeRepo` / `makeGalleryScenario` / `makeIndex`) and `StubVMGalleryService`.
extension SharedScenariosViewModelTests {

  /// On a device whose language IS present in the feed, the initial filter
  /// seeds to that device language and the list narrows to it.
  @Test func initialLanguageSeedsToDeviceWhenPresentInFeed() async throws {
    let repo = try makeRepo()
    let service = StubVMGalleryService()
    service.cachedIndex = makeIndex([
      makeGalleryScenario(id: "ja1", language: "ja"),
      makeGalleryScenario(id: "en1", language: "en")
    ])
    service.refreshResult = .success(nil)

    let viewModel = SharedScenariosViewModel(
      galleryService: service, repository: repo, deviceLanguage: "en")
    await viewModel.load()

    #expect(viewModel.selectedLanguage == "en")
    #expect(viewModel.visibleScenarios.map(\.id) == ["en1"])
  }

  /// THE regression guard (critic Axis 1 / ADR-010 D6): on an en device with
  /// an all-Japanese feed, the initial filter must fall back to `.all` rather
  /// than leaving the Browse list empty. Without the fallback an en-locale
  /// launch user would see 0 of N scenarios.
  @Test func initialLanguageFallsBackToAllWhenDeviceLanguageAbsentFromFeed() async throws {
    let repo = try makeRepo()
    let service = StubVMGalleryService()
    service.cachedIndex = makeIndex([
      makeGalleryScenario(id: "ja1", language: "ja"),
      makeGalleryScenario(id: "ja2", language: "ja")
    ])
    service.refreshResult = .success(nil)

    let viewModel = SharedScenariosViewModel(
      galleryService: service, repository: repo, deviceLanguage: "en")
    await viewModel.load()

    #expect(viewModel.selectedLanguage == nil)
    #expect(viewModel.visibleScenarios.count == 2)
  }

  /// On a ja device with the all-Japanese launch feed, the seed is "ja" and
  /// every scenario stays visible.
  @Test func initialLanguageSeedsToJaOnJapaneseDeviceAndFeed() async throws {
    let repo = try makeRepo()
    let service = StubVMGalleryService()
    service.cachedIndex = makeIndex([
      makeGalleryScenario(id: "ja1", language: "ja"),
      makeGalleryScenario(id: "ja2", language: "ja")
    ])
    service.refreshResult = .success(nil)

    let viewModel = SharedScenariosViewModel(
      galleryService: service, repository: repo, deviceLanguage: "ja")
    await viewModel.load()

    #expect(viewModel.selectedLanguage == "ja")
    #expect(viewModel.visibleScenarios.count == 2)
  }

  /// The chip row is hidden while the feed carries a single language (today's
  /// all-Japanese gallery) and surfaces once a second language ships.
  @Test func shouldShowLanguageFilterReflectsFeedLanguageCount() async throws {
    let repo = try makeRepo()
    let singleService = StubVMGalleryService()
    singleService.cachedIndex = makeIndex([
      makeGalleryScenario(id: "ja1", language: "ja"),
      makeGalleryScenario(id: "ja2", language: "ja")
    ])
    singleService.refreshResult = .success(nil)
    let single = SharedScenariosViewModel(
      galleryService: singleService, repository: repo, deviceLanguage: "ja")
    await single.load()
    #expect(single.shouldShowLanguageFilter == false)

    let repo2 = try makeRepo()
    let multiService = StubVMGalleryService()
    multiService.cachedIndex = makeIndex([
      makeGalleryScenario(id: "ja1", language: "ja"),
      makeGalleryScenario(id: "en1", language: "en")
    ])
    multiService.refreshResult = .success(nil)
    let multi = SharedScenariosViewModel(
      galleryService: multiService, repository: repo2, deviceLanguage: "ja")
    await multi.load()
    #expect(multi.shouldShowLanguageFilter == true)
  }

  /// User chip taps drive `selectedLanguage` and re-narrow the visible list;
  /// `nil` (the すべて chip) shows every language.
  @Test func switchingSelectedLanguageRenarrowsVisibleScenarios() async throws {
    let repo = try makeRepo()
    let service = StubVMGalleryService()
    service.cachedIndex = makeIndex([
      makeGalleryScenario(id: "ja1", language: "ja"),
      makeGalleryScenario(id: "en1", language: "en")
    ])
    service.refreshResult = .success(nil)

    let viewModel = SharedScenariosViewModel(
      galleryService: service, repository: repo, deviceLanguage: "ja")
    await viewModel.load()

    viewModel.selectedLanguage = "ja"
    #expect(viewModel.visibleScenarios.map(\.id) == ["ja1"])

    viewModel.selectedLanguage = "en"
    #expect(viewModel.visibleScenarios.map(\.id) == ["en1"])

    viewModel.selectedLanguage = nil
    #expect(viewModel.visibleScenarios.count == 2)
  }
}
