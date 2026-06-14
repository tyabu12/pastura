import Foundation
import Testing

@testable import Pastura

// Sibling-file extension of `ResultMarkdownExporterTests` (keeps the main
// suite under the 400-line file_length cap). NOT a new `@Suite` — Swift
// Testing runs suites in parallel, and these tests share the suite's
// `makeExporter` / `makeTurn` helpers (see `.claude/rules/testing.md`).
extension ResultMarkdownExporterTests {
  // #609: the vote `reason` is the vote-phase private-thought field. It
  // renders in the same 💭 nested bullet as speak's inner_thought (resolved
  // via `TurnOutput.secondaryText(for:)`), NOT inline in the primary line.
  @Test func rendersVoteReasonAsNestedThought() throws {
    let exporter = makeExporter()
    let turn = makeTurn(
      round: 1, seq: 1, phase: "vote",
      agent: "Alice", fields: ["vote": "Bob", "reason": "Bob is bluffing"])
    let input = ResultMarkdownExporter.Input(
      simulation: makeSimulation(),
      scenario: makeScenario(),
      turns: [turn],
      state: makeState())

    let result = try exporter.export(input)

    // Primary line carries the bare arrow form — reason is NOT inline.
    #expect(result.text.contains("- **Alice**: → Bob"))
    #expect(!result.text.contains("→ Bob (Bob is bluffing)"))
    // Reason appears as the 💭 thought bullet.
    #expect(result.text.contains("  - 💭 _Bob is bluffing_"))
  }
}
