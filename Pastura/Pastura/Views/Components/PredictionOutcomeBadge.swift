import SwiftUI

/// Compact hit/miss badge for a viewer prediction (#915).
///
/// Shows the consecutive-hit streak when `streak >= 2` on a hit — the immediate
/// end-of-run card passes it (the reward moment); the Past Results list omits it
/// (`streak == nil`) for a quieter row.
///
/// Colours live in the accessors below rather than inline in `body`, so
/// ``PredictionOutcomeBadgeTokenTests`` can pin which token each role reads
/// (`.claude/rules/view-testing.md` § "Change-detector tripwire"). Keep `body`
/// free of `Color.` references — a colour decided in both places can drift in
/// one of them while the pin stays green.
struct PredictionOutcomeBadge: View {
  let isHit: Bool
  var streak: Int?

  var body: some View {
    HStack(spacing: 5) {
      Image(systemName: isHit ? "target" : "xmark")
        .font(.caption2.weight(.bold))
      Text(isHit ? String(localized: "Correct!") : String(localized: "Missed"))
        .font(.caption.weight(.semibold))
      if isHit, let streak, streak >= 2 {
        Text(String(format: String(localized: "%lld in a row"), streak))
          .font(.caption.weight(.medium))
          .foregroundStyle(streakToken)
      }
    }
    .foregroundStyle(labelToken)
    .padding(.horizontal, 10)
    .padding(.vertical, 5)
    .background(Capsule().fill(fillToken))
    .accessibilityElement(children: .combine)
  }
}

extension PredictionOutcomeBadge {

  var fillToken: Color {
    isHit ? Color.mossSoft : Color.bubbleBackground
  }

  /// Icon + primary label. Hit: §2.6's `<family>Soft` + `<family>Ink` pairing on
  /// the opaque capsule, 6.537 light / 6.505 dark (#1407). Miss: `inkSecondary`
  /// on `bubbleBackground`, 6.934 / 5.975, replacing `muted`'s sub-AA
  /// 3.475 / 3.021. `metaBaseL3` clears the bar too, but at 8.6 the *failure*
  /// state would out-shout the hit arm — rejection derived in ADR-028
  /// § Amendment 2026-08-13 (#1427).
  var labelToken: Color {
    isHit ? Color.mossInk : Color.inkSecondary
  }

  /// Streak sub-label. Rendered on the hit arm only, so the ground is always the
  /// opaque `mossSoft` capsule and the answer is ``labelToken``'s hit pairing.
  /// The two quieter candidates were refused — `inkSecondary` reaches only 4.262
  /// in light, `metaBaseL3` is a §2.4 rung — ADR-028 § Amendment 2026-08-13.
  ///
  /// **Accepted cost:** same token as the hit label, so subordination to
  /// "Correct!" rides on weight, not colour. Pending ADR-028 gate 4 device QA in
  /// both appearances.
  var streakToken: Color {
    Color.mossInk
  }
}
