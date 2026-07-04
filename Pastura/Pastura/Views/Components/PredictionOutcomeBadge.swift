import SwiftUI

/// Compact hit/miss badge for a viewer prediction (#915).
///
/// Shows the consecutive-hit streak when `streak >= 2` on a hit — the immediate
/// end-of-run card passes it (the reward moment); the Past Results list omits it
/// (`streak == nil`) for a quieter row.
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
          .foregroundStyle(Color.muted)
      }
    }
    .foregroundStyle(isHit ? Color.mossDark : Color.muted)
    .padding(.horizontal, 10)
    .padding(.vertical, 5)
    .background(
      Capsule().fill(isHit ? Color.mossSoft : Color.bubbleBackground)
    )
    .accessibilityElement(children: .combine)
  }
}
