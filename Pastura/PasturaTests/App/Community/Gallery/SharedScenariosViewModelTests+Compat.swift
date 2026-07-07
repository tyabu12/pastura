import Foundation
import Testing

@testable import Pastura

// Sibling-file extension of `SharedScenariosViewModelTests` (not a new `@Suite`)
// per `.claude/rules/testing.md`. Covers the ADR-020 D2/D3 compatibility seam
// the Browse grey-out gate reads (`SharedScenariosViewModel.isCompatible`).
// The predicate itself is exhaustively unit-tested in
// `EngineSchemaVersionTests`; these cases pin the VM's *wiring* — that it reads
// the scenario's `phases` and `min_engine_version` into the gate.
extension SharedScenariosViewModelTests {

  private func makeCompatVM() throws -> SharedScenariosViewModel {
    SharedScenariosViewModel(galleryService: StubVMGalleryService(), repository: try makeRepo())
  }

  private func makeScenario(phases: [String]?, minEngineVersion: Int?) -> GalleryScenario {
    GalleryScenario(
      id: "compat_v1",
      title: "Compat",
      category: .socialPsychology,
      description: "desc",
      author: "t",
      recommendedModel: ModelRegistry.gemma4E2B.id,
      estimatedInferences: 5,
      // swiftlint:disable:next force_unwrapping
      yamlURL: URL(string: "https://example.com/compat_v1.yaml")!,
      yamlSHA256: String(repeating: "0", count: 64),
      addedAt: "2026-07-07",
      phases: phases,
      minEngineVersion: minEngineVersion)
  }

  @Test func isCompatibleWhenPhasesKnownAndNoVersionFloor() throws {
    let sut = try makeCompatVM()
    #expect(sut.isCompatible(makeScenario(phases: nil, minEngineVersion: nil)))
    #expect(sut.isCompatible(makeScenario(phases: ["speak_all", "vote"], minEngineVersion: nil)))
  }

  @Test func isIncompatibleWhenPhaseUnknown() throws {
    let sut = try makeCompatVM()
    #expect(!sut.isCompatible(makeScenario(phases: ["future_phase"], minEngineVersion: nil)))
  }

  @Test func isIncompatibleWhenMinEngineVersionExceedsCurrent() throws {
    let sut = try makeCompatVM()
    #expect(
      !sut.isCompatible(
        makeScenario(phases: nil, minEngineVersion: EngineSchemaVersion.current + 1)))
  }
}
