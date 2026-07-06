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
      Text(label)
        .font(.caption.weight(.semibold))
    }
    .foregroundStyle(Color.mossDark)
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
