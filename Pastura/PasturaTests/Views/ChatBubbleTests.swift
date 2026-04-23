import SwiftUI
import Testing

@testable import Pastura

/// Tests for the ChatBubble styling primitives. Verifies the shape /
/// modifier / layout constants encode the canonical values from
/// `docs/design/design-system.md` §4.2 + §5.2 and the reference HTML's
/// `.b-text` / `.b-inner` / `.bubble` rules.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct ChatBubbleTests {

  // MARK: - BubbleShape radii

  @Test func bubbleShapeTopLeadingRadiusMatchesTailToken() {
    // Radius.bubbleTail = 4pt per design-system §4.2. The tail corner
    // is what visually tags the bubble as "speaker on the left".
    #expect(BubbleShape.topLeadingRadius == 4)
    #expect(BubbleShape.topLeadingRadius == Radius.bubbleTail)
  }

  @Test func bubbleShapeBodyRadiusMatchesBubbleBodyToken() {
    // 14pt for the three non-tail corners — design-system §4.2.
    #expect(BubbleShape.bodyRadius == 14)
    #expect(BubbleShape.bodyRadius == Radius.bubbleBody)
  }

  @Test func bubbleShapePathIsNonEmptyInTypicalRect() {
    // Lightweight smoke check: the asymmetric path must actually
    // produce geometry. Catches a future refactor that accidentally
    // swaps in a zero-radius or fully-collapsed shape.
    let shape = BubbleShape()
    let rect = CGRect(x: 0, y: 0, width: 200, height: 44)
    #expect(!shape.path(in: rect).isEmpty)
  }

  // MARK: - BubbleBackground padding

  @Test func bubbleBackgroundInnerPaddingMatchesReferenceHTML() {
    // `.b-text { padding: 8px 12px }` — reference HTML line 104.
    #expect(BubbleBackground.horizontalPadding == 12)
    #expect(BubbleBackground.verticalPadding == 8)
  }

  // MARK: - ThoughtLeftRule dimensions

  @Test func thoughtLeftRuleWidthIsOnePointFivePixels() {
    // Reference HTML `.b-inner { border-left: 1.5px solid ... }`.
    // Design-system §2.3 describes the rule as "moss-soft 左線".
    #expect(ThoughtLeftRule.ruleWidth == 1.5)
  }

  @Test func thoughtLeftRuleTextLeadingMatchesReferenceHTML() {
    // Reference HTML `.b-inner { padding-left: 8px }`.
    #expect(ThoughtLeftRule.textLeading == 8)
  }

  // MARK: - ChatBubbleLayout

  @Test func avatarSizeIsFortyTwoPoints() {
    // Design-system §5.2: "[Avatar 42pt]".
    #expect(ChatBubbleLayout.avatarSize == 42)
  }

  @Test func avatarTextGapMatchesReferenceHTML() {
    // Reference HTML `.bubble { gap: 10px }` — avatar → body column.
    #expect(ChatBubbleLayout.avatarTextGap == 10)
  }

  @Test func bubbleSpacingMatchesReferenceHTML() {
    // Reference HTML `.stream { gap: 14px }` — inter-bubble vertical.
    #expect(ChatBubbleLayout.bubbleSpacing == 14)
  }

  // MARK: - AvatarSlot wiring

  @Test func avatarSlotDefaultsToCanonicalSize() {
    let slot = AvatarSlot(agentName: "Alice")
    #expect(slot.size == ChatBubbleLayout.avatarSize)
  }

  @Test func avatarSlotAcceptsCustomSize() {
    let slot = AvatarSlot(agentName: "Alice", size: 32)
    #expect(slot.size == 32)
  }

  // MARK: - Modifier instantiation (smoke test)

  @Test func bubbleBackgroundModifierCanBeApplied() {
    // Compile-time + runtime smoke check: View extensions resolve and
    // the modifier type is reachable from consumer code.
    _ = Text("hi").bubbleBackground()
  }

  @Test func thoughtLeftRuleModifierCanBeApplied() {
    _ = Text("thought").thoughtLeftRule()
  }
}
