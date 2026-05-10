import SwiftUI
import Testing

@testable import Pastura

/// Pure-logic contract tests for ``PasturaBackButton`` and
/// ``PasturaToolbarButtonStyle``. SwiftUI body rendering is out of scope
/// per ADR-009 (no ViewInspector / snapshot testing); these tests pin the
/// extracted helpers (icon name, color tokens, accessibility label,
/// variant → color mapping) so the visual contract has CI coverage.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct PasturaBackButtonTests {

  // MARK: - PasturaBackButton.iconName

  @Test func iconNameIsChevronBackward() {
    #expect(PasturaBackButton.iconName == "chevron.backward")
  }

  // MARK: - PasturaBackButton.tint

  @Test func tintIsInkPrimary() {
    #expect(PasturaBackButton.tint == Color.ink)
  }

  // MARK: - PasturaBackButton.accessibilityLabel

  @Test func accessibilityLabelIsNonEmpty() {
    #expect(!PasturaBackButton.accessibilityLabel.isEmpty)
  }

  // The label is intentionally chevron-only ("Back") — system parity that
  // includes the upstream view title (e.g. "Back, Pastura") is dropped per
  // the design choice in #342. `.claude/rules/navigation.md` QA scenario 2
  // documents this regression as accepted.
  @Test func accessibilityLabelContainsBack() {
    #expect(PasturaBackButton.accessibilityLabel.contains("Back"))
  }
}

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct PasturaToolbarButtonStyleVariantTests {

  // MARK: - foreground(for:)

  @Test func primaryVariantUsesMossDark() {
    #expect(PasturaToolbarButtonStyle.foreground(for: .primary) == Color.mossDark)
  }

  @Test func destructiveVariantUsesDangerInk() {
    #expect(PasturaToolbarButtonStyle.foreground(for: .destructive) == Color.dangerInk)
  }

  @Test func secondaryVariantUsesInk() {
    #expect(PasturaToolbarButtonStyle.foreground(for: .secondary) == Color.ink)
  }

  // MARK: - pressedOpacity

  /// Pressed opacity reduction is a pure visual constant — pinning it
  /// catches accidental "no feedback" regressions where someone removes
  /// the press indication during a refactor.
  @Test func pressedOpacityIsLessThanOne() {
    #expect(PasturaToolbarButtonStyle.pressedOpacity < 1.0)
    #expect(PasturaToolbarButtonStyle.pressedOpacity > 0.0)
  }
}
