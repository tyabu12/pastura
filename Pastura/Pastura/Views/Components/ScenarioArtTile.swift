import SwiftUI

/// Leading art tile for a ``GalleryCatalogRow`` — a moss-tinted rounded square
/// holding a small cluster of ``SheepAvatar`` heads that hints at the
/// scenario's agent count. Decorative chrome for the さがす (Browse) catalog-card
/// layout (tab-identity redesign PR2, #777); the row's title and description
/// carry the actual identity, so the tile is hidden from VoiceOver.
///
/// When `agentCount` is `nil` or non-positive (older gallery feed / parse
/// failure), the tile renders **empty** rather than fabricating a cluster —
/// mirroring `HomeScenarioRowFormat`'s "hide the sheep when the count is
/// unknown" convention, so the catalog never invents agent data the rest of
/// the app treats as absent. The clamp/empty logic lives in
/// ``GalleryCatalogRowFormat/clusterSheepCount(agentCount:)`` so it is
/// unit-testable without rendering.
struct ScenarioArtTile: View {
  /// Number of agents the scenario runs, or `nil` / non-positive when unknown.
  let agentCount: Int?

  var body: some View {
    let shape = RoundedRectangle(
      cornerRadius: GalleryCatalogMetrics.artTileCornerRadius, style: .continuous)
    return
      shape
      // Inline moss wash (lookbook --moss-wash, rgba(138,154,108,.10)) — no
      // dedicated token per the PR2 "no new design token" constraint.
      .fill(Color.moss.opacity(0.10))
      .overlay(
        shape.strokeBorder(Color.mossSoft, lineWidth: GalleryCatalogMetrics.artTileBorderWidth)
      )
      .frame(width: GalleryCatalogMetrics.artTileSize, height: GalleryCatalogMetrics.artTileSize)
      .overlay(cluster)
      // Decorative: SheepAvatar is already a11y-hidden, and the row's
      // title / description announce identity.
      .accessibilityHidden(true)
  }

  /// A 2-column grid of up to ``GalleryCatalogMetrics/maxClusterSheep`` sheep,
  /// sized by `agentCount` (sheep shrink as the count grows so 5–6 fit the
  /// fixed tile). Empty when the count is unknown / non-positive.
  @ViewBuilder private var cluster: some View {
    let count = GalleryCatalogRowFormat.clusterSheepCount(agentCount: agentCount)
    if count > 0 {
      let sheepSize = GalleryCatalogMetrics.clusterSheepSize(forCount: count)
      VStack(spacing: GalleryCatalogMetrics.artClusterSpacing) {
        ForEach(Array(clusterRows(count: count).enumerated()), id: \.offset) { _, row in
          HStack(spacing: GalleryCatalogMetrics.artClusterSpacing) {
            ForEach(row, id: \.self) { index in
              SheepAvatar(
                character: .forAgent("", position: index),
                size: sheepSize)
            }
          }
        }
      }
    }
  }

  /// Chunk `0..<count` into rows of 2 (matches the lookbook 2-column grid:
  /// 3 sheep → `[0, 1]`, `[2]`).
  private func clusterRows(count: Int) -> [[Int]] {
    stride(from: 0, to: count, by: 2).map { start in
      Array(start..<min(start + 2, count))
    }
  }
}
