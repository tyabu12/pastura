import Foundation
import Testing

@testable import Pastura

/// Install-state coverage for `SharedScenariosViewModel` (#1565):
/// `installedUnchangedIds`, the sort-last key, and the session pin for rows
/// installed behind the list. Same-struct extension, not a second `@Suite`
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

  @Test func installedUnchangedRowsSortLast() async throws {
    let repo = try makeRepo()
    let installed = makeGalleryScenario(id: "installed")
    let fresh = makeGalleryScenario(id: "fresh")
    try installBehindTheList(installed, in: repo)
    let service = StubVMGalleryService()
    service.cachedIndex = makeIndex([installed, fresh])

    let viewModel = SharedScenariosViewModel(galleryService: service, repository: repo)
    await viewModel.load()

    #expect(viewModel.visibleScenarios.map(\.id) == ["fresh", "installed"])
    #expect(viewModel.installedUnchangedIds == ["installed"])
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

    // The detail screen applies the update; the pop re-syncs. Same transition
    // into installed-and-unchanged as a fresh install → pinned, still visible.
    try installBehindTheList(scenario, in: repo)
    await viewModel.refreshInstalledSnapshot()
    #expect(!viewModel.hasUpdate(for: scenario))
    #expect(viewModel.sessionPinnedIds == ["stale"])
    #expect(viewModel.visibleScenarios.map(\.id) == ["stale"])
  }

  /// The clearing half of the `refreshInstalledSnapshot()` invariant: `load()`
  /// ends in `refresh()`, which drops the pins — so the re-appear path must
  /// never call it (see the VM doc comment).
  @Test func loadClearsSessionPins() async throws {
    let repo = try makeRepo()
    let scenario = makeGalleryScenario(id: "pinned")
    let other = makeGalleryScenario(id: "other")
    let service = StubVMGalleryService()
    service.cachedIndex = makeIndex([scenario, other])
    let viewModel = SharedScenariosViewModel(galleryService: service, repository: repo)
    await viewModel.load()
    try installBehindTheList(scenario, in: repo)
    await viewModel.refreshInstalledSnapshot()
    #expect(viewModel.sessionPinnedIds == ["pinned"])

    await viewModel.load()
    #expect(viewModel.sessionPinnedIds.isEmpty)
    // The pin is gone, so "pinned" is now installed-and-unchanged and sorts
    // after "other" regardless of the two ids' relative ordering.
    #expect(viewModel.visibleScenarios.map(\.id) == ["other", "pinned"])
  }

  @Test func rowInstalledBehindTheListStaysPinnedUntilRefresh() async throws {
    let repo = try makeRepo()
    let scenario = makeGalleryScenario(id: "acted_on")
    // Older `addedAt` than the default ("2026-04-14") so the plain date sort
    // would otherwise put "acted_on" first — making the pin's effect on
    // position observable rather than incidental.
    let other = GalleryScenario(
      id: "other", title: "Other", category: .socialPsychology,
      description: "desc", author: "t",
      recommendedModel: ModelRegistry.gemma4E2B.id, estimatedInferences: 10,
      // swiftlint:disable:next force_unwrapping
      yamlURL: URL(string: "https://example.com/other.yaml")!,
      yamlSHA256: "otherhash", addedAt: "2026-01-01")
    let service = StubVMGalleryService()
    service.cachedIndex = makeIndex([scenario, other])

    let viewModel = SharedScenariosViewModel(galleryService: service, repository: repo)
    await viewModel.load()
    #expect(viewModel.visibleScenarios.map(\.id) == ["acted_on", "other"])

    // Detail screen installs it; the pop re-syncs the snapshot.
    try installBehindTheList(scenario, in: repo)
    await viewModel.refreshInstalledSnapshot()
    #expect(viewModel.isInstalled(scenario))
    #expect(viewModel.sessionPinnedIds == ["acted_on"])
    #expect(
      viewModel.visibleScenarios.map(\.id) == ["acted_on", "other"],
      "must not vanish or move under the restored scroll while pinned")

    // A later refresh treats it like any other installed row: the pin drops
    // and it sorts to the bottom.
    await viewModel.refresh()
    #expect(viewModel.sessionPinnedIds.isEmpty)
    #expect(viewModel.visibleScenarios.map(\.id) == ["other", "acted_on"])
  }
}
