import SwiftUI

// Code-phase row renderers for `ResultDetailView`.
//
// Intentionally mirrors `ResultMarkdownExporter.renderCodePhasePayload(_:)`
// styling (full vote / score / voter lists), NOT
// `SimulationView+LogEntries.swift` which trims to top-N inline. The view's
// goal here is parity with the exported Markdown — Issue #102.
//
// Every user-visible string that could carry user-authored content (persona
// names, action labels, summary text, assignment values, vote targets) is
// passed through `contentFilter` to match the exporter's whole-string filter
// pass. Vote counts and scores are pure integers and don't need filtering.
//
// Per-row `.padding(.horizontal)` was stripped from every helper here in
// #273 PR 2 — `ResultDetailView.timelineLog` now applies a container-level
// `.padding(.horizontal, 20)` once on its parent `LazyVStack`, matching
// the strategy already in `SimulationView+LogEntries.swift`. Without the
// strip, code-phase rows would render at ~36pt-inset (20pt container +
// ~16pt per-row default) while turn rows render at 20pt-inset, which is
// exactly the cross-row misalignment this refactor was meant to eliminate.
extension ResultDetailView {

  @ViewBuilder
  func codePhaseRow(_ payload: CodePhaseEventPayload) -> some View {
    switch payload {
    case .elimination(let agent, let voteCount):
      eliminationRow(agent: agent, voteCount: voteCount)
    case .scoreUpdate(let scores):
      scoreUpdateRow(scores: scores)
    case .summary(let text):
      summaryRow(text: text)
    case .voteResults(let votes, let tallies):
      voteResultsRow(votes: votes, tallies: tallies)
    case .pairingResult(let agent1, let action1, let agent2, let action2):
      pairingRow(agent1: agent1, action1: action1, agent2: agent2, action2: action2)
    case .assignment(let agent, let value):
      assignmentRow(agent: agent, value: value)
    case .eventInjected(let event):
      eventInjectedRow(event: event)
    }
  }

  private func eliminationRow(agent: String, voteCount: Int) -> some View {
    HStack(spacing: 4) {
      Image(systemName: "xmark.circle.fill").foregroundStyle(Color.inkSecondary)
      Text("\(filtered(agent)) eliminated (\(voteCount) votes)")
        .textStyle(Typography.titlePhase)
    }
  }

  private func scoreUpdateRow(scores: [String: Int]) -> some View {
    let ordered = scores.sorted { lhs, rhs in
      if lhs.value != rhs.value { return lhs.value > rhs.value }
      return lhs.key < rhs.key
    }
    let pairs = ordered.map { "\(filtered($0.key)): \($0.value)" }.joined(separator: ", ")
    return Text("Scores — \(pairs)")
      .textStyle(Typography.metaValue)
      .monospacedDigit()
      .foregroundStyle(Color.muted)
  }

  private func summaryRow(text: String) -> some View {
    Text(filtered(text))
      .textStyle(Typography.bodyBubble)
      .foregroundStyle(Color.inkSecondary)
  }

  private func voteResultsRow(
    votes: [String: String], tallies: [String: Int]
  ) -> some View {
    let orderedTallies = tallies.sorted { lhs, rhs in
      if lhs.value != rhs.value { return lhs.value > rhs.value }
      return lhs.key < rhs.key
    }
    let orderedVotes = votes.sorted { $0.key < $1.key }
    return VStack(alignment: .leading, spacing: 2) {
      // `metaLabel` (9pt semibold mono, non-upper) instead of
      // `tagPhase` — `tagPhase` uppercases, and prose-ish headings
      // like "Vote Results" read worse shouty. `tagPhase` stays on
      // one-word tag markers (WORD WOLF, ROUND 1) per design-system
      // §3.2.
      Text("Vote Results").textStyle(Typography.metaLabel).foregroundStyle(Color.inkSecondary)
      ForEach(orderedTallies, id: \.key) { name, count in
        Text("  \(filtered(name)): \(count) votes").textStyle(Typography.metaValue)
      }
      Text("Votes").textStyle(Typography.metaLabel).foregroundStyle(Color.inkSecondary)
        .padding(.top, 4)
      ForEach(orderedVotes, id: \.key) { voter, target in
        Text("  \(filtered(voter)) → \(filtered(target))").textStyle(Typography.metaValue)
      }
    }
    .foregroundStyle(Color.muted)
  }

  private func pairingRow(
    agent1: String, action1: String, agent2: String, action2: String
  ) -> some View {
    HStack {
      Text("\(filtered(agent1))(\(filtered(action1)))")
      Text("vs").foregroundStyle(Color.muted)
      Text("\(filtered(agent2))(\(filtered(action2)))")
    }
    .textStyle(Typography.titlePhase)
  }

  private func assignmentRow(agent: String, value: String) -> some View {
    Text("\(filtered(agent)) assigned: \(filtered(value))")
      .textStyle(Typography.metaValue)
      .foregroundStyle(Color.muted)
  }

  // The miss case (`event == nil`) renders an explicit "no event"
  // marker rather than disappearing — past-results timelines should
  // distinguish "phase didn't run" from "phase ran and rolled a miss".
  @ViewBuilder
  private func eventInjectedRow(event: String?) -> some View {
    if let event {
      Text("Event: \(filtered(event))")
        .textStyle(Typography.bodyBubble)
        .foregroundStyle(Color.inkSecondary)
    } else {
      Text("No event this round")
        .textStyle(Typography.metaValue)
        .foregroundStyle(Color.muted)
    }
  }

  private func filtered(_ text: String) -> String {
    contentFilter.filter(text)
  }
}
