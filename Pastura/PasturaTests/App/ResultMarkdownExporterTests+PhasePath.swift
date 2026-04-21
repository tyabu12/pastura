import Foundation
import Testing

@testable import Pastura

// Sibling extension of `ResultMarkdownExporterTests` (see `.claude/rules/testing.md`
// "Splitting a Suite Across Files"). The original suite carries
// `.timeLimit(.minutes(1))` and `@MainActor`; these tests inherit both via the
// extension and the shared fixtures (`makeTurn`, `makeSimulation`, …).
extension ResultMarkdownExporterTests {

  @Test func nestedAndTopLevelSamePhaseTypeProduceTwoDistinctHeadings() throws {
    // path [0] → top-level, path [1,0] → nested sub-phase; same phaseType "speak_all"
    // must produce two separate headings rather than collapsing into one.
    let exporter = makeExporter()
    let topLevel = makeTurn(
      round: 1, seq: 1, phase: "speak_all",
      agent: "Alice", fields: ["statement": "top level"],
      phasePathJSON: "[0]")
    let nested = makeTurn(
      round: 1, seq: 2, phase: "speak_all",
      agent: "Bob", fields: ["statement": "nested sub-phase"],
      phasePathJSON: "[1,0]")
    let input = ResultMarkdownExporter.Input(
      simulation: makeSimulation(),
      scenario: makeScenario(),
      turns: [topLevel, nested],
      state: makeState())

    let result = try exporter.export(input)

    #expect(result.text.contains("#### Phase: speak_all"))
    #expect(result.text.contains("#### Sub-phase: speak_all (path [1, 0])"))
    // Alice belongs under the top-level heading, Bob under the sub-phase heading.
    let topRange = result.text.range(of: "#### Phase: speak_all")
    let subRange = result.text.range(of: "#### Sub-phase: speak_all (path [1, 0])")
    let aliceRange = result.text.range(of: "**Alice**")
    let bobRange = result.text.range(of: "**Bob**")
    #expect(topRange != nil && subRange != nil)
    #expect(aliceRange != nil && bobRange != nil)
    // Top-level heading should appear before the sub-phase heading (first-seen order).
    if let top = topRange, let sub = subRange {
      #expect(top.lowerBound < sub.lowerBound)
    }
    // Alice should appear before the sub-phase heading (she's in the top-level block).
    if let alice = aliceRange, let sub = subRange {
      #expect(alice.lowerBound < sub.lowerBound)
    }
    // Bob should appear after the sub-phase heading.
    if let bob = bobRange, let sub = subRange {
      #expect(bob.lowerBound > sub.lowerBound)
    }
  }

  @Test func mixedEraLegacyAndTopLevelSamePhaseTypeGroupTogether() throws {
    // Legacy (nil path) and v6 top-level ([0]) for the same phaseType must
    // render under a single "#### Phase: speak_all" heading in sequence order.
    let exporter = makeExporter()
    let legacy = makeTurn(
      round: 1, seq: 1, phase: "speak_all",
      agent: "Alice", fields: ["statement": "legacy turn"],
      phasePathJSON: nil)
    let newTopLevel = makeTurn(
      round: 1, seq: 2, phase: "speak_all",
      agent: "Bob", fields: ["statement": "v6 turn"],
      phasePathJSON: "[0]")
    let input = ResultMarkdownExporter.Input(
      simulation: makeSimulation(),
      scenario: makeScenario(),
      turns: [legacy, newTopLevel],
      state: makeState())

    let result = try exporter.export(input)

    // Exactly one top-level heading for speak_all — not two.
    let occurrences = result.text.components(separatedBy: "#### Phase: speak_all").count - 1
    #expect(occurrences == 1)
    // Both agents appear; Alice (legacy, seq=1) before Bob (v6, seq=2).
    let aliceRange = result.text.range(of: "**Alice**")
    let bobRange = result.text.range(of: "**Bob**")
    #expect(aliceRange != nil && bobRange != nil)
    if let alice = aliceRange, let bob = bobRange {
      #expect(alice.lowerBound < bob.lowerBound)
    }
    // No sub-phase heading should appear.
    #expect(!result.text.contains("#### Sub-phase:"))
  }

  @Test func orphanSubPhaseRendersWithoutParentHeading() throws {
    // A conditional sub-phase turn (path [0,0]) without a top-level parent
    // persisted must render as "#### Sub-phase: speak_all (path [0, 0])".
    // No "#### Phase: speak_all" heading is expected.
    let exporter = makeExporter()
    let subPhaseTurn = makeTurn(
      round: 1, seq: 1, phase: "speak_all",
      agent: "Alice", fields: ["statement": "from sub-phase"],
      phasePathJSON: "[0,0]")
    let input = ResultMarkdownExporter.Input(
      simulation: makeSimulation(),
      scenario: makeScenario(),
      turns: [subPhaseTurn],
      state: makeState())

    let result = try exporter.export(input)

    #expect(result.text.contains("#### Sub-phase: speak_all (path [0, 0])"))
    #expect(!result.text.contains("#### Phase: speak_all"))
  }
}
