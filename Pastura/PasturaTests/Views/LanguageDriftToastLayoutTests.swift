import SwiftUI
import Testing

@testable import Pastura

/// Change-detector tripwire for the `.languageMismatch` drift toast's
/// layout + timing tokens (``LanguageDriftToastLayout``).
///
/// These assertions mirror the source-of-truth constants **by design**.
/// The toast's rendered appearance is code-review-gated only (ADR-009
/// decision 3 — frame / animation-timing bugs are out of scope for
/// automated tests; the DEBUG-only manual trigger was removed in #455).
/// A failure here does NOT mean a bug was found: it means a
/// code-review-gated visual / timing token drifted, and the editor must
/// confirm the change passed code review before updating the expected
/// value. See issue #456 / ADR-009 § Amendment 2026-06-23.
@Suite("LanguageDriftToastLayout", .timeLimit(.minutes(1)))
@MainActor
struct LanguageDriftToastLayoutTests {

  @Test func anchorsToTopOverChatStream() {
    // The toast sits over the chat-stream area, NOT inside GameHeader's
    // frosted strip — `.top` is the load-bearing anchor.
    #expect(LanguageDriftToastLayout.overlayAlignment == .top)
  }

  @Test func autoDismissesAfterFourSeconds() {
    #expect(LanguageDriftToastLayout.autoDismissSeconds == 4)
  }

  @Test func capsuleContentPaddingUnchanged() {
    #expect(LanguageDriftToastLayout.contentHorizontalPadding == 12)
    #expect(LanguageDriftToastLayout.contentVerticalPadding == 8)
  }

  @Test func outerInsetsUnchanged() {
    #expect(LanguageDriftToastLayout.topInset == 8)
    #expect(LanguageDriftToastLayout.edgeHorizontalPadding == 16)
  }
}
