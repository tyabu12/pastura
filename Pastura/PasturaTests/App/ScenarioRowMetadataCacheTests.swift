import Foundation
import Testing

@testable import Pastura

@Suite(.timeLimit(.minutes(1)))
struct ScenarioRowMetadataCacheTests {
  private func record(id: String, name: String, updatedAt: Date) -> ScenarioRecord {
    ScenarioRecord(
      id: id, name: name, yamlDefinition: "",
      isPreset: true, createdAt: Date(), updatedAt: updatedAt)
  }

  @Test func resolvesEveryRecordKeyedById() {
    var cache = ScenarioRowMetadataCache()
    let now = Date()
    let records = [
      record(id: "a", name: "A", updatedAt: now),
      record(id: "b", name: "B", updatedAt: now)
    ]
    let result = cache.resolve(records) { ScenarioRowMetadata(name: $0.name, agentCount: 2) }
    #expect(Set(result.keys) == ["a", "b"])
    #expect(result["a"]?.agentCount == 2)
  }

  @Test func reusesParseForUnchangedUpdatedAt() {
    var cache = ScenarioRowMetadataCache()
    let now = Date()
    let records = [record(id: "a", name: "A", updatedAt: now)]
    var parseCount = 0
    let parse: (ScenarioRecord) -> ScenarioRowMetadata = {
      parseCount += 1
      return ScenarioRowMetadata(name: $0.name)
    }

    _ = cache.resolve(records, parse: parse)
    #expect(parseCount == 1)

    // Same (id, updatedAt) on a second load reuses the memoized parse.
    _ = cache.resolve(records, parse: parse)
    #expect(parseCount == 1)
  }

  @Test func bumpedUpdatedAtForcesReparse() {
    var cache = ScenarioRowMetadataCache()
    let earlier = Date(timeIntervalSince1970: 1000)
    let later = Date(timeIntervalSince1970: 2000)
    var parseCount = 0
    let parse: (ScenarioRecord) -> ScenarioRowMetadata = {
      parseCount += 1
      // Echo the round count off updatedAt so a stale (id-only) cache would
      // surface the wrong value, not just the wrong count.
      return ScenarioRowMetadata(name: $0.name, rounds: Int($0.updatedAt.timeIntervalSince1970))
    }

    let first = cache.resolve([record(id: "a", name: "A", updatedAt: earlier)], parse: parse)
    #expect(first["a"]?.rounds == 1000)
    #expect(parseCount == 1)

    // updatedAt bump (e.g. a gallery update) invalidates the entry → re-parse,
    // and the result reflects the NEW value rather than the stale one.
    let second = cache.resolve([record(id: "a", name: "A", updatedAt: later)], parse: parse)
    #expect(second["a"]?.rounds == 2000)
    #expect(parseCount == 2)
  }

  @Test func rebuildsToCurrentKeySetDroppingStaleEntries() {
    var cache = ScenarioRowMetadataCache()
    let now = Date()
    var parseCount = 0
    let parse: (ScenarioRecord) -> ScenarioRowMetadata = {
      parseCount += 1
      return ScenarioRowMetadata(name: $0.name)
    }

    _ = cache.resolve([record(id: "a", name: "A", updatedAt: now)], parse: parse)
    #expect(parseCount == 1)

    // "a" disappears (deleted) and "b" appears. The memo is rebuilt to the
    // current key set, so a later reload of "a" must re-parse (its stale
    // entry was dropped) — proving the memo doesn't grow unbounded.
    _ = cache.resolve([record(id: "b", name: "B", updatedAt: now)], parse: parse)
    #expect(parseCount == 2)

    _ = cache.resolve([record(id: "a", name: "A", updatedAt: now)], parse: parse)
    #expect(parseCount == 3)
  }
}
