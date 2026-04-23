import SwiftUI

/// Displays a phase type as a moss / ink-secondary capsule badge.
///
/// Used inline within an `AgentOutputRow` name row and standalone as a
/// `phaseStarted` log entry in `SimulationView`. The capsule shape + tag
/// typography carries the "this is a phase marker" semantic; color
/// distinguishes LLM-driven phases (moss, the only brand accent) from
/// code-driven phases (ink-secondary, muted neutral).
struct PhaseTypeLabel: View {
  let phaseType: PhaseType

  var body: some View {
    Text(phaseType.rawValue)
      .textStyle(Typography.tagPhase)
      .padding(.horizontal, 8)
      .padding(.vertical, 3)
      // Capsule fill at 15% opacity is load-bearing: without it the
      // label reads as inline text and loses its "badge" affordance
      // (critic Axis 5). Keep the capsule even if the tint palette
      // shifts further.
      .background(badgeColor.opacity(0.15), in: Capsule())
      .foregroundStyle(badgeColor)
  }

  /// LLM-driven phases get the moss brand accent; code-driven phases get
  /// the neutral ink-secondary so the two read as a clear pair without
  /// inventing a second accent hue (design-system §1 bans saturated
  /// colors; only moss is enumerated as an accent in §2.3).
  private var badgeColor: Color {
    if phaseType.requiresLLM {
      Color.moss
    } else {
      Color.inkSecondary
    }
  }
}
