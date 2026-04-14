import SwiftUI

// Helpers factored out of SimulationView so that the main file stays under
// SwiftLint's file-length ceiling. These render individual log-entry kinds
// used by the live simulation screen.
extension SimulationView {
  func eliminationEntry(agent: String, voteCount: Int) -> some View {
    HStack(spacing: 4) {
      Image(systemName: "xmark.circle.fill")
        .foregroundStyle(.red)
      Text("\(agent) eliminated (\(voteCount) votes)")
        .font(.subheadline)
    }
    .padding(.horizontal)
  }

  func assignmentEntry(agent: String, value: String) -> some View {
    Text("\(agent) assigned: \(value)")
      .font(.caption)
      .foregroundStyle(.secondary)
      .padding(.horizontal)
  }

  func summaryEntry(text: String) -> some View {
    Text(text)
      .font(.subheadline)
      .foregroundStyle(.secondary)
      .padding(.horizontal)
  }

  func voteResultsEntry(tallies: [String: Int]) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text("Vote Results")
        .font(.caption.bold())
      ForEach(tallies.sorted(by: { $0.value > $1.value }), id: \.key) { name, count in
        Text("  \(name): \(count) votes")
          .font(.caption)
      }
    }
    .foregroundStyle(.secondary)
    .padding(.horizontal)
  }

  func pairingResultEntry(
    agent1: String, act1: String, agent2: String, act2: String
  ) -> some View {
    HStack {
      Text("\(agent1)(\(act1))")
      Text("vs")
        .foregroundStyle(.secondary)
      Text("\(agent2)(\(act2))")
    }
    .font(.subheadline)
    .padding(.horizontal)
  }

  func roundSeparator(_ text: String) -> some View {
    HStack {
      Rectangle().fill(.secondary.opacity(0.3)).frame(height: 1)
      Text(text)
        .font(.caption.bold())
        .foregroundStyle(.secondary)
      Rectangle().fill(.secondary.opacity(0.3)).frame(height: 1)
    }
    .padding(.horizontal)
    .padding(.vertical, 4)
  }

  func scoresSummary(_ scores: [String: Int]) -> some View {
    HStack(spacing: 8) {
      ForEach(scores.sorted(by: { $0.value > $1.value }).prefix(5), id: \.key) { name, score in
        Text("\(name):\(score)")
          .font(.caption.monospacedDigit())
      }
    }
    .foregroundStyle(.secondary)
    .padding(.horizontal)
  }
}
