import Foundation
import Testing

@testable import Pastura

/// Pins ``RelationshipVerbalizer`` — the raw-affinity-matrix → prose renderer
/// injected into `relationship_update` agent prompts (#910). Assertions use
/// partial `.contains` matching (CLAUDE.md "Error message i18n prep") so future
/// phrasing tweaks don't break the test on the exact wording.
@Suite(.timeLimit(.minutes(1)))
struct RelationshipVerbalizerTests {

  @Test func emptyMatrixProducesEmptyString() {
    #expect(RelationshipVerbalizer.summarize([:], language: "ja").isEmpty)
    #expect(RelationshipVerbalizer.summarize([:], language: "en").isEmpty)
  }

  @Test func belowThresholdIsOmitted() {
    // |1| < mentionThreshold (2), so nothing is verbalized.
    #expect(RelationshipVerbalizer.summarize(["Bob": 1], language: "en").isEmpty)
    #expect(RelationshipVerbalizer.summarize(["Bob": -1], language: "en").isEmpty)
    #expect(RelationshipVerbalizer.summarize(["Bob": 0], language: "ja").isEmpty)
  }

  @Test func atThresholdIsMentioned() {
    // |2| == mentionThreshold, so it surfaces (inclusive boundary).
    #expect(!RelationshipVerbalizer.summarize(["Bob": 2], language: "en").isEmpty)
    #expect(!RelationshipVerbalizer.summarize(["Bob": -2], language: "en").isEmpty)
  }

  @Test func positiveScoreReadsAsWarmth() {
    let en = RelationshipVerbalizer.summarize(["Bob": 3], language: "en")
    #expect(en.contains("Bob"))
    #expect(en.contains("warmly"))
    let ja = RelationshipVerbalizer.summarize(["Bob": 3], language: "ja")
    #expect(ja.contains("Bob"))
    #expect(ja.contains("好感"))
  }

  @Test func negativeScoreReadsAsWariness() {
    let en = RelationshipVerbalizer.summarize(["Ryuji": -3], language: "en")
    #expect(en.contains("Ryuji"))
    #expect(en.contains("wary"))
    let ja = RelationshipVerbalizer.summarize(["Ryuji": -3], language: "ja")
    #expect(ja.contains("Ryuji"))
    #expect(ja.contains("警戒"))
  }

  @Test func mentionsAreSortedByNameForDeterminism() {
    // Zoe warm (+2), Ada wary (-2). Deterministic output orders by name,
    // so "Ada" must precede "Zoe" regardless of dictionary iteration order.
    let summary = RelationshipVerbalizer.summarize(["Zoe": 2, "Ada": -2], language: "en")
    let adaIndex = summary.range(of: "Ada").map {
      summary.distance(from: summary.startIndex, to: $0.lowerBound)
    }
    let zoeIndex = summary.range(of: "Zoe").map {
      summary.distance(from: summary.startIndex, to: $0.lowerBound)
    }
    #expect(adaIndex != nil && zoeIndex != nil)
    if let adaIndex, let zoeIndex {
      #expect(adaIndex < zoeIndex)
    }
  }

  @Test func mixesThresholdAndBelowThresholdEntries() {
    // Only the two notable entries appear; the |1| entry is dropped.
    let summary = RelationshipVerbalizer.summarize(
      ["Ada": 2, "Bob": 1, "Zoe": -4], language: "en")
    #expect(summary.contains("Ada"))
    #expect(summary.contains("Zoe"))
    #expect(!summary.contains("Bob"))
  }
}
