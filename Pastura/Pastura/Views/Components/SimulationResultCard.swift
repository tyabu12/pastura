import SwiftUI

/// Final-ranking "curtain" card shown once at the tail of a completed
/// simulation log (issue #868).
///
/// The mirror image of ``ScenarioIntroCard`` (#853): where the intro card sets
/// the scene above the first turn, this card resolves the *outcome* below the
/// last one. Before it, a run's terminal result (scores / vote tallies /
/// eliminations) rendered as ordinary 9pt-mono log rows — visually
/// indistinguishable from mid-run chatter. This card gives the outcome its own
/// elevated container and heavier type so "the result is in" reads at a glance.
///
/// Presentation-only by design (ADR-009): it takes an already-resolved
/// ``Model`` derived from plain value dictionaries, never the Engine/Data
/// domain types, so the derivation is unit-tested (`SimulationResultCardTests`)
/// while layout / motion / the tap affordance are code-review + device-QA gated.
/// The ``Model`` resolver lives in `SimulationResultCard+Model.swift`.
struct SimulationResultCard: View {
  /// How the outcome is framed. The resolver classifies every completed run
  /// into one of these; the seam lets future work diverge the layouts further
  /// (today `.ranking` and `.pairing` render identically — the eyebrow differs).
  nonisolated enum Framing: Equatable {
    /// Score-based leaderboard, or a vote-only "popularity vote".
    case ranking
    /// Per-agent scores from a round-robin / prisoner's-dilemma pairing.
    case pairing
    /// Vote/elimination outcome — who is left standing is the headline.
    case survival
  }

  /// Which number (if any) a row shows next to an agent, so the View renders
  /// the right unit without re-deriving semantics.
  nonisolated enum ValueKind: Equatable {
    case points
    case votes
    /// No meaningful number for this row (e.g. a survivor whose last-round
    /// received-vote count is not comparable across rounds).
    case none
  }

  /// One agent's row in the resolved outcome.
  nonisolated struct Entry: Identifiable, Equatable {
    /// Agent name — also the identity (agents are unique within a run).
    let id: String
    let name: String
    /// 1-based rank for `.ranking` / `.pairing`; `nil` under `.survival`,
    /// which groups by survived/eliminated rather than assigning a rank.
    let rank: Int?
    let isEliminated: Bool
    /// The number to show, or `nil` to show none. Paired with ``valueKind``.
    let primaryValue: Int?
    let valueKind: ValueKind
  }

  let model: Model

  /// Whether this run has scores worth a full scoreboard. Drives the
  /// tap-to-scoreboard affordance (wired by the host in a follow-up): a
  /// vote-only survival card has all its data on-screen already, so it should
  /// not offer a "0 pts" scoreboard.
  var onTap: (() -> Void)?

  var body: some View {
    let surface = cardSurface
    if let onTap {
      Button(action: onTap) { surface }
        .buttonStyle(.plain)
        .accessibilityHint(String(localized: "Shows the full scoreboard"))
    } else {
      surface
    }
  }

  private var cardSurface: some View {
    PasturaCard {
      VStack(alignment: .leading, spacing: Spacing.xs) {
        eyebrow
        content
      }
      .padding(Spacing.m)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  /// Small framing heading with a leading glyph — orients the viewer that this
  /// block is the settled outcome, not another agent turn.
  private var eyebrow: some View {
    HStack(spacing: Spacing.xxs) {
      Image(systemName: eyebrowSymbol)
        .accessibilityHidden(true)
      Text(eyebrowLabel)
      if onTap != nil {
        Spacer(minLength: Spacing.xxs)
        Image(systemName: "chevron.right")
          .accessibilityHidden(true)
      }
    }
    .textStyle(Typography.captionName)
    .foregroundStyle(Color.mossDark)
  }

  @ViewBuilder private var content: some View {
    switch model.framing {
    case .ranking, .pairing:
      ForEach(model.entries) { rankedRow($0) }
    case .survival:
      survivalGroups
    }
  }

  private func rankedRow(_ entry: Entry) -> some View {
    let isWinner = entry.rank == 1
    return HStack(spacing: Spacing.xs) {
      if let rank = entry.rank {
        Text(verbatim: "\(rank)")
          .textStyle(Typography.bodyBubble)
          .monospacedDigit()
          .foregroundStyle(isWinner ? Color.mossInk : Color.muted)
          .frame(width: 28, alignment: .trailing)
      }
      Text(entry.name)
        // The leader gets the (otherwise unused) heavier completion style so
        // the eye lands on the winner first.
        .textStyle(isWinner ? Typography.statusComplete : Typography.bodyBubble)
        .strikethrough(entry.isEliminated)
        .foregroundStyle(nameColor(entry, isWinner: isWinner))
      Spacer(minLength: Spacing.xs)
      valueText(entry)
      statusDot(entry)
    }
    .accessibilityElement(children: .combine)
  }

  @ViewBuilder private var survivalGroups: some View {
    let survivors = model.entries.filter { !$0.isEliminated }
    let eliminated = model.entries.filter(\.isEliminated)
    if !survivors.isEmpty {
      groupHeader(String(localized: "Survived"))
      ForEach(survivors) { survivalRow($0) }
    }
    if !eliminated.isEmpty {
      groupHeader(String(localized: "Eliminated"))
      ForEach(eliminated) { survivalRow($0) }
    }
  }

  private func survivalRow(_ entry: Entry) -> some View {
    HStack(spacing: Spacing.xs) {
      Text(entry.name)
        .textStyle(Typography.bodyBubble)
        .strikethrough(entry.isEliminated)
        .foregroundStyle(entry.isEliminated ? Color.muted : Color.ink)
      Spacer(minLength: Spacing.xs)
      valueText(entry)
      statusDot(entry)
    }
    .accessibilityElement(children: .combine)
  }

  private func groupHeader(_ text: String) -> some View {
    Text(text)
      .textStyle(Typography.captionName)
      .foregroundStyle(Color.muted)
      .padding(.top, Spacing.xxs)
  }

  @ViewBuilder private func valueText(_ entry: Entry) -> some View {
    if let value = entry.primaryValue, entry.valueKind != .none {
      Text(formattedValue(value, kind: entry.valueKind))
        .textStyle(Typography.bodyBubble)
        .monospacedDigit()
        .foregroundStyle(entry.isEliminated ? Color.muted : Color.inkSecondary)
    }
  }

  private func statusDot(_ entry: Entry) -> some View {
    Image(systemName: entry.isEliminated ? "xmark.circle.fill" : "circle.fill")
      .font(.caption)
      .foregroundStyle(entry.isEliminated ? Color.inkSecondary : Color.moss)
      .accessibilityHidden(true)
  }

  private func nameColor(_ entry: Entry, isWinner: Bool) -> Color {
    if entry.isEliminated { return Color.muted }
    return isWinner ? Color.mossInk : Color.ink
  }

  private func formattedValue(_ value: Int, kind: ValueKind) -> String {
    switch kind {
    case .points: String(format: String(localized: "%lld pts"), value)
    case .votes: String(format: String(localized: "%lld votes"), value)
    case .none: ""
    }
  }

  private var eyebrowSymbol: String {
    switch model.framing {
    case .ranking, .pairing: "trophy"
    case .survival: "flag.checkered"
    }
  }

  private var eyebrowLabel: String {
    switch model.framing {
    case .ranking: String(localized: "Final ranking")
    case .pairing: String(localized: "Final scores")
    case .survival: String(localized: "Outcome")
    }
  }
}

#Preview("Result card — ranking / survival") {
  ScrollView {
    VStack(spacing: 12) {
      if let model = SimulationResultCard.Model(
        scores: ["Alice": 12, "Bob": 8, "Carol": 5],
        eliminated: ["Carol": true], voteResults: [:], eliminationVotes: [:],
        phases: [Phase(type: .scoreCalc, logic: .voteTally)]) {
        SimulationResultCard(model: model, onTap: {})
      }
      if let model = SimulationResultCard.Model(
        scores: ["Alice": 0, "Bob": 0, "Carol": 0],
        eliminated: ["Carol": true], voteResults: ["Carol": 4],
        eliminationVotes: ["Carol": 4],
        phases: [Phase(type: .vote), Phase(type: .eliminate)]) {
        SimulationResultCard(model: model)
      }
    }
    .padding(.horizontal, 20)
    .padding(.vertical, 8)
  }
  .background(Color.screenBackground)
}
