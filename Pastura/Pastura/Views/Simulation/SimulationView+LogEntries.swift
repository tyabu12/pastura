import SwiftUI

// Helpers factored out of SimulationView so that the main file stays under
// SwiftLint's file-length ceiling. These render individual log-entry kinds
// used by the live simulation screen.
extension SimulationView {
  func eliminationEntry(agent: String, voteCount: Int) -> some View {
    HStack(spacing: 4) {
      Image(systemName: "xmark.circle.fill")
        .foregroundStyle(Color.inkSecondary)
      Text("\(agent) eliminated (\(voteCount) votes)")
        .textStyle(Typography.titlePhase)
    }
    .padding(.horizontal)
  }

  func assignmentEntry(agent: String, value: String) -> some View {
    Text("\(agent) assigned: \(value)")
      .textStyle(Typography.metaValue)
      .foregroundStyle(Color.muted)
      .padding(.horizontal)
  }

  func summaryEntry(text: String) -> some View {
    Text(text)
      .textStyle(Typography.bodyBubble)
      .foregroundStyle(Color.inkSecondary)
      .padding(.horizontal)
  }

  func voteResultsEntry(tallies: [String: Int]) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      // `metaLabel` (9pt semibold mono, non-upper) instead of `tagPhase`
      // — the latter uppercases, and "Vote Results" as a prose-ish
      // section heading reads worse as "VOTE RESULTS". `tagPhase` is
      // reserved for one-word tags (WORD WOLF, ROUND 1).
      Text("Vote Results")
        .textStyle(Typography.metaLabel)
        .foregroundStyle(Color.inkSecondary)
      ForEach(tallies.sorted(by: { $0.value > $1.value }), id: \.key) { name, count in
        Text("  \(name): \(count) votes")
          .textStyle(Typography.metaValue)
      }
    }
    .foregroundStyle(Color.muted)
    .padding(.horizontal)
  }

  func pairingResultEntry(
    agent1: String, act1: String, agent2: String, act2: String
  ) -> some View {
    HStack {
      Text("\(agent1)(\(act1))")
      Text("vs")
        .foregroundStyle(Color.muted)
      Text("\(agent2)(\(act2))")
    }
    .textStyle(Typography.titlePhase)
    .padding(.horizontal)
  }

  /// Live row for `event_inject` phase results.
  ///
  /// The miss case (`event == nil`) renders an explicit "no event"
  /// marker rather than disappearing — users observing a probabilistic
  /// phase need to see the dice roll, not just the hits.
  @ViewBuilder
  func eventInjectedEntry(event: String?) -> some View {
    if let event {
      HStack(spacing: 4) {
        Image(systemName: "die.face.5").foregroundStyle(Color.inkSecondary)
        Text(event)
          .textStyle(Typography.bodyBubble)
          .foregroundStyle(Color.inkSecondary)
      }
      .padding(.horizontal)
    } else {
      Text("No event this round")
        .textStyle(Typography.metaValue)
        .foregroundStyle(Color.muted)
        .padding(.horizontal)
    }
  }

  func roundSeparator(_ text: String) -> some View {
    HStack {
      Rectangle().fill(Color.rule).frame(height: 1)
      // `metaLabel` keeps "Round N/M" mixed case — tagPhase would
      // upper-case to "ROUND N/M" which reads shouty for a prose
      // marker. tagPhase stays reserved for one-word phase tags
      // (WORD WOLF). See design-system §3.2.
      Text(text)
        .textStyle(Typography.metaLabel)
        .foregroundStyle(Color.inkSecondary)
      Rectangle().fill(Color.rule).frame(height: 1)
    }
    .padding(.horizontal)
    .padding(.vertical, 4)
  }

  func scoresSummary(_ scores: [String: Int]) -> some View {
    HStack(spacing: 8) {
      ForEach(scores.sorted(by: { $0.value > $1.value }).prefix(5), id: \.key) { name, score in
        Text("\(name):\(score)")
          .textStyle(Typography.metaValue)
          .monospacedDigit()
      }
    }
    .foregroundStyle(Color.muted)
    .padding(.horizontal)
  }
}
