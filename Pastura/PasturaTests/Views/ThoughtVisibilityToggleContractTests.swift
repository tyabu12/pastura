import SwiftUI
import Testing

@testable import Pastura

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct ThoughtVisibilityToggleContractTests {

  // MARK: - iconName(for:)

  @Test func iconNameForOnStateIsFilledEye() {
    #expect(ThoughtVisibilityToggle.iconName(for: true) == "eye.fill")
  }

  @Test func iconNameForOffStateIsSlashedEye() {
    #expect(ThoughtVisibilityToggle.iconName(for: false) == "eye.slash")
  }

  // MARK: - tint(for:)

  @Test func tintForOnStateIsMoss() {
    #expect(ThoughtVisibilityToggle.tint(for: true) == Color.moss)
  }

  @Test func tintForOffStateIsInkSecondary() {
    #expect(ThoughtVisibilityToggle.tint(for: false) == Color.inkSecondary)
  }

  // MARK: - accessibilityLabel(for:)

  @Test func accessibilityLabelForOnStateContainsHide() {
    let label = ThoughtVisibilityToggle.accessibilityLabel(for: true)
    #expect(!label.isEmpty)
    #expect(label.contains("Hide"))
  }

  @Test func accessibilityLabelForOffStateContainsShow() {
    let label = ThoughtVisibilityToggle.accessibilityLabel(for: false)
    #expect(!label.isEmpty)
    #expect(label.contains("Show"))
  }

  @Test func accessibilityLabelsForOnAndOffAreDifferent() {
    let onLabel = ThoughtVisibilityToggle.accessibilityLabel(for: true)
    let offLabel = ThoughtVisibilityToggle.accessibilityLabel(for: false)
    #expect(onLabel != offLabel)
  }
}
