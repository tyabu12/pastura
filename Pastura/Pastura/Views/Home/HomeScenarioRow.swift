import SwiftUI

/// One row in the Home scenario list (ADR-016 D3): name (+ trailing preset /
/// gallery-update badge) / sheep · rounds meta line / 2-line description /
/// estimated-inference caption, plus a trailing chevron. Wraps a value-based
/// `NavigationLink` to the scenario detail. Rendered inside the Home
/// ``PasturaCard`` (ScrollView host, like the other browse screens — Shared
/// Scenarios / Past Results / Settings), so it supplies its own chevron + row
/// padding + `.buttonStyle(.plain)` rather than relying on a `List` cell's
/// disclosure chrome. The inner label is the shared ``ScenarioSummaryRow``, so
/// Home and Shared Scenarios stay visually aligned.
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
      HStack(spacing: 10) {
        ScenarioSummaryRow(model: model)
        Spacer(minLength: 8)
        // Manual disclosure chevron — the ScrollView/`PasturaCard` host has no
        // List-cell chrome to supply one (matches Shared Scenarios' galleryRow).
        Image(systemName: "chevron.forward")
          .font(.footnote.weight(.semibold))
          .foregroundStyle(Color.muted)
          .accessibilityHidden(true)
      }
      .padding(.horizontal, 17)
      .padding(.vertical, 12)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("home.scenarioListCell.\(scenario.id)")
  }

  private var model: ScenarioSummaryRow.Model {
    ScenarioSummaryRow.Model(
      title: scenario.name,
      badge: badge,
      agentCount: metadata?.agentCount,
      rounds: metadata?.rounds,
      description: metadata?.description,
      descriptionLineLimit: HomeScenarioRowFormat.descriptionLineLimit(
        isAccessibilitySize: dynamicTypeSize.isAccessibilitySize),
      // No category for local scenarios (gallery-only) — the caption shows the
      // estimated inference count alone (leading nil ⇒ no dangling separator).
      captionTrailing: metadata?.estimatedInferences.map {
        String(format: String(localized: "~%lld inferences"), $0)
      }
    )
  }

  /// Update wins over Preset — but a preset (bundled, never gallery-installed)
  /// never carries a gallery update, so in practice they are exclusive.
  private var badge: ScenarioBadge? {
    if hasGalleryUpdate { return .update }
    if scenario.isPreset { return .preset }
    return nil
  }
}
