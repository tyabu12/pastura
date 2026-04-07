import SwiftUI

/// Modal sheet displaying current scores and elimination status.
struct ScoreboardSheet: View {
  let scores: [String: Int]
  let eliminated: [String: Bool]

  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      List {
        ForEach(sortedAgents, id: \.name) { entry in
          HStack {
            Text("\(entry.rank).")
              .foregroundStyle(.secondary)
              .monospacedDigit()
              .frame(width: 30, alignment: .trailing)

            Text(entry.name)
              .font(.body)
              .strikethrough(entry.isEliminated)

            Spacer()

            Text("\(entry.score) pts")
              .font(.body.monospacedDigit())
              .foregroundStyle(entry.isEliminated ? .secondary : .primary)

            if entry.isEliminated {
              Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
                .font(.caption)
            } else {
              Image(systemName: "circle.fill")
                .foregroundStyle(.green)
                .font(.caption)
            }
          }
        }
      }
      .navigationTitle("Scoreboard")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { dismiss() }
        }
      }
    }
  }

  private struct AgentEntry: Identifiable {
    let rank: Int
    let name: String
    let score: Int
    let isEliminated: Bool
    var id: String { name }
  }

  private var sortedAgents: [AgentEntry] {
    let sorted =
      scores
      .sorted { $0.value > $1.value }
      .enumerated()
      .map { index, pair in
        AgentEntry(
          rank: index + 1,
          name: pair.key,
          score: pair.value,
          isEliminated: eliminated[pair.key] ?? false
        )
      }
    return sorted
  }
}
