import Foundation
import Testing

@testable import Pastura

/// Install-state filter coverage for `SharedScenariosViewModel` (#1565):
/// the `.hideInstalled` default, `installedUnchangedIds`, the session pin
/// for rows installed behind the list, and the hidden-count / empty-reason
/// wiring. Same-struct extension, not a second `@Suite`
/// (`testing.md` § "Splitting a Suite Across Files").
extension SharedScenariosViewModelTests {

  /// A gallery row saved directly to the repository — the detail screen's
  /// install, which goes through a *different* VM instance.
  private func installBehindTheList(
    _ scenario: GalleryScenario, in repo: GRDBScenarioRepository, hash: String? = nil
  ) throws {
    try repo.save(
      ScenarioRecord(
        id: scenario.id, name: scenario.title, yamlDefinition: "yaml: stub",
        isPreset: false, createdAt: Date(), updatedAt: Date(),
        sourceType: ScenarioSourceType.gallery, sourceId: scenario.id,
        sourceHash: hash ?? scenario.yamlSHA256))
  }

  @Test func hideInstalledIsTheDefaultAndHidesInstalledUnchangedRows() async throws {
    let repo = try makeRepo()
    let installed = makeGalleryScenario(id: "installed")
    let fresh = makeGalleryScenario(id: "fresh")
    try installBehindTheList(installed, in: repo)
    let service = StubVMGalleryService()
    service.cachedIndex = makeIndex([installed, fresh])

    let viewModel = SharedScenariosViewModel(galleryService: service, repository: repo)
    await viewModel.load()

    #expect(viewModel.installFilter == .hideInstalled)
    #expect(viewModel.installedUnchangedIds == ["installed"])
    #expect(viewModel.visibleScenarios.map(\.id) == ["fresh"])
    #expect(viewModel.hiddenInstalledCount == 1)

    viewModel.installFilter = .all
    #expect(viewModel.visibleScenarios.map(\.id) == ["fresh", "installed"])
    #expect(viewModel.hiddenInstalledCount == 0)
  }

  @Test func installedRowWithPendingUpdateStaysVisible() async throws {
    let repo = try makeRepo()
    let scenario = makeGalleryScenario(id: "stale")
    try installBehindTheList(scenario, in: repo, hash: String(repeating: "f", count: 64))
    let service = StubVMGalleryService()
    service.cachedIndex = makeIndex([scenario])

    let viewModel = SharedScenariosViewModel(galleryService: service, repository: repo)
    await viewModel.load()

    #expect(viewModel.hasUpdate(for: scenario))
    #expect(viewModel.installedUnchangedIds.isEmpty)
    #expect(viewModel.visibleScenarios.map(\.id) == ["stale"])
  }

  @Test func rowInstalledBehindTheListStaysPinnedUntilRefresh() async throws {
    let repo = try makeRepo()
    let scenario = makeGalleryScenario(id: "acted_on")
    let service = StubVMGalleryService()
    service.cachedIndex = makeIndex([scenario])

    let viewModel = SharedScenariosViewModel(galleryService: service, repository: repo)
    await viewModel.load()
    #expect(viewModel.visibleScenarios.map(\.id) == ["acted_on"])

    // Detail screen installs it; the pop re-syncs the snapshot.
    try installBehindTheList(scenario, in: repo)
    await viewModel.refreshInstalledSnapshot()
    #expect(viewModel.isInstalled(scenario))
    #expect(viewModel.sessionPinnedIds == ["acted_on"])
    #expect(viewModel.visibleScenarios.map(\.id) == ["acted_on"], "must not vanish under the restored scroll")
    #expect(viewModel.hiddenInstalledCount == 0)

    // A later refresh treats it like any other installed row.
    await viewModel.refresh()
    #expect(viewModel.sessionPinnedIds.isEmpty)
    #expect(viewModel.visibleScenarios.isEmpty)
    #expect(viewModel.hiddenInstalledCount == 1)
  }

  @Test func emptyReasonReportsAllInstalledWhenTheFilterHidEverything() async throws {
    let repo = try makeRepo()
    let scenario = makeGalleryScenario(id: "only", category: .ethics)
    try installBehindTheList(scenario, in: repo)
    let service = StubVMGalleryService()
    service.cachedIndex = makeIndex([scenario])

    let viewModel = SharedScenariosViewModel(galleryService: service, repository: repo)
    await viewModel.load()
    viewModel.selectedCategory = .ethics

    #expect(viewModel.visibleScenarios.isEmpty)
    #expect(viewModel.emptyReason == .allInstalled)

    viewModel.searchQuery = "zzz"
    #expect(viewModel.emptyReason == .noMatchingQuery)
  }
}
