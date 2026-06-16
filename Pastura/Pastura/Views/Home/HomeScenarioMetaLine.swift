import SwiftUI

/// Shared meta line for the Home scenario row and resume card — one sheep
/// avatar per agent (clamped via ``HomeScenarioRowFormat/maxRowSheep``)
/// followed by the round count.
///
/// The sheep are decorative (``SheepAvatar`` is `.accessibilityHidden`); the
/// true agent count is surfaced to VoiceOver through the group's `%lld agents`
/// label so the visual clamp never hides it.
struct HomeScenarioMetaLine: View {
  let agentCount: Int?
  let rounds: Int?

  var body: some View {
    let sheepCount = HomeScenarioRowFormat.rowSheepCount(agentCount: agentCount)
    HStack(spacing: 7) {
      if sheepCount > 0 {
        HStack(spacing: 2) {
          ForEach(0..<sheepCount, id: \.self) { index in
            SheepAvatar(character: .forAgent("", position: index), size: SheepAvatar.rowSize)
          }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
          String(format: String(localized: "%lld agents"), agentCount ?? 0))
      }
      if let roundsLabel = HomeScenarioRowFormat.roundsLabel(rounds: rounds) {
        if sheepCount > 0 {
          Text(verbatim: "·")
            .font(.caption2)
            .foregroundStyle(Color.muted)
        }
        Text(roundsLabel)
          .font(.caption)
          .foregroundStyle(Color.muted)
      }
    }
  }
}
