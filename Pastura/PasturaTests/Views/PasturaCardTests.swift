import SwiftUI
import Testing

@testable import Pastura

/// Pure-logic contract tests for ``PasturaCard``. SwiftUI body rendering is
/// out of scope per ADR-009; these pin the shared layout metrics so an
/// accidental token/radius swap (or a re-introduced shadow) is caught in CI.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct PasturaCardTests {

  @Test func cornerRadiusIsFourteen() {
    #expect(PasturaCardMetrics.cornerRadius == 14)
  }

  @Test func borderIsHairline() {
    #expect(PasturaCardMetrics.borderWidth == 1)
  }

  // Outer margin + inter-card spacing are shared across every browse screen's
  // ScrollView host so they align — pin them positive so a refactor can't
  // silently zero them and collapse the rhythm.
  @Test func layoutSpacingIsPositive() {
    #expect(PasturaCardMetrics.horizontalMargin > 0)
    #expect(PasturaCardMetrics.interCardSpacing > 0)
  }
}
