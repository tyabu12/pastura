import Testing

@testable import Pastura

/// `ModelRegistry.shortDisplayName(forIdentifier:)` — the past-results share
/// card's model-name resolution (issue #1070). Maps a persisted
/// `SimulationRecord.modelIdentifier` (a descriptor `displayName`) to its short
/// label so the past-results card matches the live card.
@Suite(.timeLimit(.minutes(1)))
struct ModelRegistryShortNameTests {

  @Test("A known catalog displayName resolves to its short label")
  func resolvesCatalogDisplayName() throws {
    let descriptor = try #require(ModelRegistry.catalog.first)
    let resolved = ModelRegistry.shortDisplayName(forIdentifier: descriptor.displayName)
    #expect(resolved == (descriptor.shortDisplayName ?? descriptor.displayName))
  }

  @Test("nil / empty identifier yields nil (line omitted)")
  func nilAndEmptyYieldNil() {
    #expect(ModelRegistry.shortDisplayName(forIdentifier: nil) == nil)
    #expect(ModelRegistry.shortDisplayName(forIdentifier: "") == nil)
  }

  @Test("Unknown identifier (superseded model) falls back to the raw string")
  func unknownFallsBackToRaw() {
    let raw = "Some Legacy Model 0.9B (Q2_K)"
    #expect(ModelRegistry.shortDisplayName(forIdentifier: raw) == raw)
  }
}
