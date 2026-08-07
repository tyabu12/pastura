import SwiftUI

/// Layout tokens for ``PasturaStreamDivider``.
///
/// Extracted from the View so `PasturaStreamDividerTests` can act as a
/// **change-detector tripwire** — see that suite's doc comment for why these
/// values earn one (`.claude/rules/view-testing.md` § "Change-detector
/// tripwire for code-review-gated tokens").
enum PasturaStreamDividerLayout {
  /// Thickness of the hairline rules flanking the centred content.
  static let ruleHeight: CGFloat = 1

  /// Breathing room above and below the divider, separating it from the
  /// chat rows on either side.
  static let verticalPadding: CGFloat = 4
}

/// A full-width "chapter" separator for chat-stream surfaces: a hairline rule,
/// the caller's centred content, and a second hairline rule.
///
/// This is the shared body of what used to be five inline copies of one
/// container: three byte-identical round separators (live simulation, DL-time
/// demo, past results) plus two phase separators differing only in the centred
/// element. That element is now whatever the caller passes — a `Text` round
/// label, a ``PhaseTypeLabel`` badge — and everything *outside* the divider
/// stays at the call site too: the demo's `.id()` / `.transition()`, and its
/// `requiresLLM` gate.
///
/// ⚠️ Two neighbours look like members and are not:
///
/// - `demoPhaseSeparator`'s **code-phase** branch renders a bare
///   ``PhaseTypeLabel`` with no rules at all, so full-width emphasis doesn't
///   land on every phase of a code-phase-heavy scenario (#882).
/// - ``DemoBoundaryRow`` *is* rule–content–rule and *does* sit in the same
///   DL-time chat stream, but its rules take `.frame(maxWidth: .infinity)`, its
///   14pt rhythm carries its own in-source rationale for the +2 over the
///   inter-bubble gap, and it declares `.accessibilityAddTraits(.isHeader)`.
///   Those are its contract, not drift from this one.
struct PasturaStreamDivider<Content: View>: View {
  private let content: Content

  init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }

  var body: some View {
    HStack {
      rule
      content
      rule
    }
    .padding(.vertical, PasturaStreamDividerLayout.verticalPadding)
  }

  private var rule: some View {
    Rectangle()
      .fill(Color.rule)
      .frame(height: PasturaStreamDividerLayout.ruleHeight)
  }
}
