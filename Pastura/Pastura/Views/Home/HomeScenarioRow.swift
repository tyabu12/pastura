import SwiftUI

/// One row in the Home scenario list (ADR-016 D3): name (+ inline preset /
/// gallery-update badges) / sheep · rounds meta line / 1-line description.
/// Wraps a value-based `NavigationLink` to the scenario detail.
struct HomeScenarioRow: View {
  let scenario: ScenarioRecord
  let metadata: ScenarioRowMetadata?
  var hasGalleryUpdate: Bool = false
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  var body: some View {
    // initialName supplies the scenario name to navigationTitle from the
    // first frame of the push, before ScenarioDetailViewModel finishes
    // loading. Identity-neutral via RouteHint (ADR-008).
    NavigationLink(
      value: Route.scenarioDetail(
        scenarioId: scenario.id,
        initialName: .init(scenario.name)
      )
    ) {
      label
    }
    .accessibilityIdentifier("home.scenarioListCell.\(scenario.id)")
  }

  private var label: some View {
    VStack(alignment: .leading, spacing: 5) {
      HStack(spacing: 6) {
        Text(scenario.name)
          .font(.headline)
          .foregroundStyle(Color.ink)
        // Preset badge moves inline next to the name (d3) rather than its
        // own caption row below.
        if scenario.isPreset {
          Text(String(localized: "Preset"))
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.secondary.opacity(0.15), in: Capsule())
        }
        if hasGalleryUpdate {
          Text(String(localized: "Update"))
            .font(.caption2.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.accentColor.opacity(0.2), in: Capsule())
            .foregroundStyle(Color.accentColor)
        }
      }
      if HomeScenarioRowFormat.showsMetaLine(
        agentCount: metadata?.agentCount, rounds: metadata?.rounds) {
        HomeScenarioMetaLine(agentCount: metadata?.agentCount, rounds: metadata?.rounds)
      }
      if let description = metadata?.description, !description.isEmpty {
        Text(description)
          .font(.subheadline)
          .foregroundStyle(Color.inkSecondary)
          .lineLimit(
            HomeScenarioRowFormat.descriptionLineLimit(
              isAccessibilitySize: dynamicTypeSize.isAccessibilitySize)
          )
          .truncationMode(.tail)
      }
    }
    .padding(.vertical, 4)
  }
}
