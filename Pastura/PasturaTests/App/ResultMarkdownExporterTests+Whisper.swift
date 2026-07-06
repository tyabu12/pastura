import Foundation
import Testing

@testable import Pastura

// Sibling-file extension of `ResultMarkdownExporterTests` (keeps the main
// suite under the 400-line file_length cap). NOT a new `@Suite` — Swift
// Testing runs suites in parallel, and these tests share the suite's
// `makeExporter` / `makeTurn` helpers (see `.claude/rules/testing.md`).
//
// #908 PR2: whisper (密談) turns carry pair attribution — "🤫 A → B" — so a
// Markdown export reads the private exchange as directed, mirroring the
// `pairingResult` "**A** ↔ **B**" precedent.
extension ResultMarkdownExporterTests {

  @Test func rendersWhisperWithPairAttribution() throws {
    let exporter = makeExporter()
    let turn = makeTurn(
      round: 1, seq: 1, phase: "whisper",
      agent: "Alice",
      fields: ["statement": "let's team up", "whisper_to": "Bob", "inner_thought": "risky"])
    let input = ResultMarkdownExporter.Input(
      simulation: makeSimulation(),
      scenario: makeScenario(),
      turns: [turn],
      state: makeState())

    let result = try exporter.export(input)

    // Primary line names both ends of the whisper.
    #expect(result.text.contains("- 🤫 **Alice** → **Bob**: let's team up"))
    // It must NOT fall back to the plain speaker line.
    #expect(!result.text.contains("- **Alice**: let's team up"))
    // The private thought still renders as the nested 💭 bullet.
    #expect(result.text.contains("  - 💭 _risky_"))
  }

  @Test func whisperWithoutPartnerFallsBackToPlainLine() throws {
    // A whisper turn missing `whisper_to` (or blank) must render the plain
    // speaker line, never a dangling "Alice → ".
    let exporter = makeExporter()
    let turn = makeTurn(
      round: 1, seq: 1, phase: "whisper",
      agent: "Alice",
      fields: ["statement": "hello", "whisper_to": "   "])
    let input = ResultMarkdownExporter.Input(
      simulation: makeSimulation(),
      scenario: makeScenario(),
      turns: [turn],
      state: makeState())

    let result = try exporter.export(input)

    #expect(result.text.contains("- **Alice**: hello"))
    #expect(!result.text.contains("🤫"))
    #expect(!result.text.contains("→"))
  }
}
