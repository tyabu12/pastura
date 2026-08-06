import SwiftUI
import Testing

@testable import Pastura

/// Change-detector tripwire for ``PasturaStreamDividerLayout``.
///
/// These assertions mirror the source-of-truth constants **by design**. The
/// divider's rendered appearance is code-review-gated only (ADR-009 rules out
/// snapshot tests), and since this component was extracted it backs four
/// screens at once — the live simulation, the DL-time demo, past results, and
/// the gallery highlight excerpt. A silent drift in a refactor would therefore
/// re-space every chat-stream chapter break in the app simultaneously, with
/// nothing else to catch it.
///
/// A failure here does NOT mean a bug was found: it means a code-review-gated
/// visual token changed, and the editor must confirm that change passed code
/// review before updating the expected value. See
/// `.claude/rules/view-testing.md` § "Change-detector tripwire for
/// code-review-gated tokens".
@Suite("PasturaStreamDividerLayout", .timeLimit(.minutes(1)))
@MainActor
struct PasturaStreamDividerTests {

  @Test func ruleIsAHairline() {
    // A hairline, not a bar — the divider marks a chapter break without
    // competing with the chat rows it separates.
    #expect(PasturaStreamDividerLayout.ruleHeight == 1)
  }

  @Test func verticalPaddingMatchesTheChatStreamRhythm() {
    // 4pt on each side. Tighter than the 8pt `ChatBubbleLayout.bubbleSpacing`
    // between bubbles, so a chapter break reads as belonging to the stream
    // rather than as a third kind of gap.
    #expect(PasturaStreamDividerLayout.verticalPadding == 4)
  }
}
