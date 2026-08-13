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

  /// Capsule fill: the §2.6-shaped `mossSoft` on a hit, the neutral card
  /// surface on a miss.
  var fillToken: Color {
    isHit ? Color.mossSoft : Color.bubbleBackground
  }

  /// Icon + primary label foreground.
  ///
  /// The hit arm takes `mossInk` for the opaque `mossSoft` capsule — the §2.6
  /// `<family>Soft` + `<family>Ink` pairing, 6.537 light / 6.505 dark (#1407,
  /// derivation in `ContradictionBadge`).
  ///
  /// The miss arm reads `inkSecondary` on `bubbleBackground` at 6.934 / 5.975,
  /// replacing `muted`'s 3.475 / 3.021 — sub-AA in *both* appearances (#1427).
  /// `metaBaseL3` would also clear the bar (8.577 / 8.161) and is what
  /// design-system §8 names for must-read meta info, but it is rejected here on
  /// **hierarchy**: at 8.6 the failure state would out-shout the hit arm's 6.5,
  /// and ADR-028 records that a supporting element must not become the loudest
  /// thing in the row. `inkSecondary` lands at parity instead.
  var labelToken: Color {
    isHit ? Color.mossInk : Color.inkSecondary
  }

  /// Streak sub-label foreground. Only rendered on the hit arm, so the ground is
  /// always the opaque `mossSoft` capsule — which makes this the same §2.6
  /// pairing as ``labelToken``'s hit arm, at 6.537 light / 6.505 dark. Replaces
  /// `muted`, which measured 2.136 / 2.413 there — the worst `muted` instance in
  /// the app (#1427).
  ///
  /// **Two quieter candidates were rejected on measurement, not taste.**
  /// `inkSecondary` does not rescue this ground (4.262 light, though it *does*
  /// pass at 4.772 in dark — the rejection is light-only). `metaBaseL3` clears it
  /// at 5.272 / 6.518 and would have preserved colour subordination, but it is a
  /// §2.4 DL-progress ladder rung: ADR-028 § "Three narrower rejections" refuses
  /// borrowing one ("borrowing it would couple two families"), and
  /// `DesignTokens+ExtendedPalette.swift` minted `headerMetaInk` at the *same
  /// hex* rather than collapse the two. §8's binding requirement is the ratio;
  /// the family that owns the ground supplies the token.
  ///
  /// **Accepted cost:** this is the same token as the hit label, so subordination
  /// to "Correct!" rides on weight (`.medium` vs `.semibold`), not colour. Gated
  /// on ADR-028 gate 4 device QA in both appearances.
  var streakToken: Color {
    Color.mossInk
  }
}
