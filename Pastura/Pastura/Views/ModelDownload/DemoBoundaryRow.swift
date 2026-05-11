import SwiftUI

/// Demo-boundary marker row inserted between bundled demos in the
/// DL-time chat stream (#208). Sits between the last bubble of the
/// just-finished demo and the first bubble of the next one when the
/// `ReplayViewModel` rotates mid-cycle.
///
/// Visual contract — `docs/specs/demo-replay-ui.md` §"Demo boundary
/// marker":
/// - thin horizontal divider on each side of the caption
/// - caption "Next demo: <scenarioName>" using the same name-label
///   typography as `AgentOutputRow`'s agent-name slot
///   (`Typography.captionName` + `Color.inkSecondary`)
/// - `.accessibilityAddTraits(.isHeader)` so VoiceOver reads the row
///   as a section break, mirroring `GameHeader.titleRow`'s a11y
///   treatment
///
/// Loop wrap-around (last source → source 0) does NOT insert a marker
/// — `ReplayViewModel.advanceAfterSource(_:)` wipes `chatItems`
/// instead, and the full visual reset is itself the new-cycle signal
/// (see the spec's wrap rationale).
struct DemoBoundaryRow: View {
  let scenarioName: String

  /// Localized "Next demo: %@" caption. Uses the canonical
  /// `String(format: String(localized:))` pattern (memory entry
  /// `reference_pastura_localized_format_pattern.md`) — direct Swift
  /// 5.7+ interpolation into `String(localized:)` is not the project
  /// idiom.
  private var caption: String {
    String(format: String(localized: "Next demo: %@"), scenarioName)
  }

  var body: some View {
    HStack(spacing: Spacing.xs) {
      divider
      Text(caption)
        .textStyle(Typography.captionName)
        .foregroundStyle(Color.inkSecondary)
        .fixedSize()
      divider
    }
    // ~16pt vertical breathing room each side. Spacing.m (14) is the
    // closest design-system rhythm token; the literal +2 keeps the
    // marker visually distinct from the 8pt inter-bubble gap.
    .padding(.vertical, Spacing.m)
    .accessibilityElement(children: .combine)
    .accessibilityAddTraits(.isHeader)
  }

  private var divider: some View {
    Rectangle()
      .fill(Color.rule)
      .frame(height: 1)
      .frame(maxWidth: .infinity)
  }
}

#Preview("Demo boundary row") {
  VStack {
    DemoBoundaryRow(scenarioName: "ワードウルフ")
    DemoBoundaryRow(scenarioName: "Prisoner's Dilemma")
  }
  .padding()
  .background(Color.screenBackground)
}
