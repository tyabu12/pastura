import SwiftUI
import Testing

@testable import Pastura

/// Change-detector tripwire for ``PasturaStreamDividerLayout``.
///
/// These assertions mirror the source-of-truth constants **by design**.
///
/// `view-testing.md`'s tripwire rule is written for a surface with "no manual
/// trigger to *see* it", and this divider fails that reading — it renders on
/// every simulation run. The argument for guarding it anyway is **drift
/// magnitude, not invisibility**: 1pt→2pt on the rule, or 4pt→6pt on the
/// padding, is not something casual QA notices on any one screen, yet since
/// the component was extracted a single edit re-spaces every chat-stream
/// chapter break in the app at once — live simulation, DL-time demo, past
/// results, and the gallery highlight excerpt. ADR-009 rules out the snapshot
/// test that would otherwise catch it, so nothing else would.
///
/// A failure here does NOT mean a bug was found: it means a code-review-gated
/// visual token changed, and the editor must confirm that change passed code
/// review before updating the expected value.
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
