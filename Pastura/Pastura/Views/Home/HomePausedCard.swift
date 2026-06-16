import SwiftUI

/// The "resume" card for the most-recent paused run (ADR-016 P2). Mirrors the
/// d3 layout — name / sheep · rounds / description / progress + Resume.
///
/// **Display-only in P2**: the Resume button is `.disabled(true)` because the
/// run rehydration it needs lands in P3. A nil `rounds` hides the progress
/// line (orphaned / name-only metadata).
struct HomePausedCard: View {
  let summary: PausedScenarioSummary
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  var body: some View {
    PasturaCard {
      VStack(alignment: .leading, spacing: 11) {
        Text(summary.name)
          .font(.headline)
          .foregroundStyle(Color.ink)
        if HomeScenarioRowFormat.showsMetaLine(
          agentCount: summary.agentCount, rounds: summary.rounds) {
          HomeScenarioMetaLine(agentCount: summary.agentCount, rounds: summary.rounds)
        }
        if let description = summary.description, !description.isEmpty {
          Text(description)
            .font(.subheadline)
            .foregroundStyle(Color.inkSecondary)
            .lineLimit(
              HomeScenarioRowFormat.descriptionLineLimit(
                isAccessibilitySize: dynamicTypeSize.isAccessibilitySize)
            )
            .truncationMode(.tail)
        }
        Divider().overlay(Color.rule)
        footer
      }
      .padding(16)
    }
  }

  private var footer: some View {
    HStack {
      if let progress = HomeScenarioRowFormat.pausedProgressLabel(
        currentRound: summary.currentRound, totalRounds: summary.rounds) {
        Text(progress)
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(Color.inkSecondary)
      }
      Spacer()
      // P2 ships the card display-only; resume rehydration (DB → live run) is
      // P3, so the action is disabled rather than wired to a half-built path
      // (ADR-016 §4).
      Button {
      } label: {
        Label(String(localized: "Resume"), systemImage: "play.fill")
      }
      .buttonStyle(.borderedProminent)
      .disabled(true)
    }
  }
}
