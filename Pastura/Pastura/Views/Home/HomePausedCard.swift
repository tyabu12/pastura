import SwiftUI

/// The "resume" card for the most-recent paused run (ADR-016 P2 layout, P3
/// resume). Mirrors the d3 layout — name / sheep · rounds / description /
/// progress + Resume. A nil `rounds` hides the progress line (orphaned /
/// name-only metadata).
///
/// **P3 (#667)**: the Resume button pushes ``Route/resumeSimulation`` onto the
/// current tab's stack (the Home tab — `@Environment(AppRouter.self)` resolves
/// to the tab the card lives in, per `.claude/rules/navigation.md`).
struct HomePausedCard: View {
  let summary: PausedScenarioSummary
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Environment(AppRouter.self) private var router

  /// Pure mapping from the card's summary to its resume destination, extracted
  /// so the dispatch is unit-testable without a live `AppRouter`. Identity is
  /// the paused run's id; the name rides along as an identity-neutral
  /// `RouteHint` for the nav title (ADR-008).
  static func resumeRoute(for summary: PausedScenarioSummary) -> Route {
    .resumeSimulation(simulationId: summary.runId, initialName: .init(summary.name))
  }

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
      // Use the design-system primary style (mossDark + white label, AA pass),
      // NOT raw `.borderedProminent`: on iOS 26 the latter opts into the Liquid
      // Glass capsule, which renders the `play.fill` glyph into the fill so it
      // vanishes (design-system §5.8 / PasturaPrimaryButtonStyle rationale).
      // The explicit white `foregroundStyle` on the label restores the icon.
      Button {
        router.push(Self.resumeRoute(for: summary))
      } label: {
        Label(String(localized: "Resume"), systemImage: "play.fill")
      }
      .buttonStyle(PasturaPrimaryButtonStyle())
    }
  }
}
