import SwiftUI

/// 🃏 declaration/action contradiction badge (#916).
///
/// Two renderings share the one localized phrasing: the compact form
/// (`agent == nil`) decorates the original declaration row retroactively,
/// and the named form is the reveal line appended to the transcript at
/// choose-phase completion — the moment the actions have just been shown.
struct ContradictionBadge: View {
  var agent: String?

  var body: some View {
    HStack(spacing: 5) {
      Text(verbatim: "🃏")
        .font(.caption)
        // Decorative — without this the combined element announces
        // "joker" before the meaningful phrase.
        .accessibilityHidden(true)
      Text(label)
        .font(.caption.weight(.semibold))
    }
    // On an **opaque** `mossSoft` fill the foreground must be `mossInk` — the
    // §2.6 `<family>Soft` + `<family>Ink` pairing the alert families use. The
    // two plausible alternatives both fail the 4.5:1 bar this ~12pt label owes:
    // `mossDark` at 2.911 in light, and `mossOnWash` at 4.292 (that token is
    // scoped to *translucent* washes). Asserted, with both rejections, by
    // `DesignTokensTests+MossSoftGround` (#1407).
    .foregroundStyle(Color.mossInk)
    .padding(.horizontal, 10)
    .padding(.vertical, 5)
    .background(Capsule().fill(Color.mossSoft))
    .accessibilityElement(children: .combine)
  }

  private var label: String {
    if let agent {
      return String(
        format: String(localized: "%@ said one thing, did another"), agent)
    }
    return String(localized: "Said one thing, did another")
  }
}
