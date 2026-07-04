import Foundation
import Testing

@testable import Pastura

/// Change-detector for `ViewerPredictionSheet`'s code-review-gated countdown
/// length (#915). A failure here is not a bug — it means the value drifted
/// (typically in an unrelated refactor) and the editor must confirm the change
/// passed review before updating the expected value. This narrows the
/// silent-drift window without rendering the View (ADR-009 / view-testing.md
/// § "Change-detector tripwire").
@Suite(.timeLimit(.minutes(1)))
struct ViewerPredictionSheetLayoutTests {
  @Test func countdownSecondsIsFifteen() {
    #expect(ViewerPredictionSheetLayout.countdownSeconds == 15)
  }
}
