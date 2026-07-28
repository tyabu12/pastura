import SwiftUI
import Testing

@testable import Pastura

/// Pure-logic contract tests for ``PasturaPrimaryButtonStyle``. SwiftUI
/// body rendering is out of scope per ADR-009; these pin the fill /
/// foreground token pair (the WCAG-AA contrast rationale lives in the
/// type doc-comment) and the press-feedback constant.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct PasturaPrimaryButtonStyleTests {

  // The fill MUST be mossDark, not base moss: white-on-mossDark ≈ 4.76:1
  // (AA pass) vs. white-on-moss ≈ 3.0:1 (fail). Pinning the token guards
  // the contrast contract against a "use the accent" regression.
  @Test func fillIsMossDark() {
    #expect(PasturaPrimaryButtonStyle.fill == Color.mossDark)
  }

  @Test func foregroundIsInkOnAccent() {
    #expect(PasturaPrimaryButtonStyle.foreground == Color.inkOnAccent)
  }

  @Test func pressedOpacityIsLessThanOne() {
    #expect(PasturaPrimaryButtonStyle.pressedOpacity < 1.0)
    #expect(PasturaPrimaryButtonStyle.pressedOpacity > 0.0)
  }
}
