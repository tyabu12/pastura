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
      .background(badgeFill.opacity(0.15), in: Capsule())
      .foregroundStyle(badgeText)
  }

  /// Text tint. §2.3 reserves `moss-dark` for accent text (アクセント
  /// リンク・ステータスラベル) — the readable foreground belongs there,
  /// not on `moss` (which is enumerated for fills / borders).
  /// Code-driven phases stay on `ink-secondary` (neutral pair).
  private var badgeText: Color {
    if phaseType.requiresLLM {
      Color.mossDark
    } else {
      Color.inkSecondary
    }
  }

  /// Capsule fill (rendered at 15% opacity). LLM phases use the lighter
  /// `moss` so the wash reads as a soft tint; if we used `moss-dark`
  /// here too, the 0.15 wash would skew olive-brown and clash with the
  /// readable text on top. Code phases reuse their text color since
  /// `ink-secondary` at 15% lands at a similar neutral wash.
  private var badgeFill: Color {
    if phaseType.requiresLLM {
      Color.moss
    } else {
      Color.inkSecondary
    }
  }
}
