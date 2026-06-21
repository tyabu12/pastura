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
    #expect(PasturaCardMetrics.borderWidth == 0.5)
  }

  // Category chips (SharedScenarios filter capsules) reuse a 1pt border that is
  // independent of the card hairline — pin it so the borderWidth 1→0.5 thinning
  // can't silently drag the chip stroke down with it.
  @Test func chipBorderStaysOnePoint() {
    #expect(PasturaCardMetrics.chipBorderWidth == 1)
  }

  // Outer margin + inter-card spacing are shared across every browse screen's
  // ScrollView host so they align — pin them positive so a refactor can't
  // silently zero them and collapse the rhythm. The full-bleed zero-override
  // lives on ``PasturaSectionStyle``, NOT on these shared constants.
  @Test func layoutSpacingIsPositive() {
    #expect(PasturaCardMetrics.horizontalMargin > 0)
    #expect(PasturaCardMetrics.interCardSpacing > 0)
  }

  // The full-bleed (.grouped) style zeroes the outer margin and corner radius
  // to reach both screen edges as a squared-off band; .insetGrouped keeps the
  // shared constants. Pinning the mapping protects the detail-screen invariant
  // (detail screens stay .insetGrouped) from an accidental flip.
  @Test func groupedStyleIsFullBleed() {
    #expect(PasturaSectionStyle.grouped.horizontalMargin == 0)
    #expect(PasturaSectionStyle.grouped.cornerRadius == 0)
  }

  @Test func insetGroupedStyleMatchesSharedConstants() {
    #expect(
      PasturaSectionStyle.insetGrouped.horizontalMargin == PasturaCardMetrics.horizontalMargin)
    #expect(PasturaSectionStyle.insetGrouped.cornerRadius == PasturaCardMetrics.cornerRadius)
  }
}
