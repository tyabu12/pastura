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
///
/// `signature` adds a single glyph badge overhanging the bottom-trailing
/// corner — the scenario's "headline" mechanic (vote / eliminate / …). It is
/// `O(1)` regardless of phase count and hidden when `nil` (older feed without
/// `phases`). The phase→signature mapping lives in
/// ``GalleryCatalogRowFormat/signaturePhase(phases:)`` (#786).
struct ScenarioArtTile: View {
  /// Number of agents the scenario runs, or `nil` / non-positive when unknown.
  let agentCount: Int?

  /// The headline phase to badge, or `nil` to draw no badge.
  let signature: ScenarioSignaturePhase?

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
      // Badge overhangs the corner — kept as the outermost overlay so it is not
      // clipped by the tile's rounded-rect and floats above the cluster.
      .overlay(alignment: .bottomTrailing) { badge }
      // Decorative: SheepAvatar is already a11y-hidden, and the row's
      // title / description announce identity.
      .accessibilityHidden(true)
  }

  /// The signature-phase glyph badge — a white circle with a mossDark SF Symbol,
  /// offset outward so it overhangs the tile's bottom-trailing corner. Hidden
  /// when `signature` is `nil`.
  @ViewBuilder private var badge: some View {
    if let signature {
      Image(systemName: signature.sfSymbolName)
        .font(.system(size: GalleryCatalogMetrics.badgeGlyphSize, weight: .semibold))
        .foregroundStyle(Color.mossDark)
        .frame(
          width: GalleryCatalogMetrics.badgeDiameter, height: GalleryCatalogMetrics.badgeDiameter
        )
        .background(Color.bubbleBackground, in: Circle())
        .overlay(
          Circle().strokeBorder(Color.mossSoft, lineWidth: GalleryCatalogMetrics.badgeBorderWidth)
        )
        .shadow(
          color: PasturaShadows.tight.color.color, radius: PasturaShadows.tight.radius,
          x: PasturaShadows.tight.x, y: PasturaShadows.tight.y
        )
        .offset(x: GalleryCatalogMetrics.badgeOffset, y: GalleryCatalogMetrics.badgeOffset)
    }
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
