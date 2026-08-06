import SwiftUI

/// Layout tokens for ``PasturaStreamDivider``.
///
/// Extracted from the View so `PasturaStreamDividerTests` can act as a
/// **change-detector tripwire** (`.claude/rules/view-testing.md` §
/// "Change-detector tripwire for code-review-gated tokens"). The divider's
/// rendered appearance is code-review-gated only — ADR-009 keeps snapshot
/// tests out — and it now backs four separate screens, so a silent drift here
/// would move the chapter rhythm on all of them at once. A failure is NOT a
/// bug report: it means a code-review-gated token changed, and the editor must
/// confirm that change passed review before updating the expected value.
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
/// This is the shared body of what used to be five byte-identical inline
/// copies — round separators on the live simulation, the DL-time demo and past
/// results, plus phase separators on the first two. The centred element is
/// whatever the caller passes (a `Text` round label, a ``PhaseTypeLabel``
/// badge), and everything *outside* the divider stays at the call site:
/// the demo's `.id()` / `.transition()`, and its `requiresLLM` gate.
///
/// ⚠️ Not every "separator"-named helper is one of these. `demoPhaseSeparator`
/// renders a **bare** ``PhaseTypeLabel`` for code-driven phases — no rules, no
/// flanking — so full-width emphasis doesn't land on every phase of a
/// code-phase-heavy scenario (#882). That branch must not be folded in here.
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
