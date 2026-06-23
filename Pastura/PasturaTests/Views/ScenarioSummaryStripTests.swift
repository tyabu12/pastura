import Testing

@testable import Pastura

/// Unit tests for the scenario-detail hero summary strip's pure formatting
/// (the `Agents 2 · Rounds 1 · Est. Inferences 2` line). Asserts logic
/// properties only, never rendered output (ADR-009 /
/// `.claude/rules/view-testing.md`).
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct ScenarioSummaryStripTests {

  @Test func joinsFragmentsWithMiddleDotSeparator() {
    let strip = ScenarioSummaryStrip.text(stats: [
      ("Agents", 2), ("Rounds", 1), ("Est. Inferences", 2)
    ])
    #expect(strip == "Agents 2 · Rounds 1 · Est. Inferences 2")
  }

  @Test func interpolatesEachValueNextToItsLabel() {
    let strip = ScenarioSummaryStrip.text(stats: [
      ("A", 5), ("R", 12), ("I", 60)
    ])
    #expect(strip == "A 5 · R 12 · I 60")
  }

  /// Labels are injected already-localized, so a ja label flows through
  /// verbatim — proving the formatter never re-keys on an English literal.
  @Test func passesLocalizedLabelsThroughVerbatim() {
    let strip = ScenarioSummaryStrip.text(stats: [
      ("エージェント", 3), ("ラウンド", 4), ("推論数", 9)
    ])
    #expect(strip == "エージェント 3 · ラウンド 4 · 推論数 9")
  }

  /// A single stat renders with no separator; an empty list renders empty.
  @Test func handlesSingleAndEmptyStatLists() {
    #expect(ScenarioSummaryStrip.text(stats: [("Agents", 1)]) == "Agents 1")
    #expect(ScenarioSummaryStrip.text(stats: []) == "")
  }
}
