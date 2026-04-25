import SwiftUI
import Testing

@testable import Pastura

/// Layout regression guard for `DemoReplayHostView.chatStream()` after
/// the #171 B2 retrofit added avatars + bubble styling to
/// `AgentOutputRow`.
///
/// The demo screen is the first surface every new user sees (DL-time),
/// so visual regressions here are high-blast-radius. These tests pin
/// the layout constants the demo composition relies on — if a future
/// token change or refactor accidentally drifts the bubble spacing,
/// avatar size, or avatar-text gap away from the reference HTML
/// values, one of these asserts fires before CI merges the regression.
///
/// Live render behavior (scrollTo anchors, safeAreaInset positioning,
/// PromoCard non-occlusion) is covered by manual QA per the #171 PR
/// body — those require a SwiftUI host this test target doesn't have.
extension DemoReplayHostViewTests {

  // MARK: - ChatBubbleLayout — reference HTML values

  @Test func demoChatStreamUsesCanonicalBubbleSpacing() {
    // Reference HTML `.stream { gap: 14px }`. The demo screen's
    // `LazyVStack(spacing: ChatBubbleLayout.bubbleSpacing)` must agree
    // — a mismatch would make bubbles visually cramped or loose vs the
    // prototype the design was signed off against.
    #expect(ChatBubbleLayout.bubbleSpacing == 14)
  }

  @Test func demoChatStreamUsesCanonicalAvatarSize() {
    // Design-system §5.2 "[Avatar 48pt]" (bumped from 42pt in #171).
    // AgentOutputRow prepends a 48pt avatar via AvatarSlot — a size
    // change would shift the bubble column leading edge and require
    // re-checking horizontal gutter alignment.
    #expect(ChatBubbleLayout.avatarSize == 48)
  }

  @Test func demoChatStreamUsesCanonicalAvatarTextGap() {
    // Reference HTML `.bubble { gap: 10px }`. AgentOutputRow's
    // HStack uses `ChatBubbleLayout.avatarTextGap` between the avatar
    // and the name/bubble column — gating regression here protects
    // the reference's visual rhythm.
    #expect(ChatBubbleLayout.avatarTextGap == 10)
  }

  // MARK: - Bubble composition — AgentOutputRow defaults

  @Test func demoChatStreamUsesAgentOutputRowWithDefaultShowAvatar() {
    // DemoReplayHostView.chatStream constructs AgentOutputRow *without*
    // an explicit `showAvatar:` argument, relying on the default
    // `showAvatar: true` to render sheep avatars. A future refactor
    // that flips the default or re-orders parameters would silently
    // strip avatars from the demo — this call pins the initializer
    // shape the demo currently depends on.
    let row = AgentOutputRow(
      agent: "Alice",
      output: TurnOutput(fields: ["statement": "hi"]),
      phaseType: .speakAll,
      showAllThoughts: true,
      isLatest: true,
      charsPerSecond: 60
    )
    #expect(row.showAvatar == true)
  }

  @Test func demoChatStreamAvatarForAliceResolvesToAliceCharacter() {
    // The demo-replay YAMLs use the four canonical names. An
    // accidental regression in `SheepAvatar.Character.forAgent`
    // (e.g., reverting the direct-match short-circuit) would silently
    // push "Alice" into the byte-sum fallback bucket and land on the
    // wrong avatar color.
    #expect(SheepAvatar.Character.forAgent("Alice") == .alice)
    #expect(SheepAvatar.Character.forAgent("Bob") == .bob)
    #expect(SheepAvatar.Character.forAgent("Carol") == .carol)
    #expect(SheepAvatar.Character.forAgent("Dave") == .dave)
  }
}
