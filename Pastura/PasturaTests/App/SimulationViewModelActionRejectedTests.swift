import Foundation
import Testing

@testable import Pastura

/// `.actionRejected` event surfacing (ADR-021 § Amendment 2026-07-17 / #1151).
/// A `choose` action that no normalization could map to the option set drops
/// its pairing; the App folds the event into the same `degradedTurnCount`
/// aggregate/badge as `.turnSkipped` and appends a per-rejection live-log line.
/// Unlike `.turnSkipped`, the `raw` value **is** carried (the whole point is to
/// show what the model said) and — being model content — MUST be
/// `ContentFilter`-rewritten before it reaches the UI (ADR-005). This suite
/// covers the live counting + narration + the mandatory filtering.
@Suite("SimulationViewModelActionRejected", .serialized, .timeLimit(.minutes(1)))
@MainActor
struct SimulationViewModelActionRejectedTests {

  @Test func actionRejectedIncrementsCountAndAppendsLogLine() throws {
    let (sut, scenario) = try makeSUT()
    sut.handleEvent(
      .actionRejected(agent: "Alice", phaseType: .choose, raw: "裏切る"),
      scenario: scenario)
    #expect(sut.degradedTurnCount == 1)
    guard case .actionRejected(let agent, let phaseType, let raw) = sut.logEntries.last?.kind
    else {
      Issue.record(
        "expected a .actionRejected log entry, got \(String(describing: sut.logEntries.last?.kind))"
      )
      return
    }
    #expect(agent == "Alice")
    #expect(phaseType == .choose)
    // The default SUT filter blocks only "badword", so a clean off-menu action
    // passes through verbatim.
    #expect(raw == "裏切る")
  }

  @Test func multipleActionRejectedAccumulateOneLinePerEvent() throws {
    let (sut, scenario) = try makeSUT()
    sut.handleEvent(
      .actionRejected(agent: "Alice", phaseType: .choose, raw: "betray!"),
      scenario: scenario)
    sut.handleEvent(
      .actionRejected(agent: "Bob", phaseType: .choose, raw: "裏切る"),
      scenario: scenario)
    #expect(sut.degradedTurnCount == 2)
    let rejectedLines = sut.logEntries.filter {
      if case .actionRejected = $0.kind { return true }
      return false
    }
    #expect(rejectedLines.count == 2)
  }

  /// ADR-005 headline: `raw` is model-emitted content, so the live log must
  /// show a `ContentFilter`-rewritten value — never the raw string. Reverting
  /// the `contentFilter.filter(raw)` call in `handleEvent`'s `.actionRejected`
  /// arm makes `storedRaw == rawInput` and fails here.
  @Test func actionRejectedRawIsContentFilteredBeforeLiveLog() throws {
    let filter = ContentFilter(blockedPatterns: ["betrayx"])
    let (sut, scenario) = try makeSUT(contentFilter: filter)
    let rawInput = "betrayx!"
    sut.handleEvent(
      .actionRejected(agent: "Alice", phaseType: .choose, raw: rawInput),
      scenario: scenario)
    guard case .actionRejected(_, _, let storedRaw) = sut.logEntries.last?.kind else {
      Issue.record(
        "expected a .actionRejected log entry, got \(String(describing: sut.logEntries.last?.kind))"
      )
      return
    }
    let expected = filter.filter(rawInput)
    // Non-tautological: the filter genuinely rewrites this input.
    #expect(expected != rawInput)
    #expect(storedRaw == expected)
    #expect(!storedRaw.contains("betrayx"))
  }
}
