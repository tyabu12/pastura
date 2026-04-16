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
    }
  }

  private func eliminationRow(agent: String, voteCount: Int) -> some View {
    HStack(spacing: 4) {
      Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
      Text("\(filtered(agent)) eliminated (\(voteCount) votes)")
        .font(.subheadline)
    }
    .padding(.horizontal)
  }

  private func scoreUpdateRow(scores: [String: Int]) -> some View {
    let ordered = scores.sorted { lhs, rhs in
      if lhs.value != rhs.value { return lhs.value > rhs.value }
      return lhs.key < rhs.key
    }
    let pairs = ordered.map { "\(filtered($0.key)): \($0.value)" }.joined(separator: ", ")
    return Text("Scores — \(pairs)")
      .font(.caption.monospacedDigit())
      .foregroundStyle(.secondary)
      .padding(.horizontal)
  }

  private func summaryRow(text: String) -> some View {
    Text(filtered(text))
      .font(.subheadline)
      .foregroundStyle(.secondary)
      .padding(.horizontal)
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
      Text("Vote Results").font(.caption.bold())
      ForEach(orderedTallies, id: \.key) { name, count in
        Text("  \(filtered(name)): \(count) votes").font(.caption)
      }
      Text("Votes").font(.caption.bold()).padding(.top, 4)
      ForEach(orderedVotes, id: \.key) { voter, target in
        Text("  \(filtered(voter)) → \(filtered(target))").font(.caption)
      }
    }
    .foregroundStyle(.secondary)
    .padding(.horizontal)
  }

  private func pairingRow(
    agent1: String, action1: String, agent2: String, action2: String
  ) -> some View {
    HStack {
      Text("\(filtered(agent1))(\(filtered(action1)))")
      Text("vs").foregroundStyle(.secondary)
      Text("\(filtered(agent2))(\(filtered(action2)))")
    }
    .font(.subheadline)
    .padding(.horizontal)
  }

  private func assignmentRow(agent: String, value: String) -> some View {
    Text("\(filtered(agent)) assigned: \(filtered(value))")
      .font(.caption)
      .foregroundStyle(.secondary)
      .padding(.horizontal)
  }

  private func filtered(_ text: String) -> String {
    contentFilter.filter(text)
  }
}
