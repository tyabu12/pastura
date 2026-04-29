import SwiftUI

// Styling primitives for the Pastura chat-bubble design system component.
//
// These are intentionally **small composable pieces** rather than a single
// wrapper view. The caller retains control over the view-tree structure,
// which matters for `AgentOutputRow` — its `@State` identity is
// load-bearing for #133's streaming stability, and wrapping the whole row
// in a container view risked flushing that state mid-stream (critic
// Axis 2, Critical). Modifiers leave the outer view tree unchanged.
//
// Canonical source: `docs/design/design-system.md` §5.2 (ChatBubble) +
// `docs/design/demo-replay-reference.html` `.b-text` / `.b-inner` rules.
//
// The pieces:
//   - `BubbleShape`        — asymmetric rounded rect (tail 4pt, body 14pt).
//   - `BubbleBackground`   — bubble fill + soft rule stroke + padding.
//   - `ThoughtLeftRule`    — moss-soft 1.5pt left border with 8pt gutter.
//   - `AvatarSlot`         — named-agent-to-SheepAvatar mapping helper.
//   - `View.bubbleBackground()` / `View.thoughtLeftRule()` — convenience.

// MARK: - BubbleShape

/// Asymmetric rounded rectangle used as the chat bubble outline.
///
/// Corner radii match `design-system.md` §4.2: **top-leading 4pt** (the
/// bubble tail corner) + **14pt** for the other three. The tail's presence
/// at top-leading encodes "the speaker is on the left" visually; the
/// remaining 14pt corners soften the shape to match the wool / paper
/// palette.
struct BubbleShape: Shape {

  // Values mirror `Radius.bubbleTail` / `Radius.bubbleBody`
  // (design-system §4.2). Inlined as literals here because `Shape`
  // conformance forces this type nonisolated, while `Radius` inherits
  // the project's MainActor default and can't be referenced from a
  // nonisolated static initializer. `ChatBubbleTests` pins equality
  // against `Radius.*` so the single-source-of-truth invariant still
  // has a guard.
  /// Top-leading (tail) corner radius — mirrors `Radius.bubbleTail` (4pt).
  static let topLeadingRadius: CGFloat = 4
  /// Non-tail corners — mirrors `Radius.bubbleBody` (14pt).
  static let bodyRadius: CGFloat = 14

  func path(in rect: CGRect) -> Path {
    UnevenRoundedRectangle(
      topLeadingRadius: Self.topLeadingRadius,
      bottomLeadingRadius: Self.bodyRadius,
      bottomTrailingRadius: Self.bodyRadius,
      topTrailingRadius: Self.bodyRadius
    ).path(in: rect)
  }
}

// MARK: - BubbleBackground modifier

/// Paints the Pastura chat-bubble background — `bubbleBackground` fill,
/// soft `rule`-tinted stroke, and the §5.2 inner padding (12h / 8v).
///
/// Apply to the primary speech text only. The inner thought sits
/// *outside* the bubble per reference HTML (`.b-text` vs sibling
/// `.b-inner`) and uses ``ThoughtLeftRule`` instead.
struct BubbleBackground: ViewModifier {

  /// Inner horizontal padding — matches `design-system.md` §5.2 /
  /// `.b-text { padding: 8px 12px }` in the reference HTML.
  static let horizontalPadding: CGFloat = 12
  /// Inner vertical padding — same source.
  static let verticalPadding: CGFloat = 8

  func body(content: Content) -> some View {
    content
      .padding(.horizontal, Self.horizontalPadding)
      .padding(.vertical, Self.verticalPadding)
      .background(
        BubbleShape().fill(Color.bubbleBackground)
      )
      .overlay(
        // 1pt soft border tinted from `Color.rule`. Reference HTML uses
        // `rgba(90,90,70,.07)` which is fainter than the raw rule token —
        // dropping to 0.5 opacity approximates that visual weight while
        // keeping the token as the semantic source.
        BubbleShape().stroke(Color.rule.opacity(0.5), lineWidth: 1)
      )
  }
}

// MARK: - ThoughtLeftRule modifier

/// Paints the `moss-soft` 1.5pt left border used for inner-thought
/// reveals, with an 8pt gutter before the text.
///
/// Matches `design-system.md` §2.3 + `.b-inner { border-left: 1.5px
/// solid #d4cba8; padding-left: 8px }` in the reference HTML.
struct ThoughtLeftRule: ViewModifier {

  /// Left-rule line width. Reference HTML uses 1.5px; SwiftUI renders it
  /// at device scale without rounding on @2x/@3x displays.
  static let ruleWidth: CGFloat = 1.5
  /// Gap between the rule and the first glyph.
  static let textLeading: CGFloat = 8

  func body(content: Content) -> some View {
    content
      .padding(.leading, Self.textLeading)
      .overlay(alignment: .leading) {
        // Overlay (not HStack) so the rule stretches to the natural text
        // height instead of forcing the caller into a two-column layout.
        Rectangle()
          .fill(Color.mossSoft)
          .frame(width: Self.ruleWidth)
      }
  }
}

// MARK: - AvatarSlot

/// A 48pt (default) sheep avatar derived from the agent's name and
/// (preferably) their position in the scenario's agent list.
///
/// Maps via ``SheepAvatar/Character/forAgent(_:position:)`` — when
/// `position` is supplied, distinct colors are guaranteed up to the
/// 4-character palette (pigeonhole); otherwise falls back to the
/// canonical-name direct match + UTF-8 byte-sum hash.
///
/// Use at the leading edge of a chat row (`HStack(alignment: .top,
/// spacing: ChatBubbleLayout.avatarTextGap)`) before the bubble column.
struct AvatarSlot: View {

  /// The speaker's display name. Resolved to a character once per
  /// render; lookup is O(name length) and cheap enough for per-row use.
  let agentName: String

  /// Agent's zero-based index in the scenario's agent list. When
  /// supplied, takes priority over the name-based lookup so that
  /// scenarios with ≤4 agents always get distinct avatar colors.
  /// Defaults to `nil` for call sites that don't have scenario
  /// context handy (previews, legacy paths).
  var position: Int?

  /// Avatar diameter in points. Defaults to the §5.2 canonical 48pt.
  var size: CGFloat = ChatBubbleLayout.avatarSize

  var body: some View {
    SheepAvatar(
      character: SheepAvatar.Character.forAgent(agentName, position: position),
      size: size)
  }
}

// MARK: - Layout constants

/// Shared layout values for composing chat rows. Exposed as a namespace
/// (rather than spreading constants across individual primitives) so
/// consumers + tests reference a single authoritative source.
///
/// `nonisolated` because these constants are read from `@Sendable`
/// closures (e.g. `.alignmentGuide(.top)` in `AgentOutputRow`) under
/// Swift 6's stricter inference; the namespace holds only pure
/// `CGFloat` values, so the type-level marker is safe and prevents
/// future call sites from re-tripping the same warning.
nonisolated enum ChatBubbleLayout {
  /// Avatar diameter — `design-system.md` §5.2. Bumped from 42pt to
  /// 48pt in #171 so the sheep silhouette reads more clearly on
  /// ~390pt iPhone widths. Both docs (`design-system.md` §5.2 +
  /// `demo-replay-reference.html` `.ava`) carry the updated value.
  static let avatarSize: CGFloat = 48
  /// Horizontal gap between avatar column and bubble column — matches
  /// reference HTML `.bubble { gap: 10px }`.
  static let avatarTextGap: CGFloat = 10
  /// Vertical gap between stacked bubbles. Tightened project-wide
  /// from the original 14pt (which still appears in the reference
  /// HTML at `docs/design/demo-replay-reference.html` `.stream { gap: 14px }`)
  /// to 8pt in #273 PR 2 so Sim/Results — which surface long
  /// simulation logs — fit more turns per viewport. Demo's loop also
  /// benefits since its ~3 visible turns no longer need the wider
  /// pacing. Consumers using `LazyVStack(spacing:)` should pass this
  /// value rather than a literal so a future re-tuning flows through
  /// all three chat-stream surfaces in one place. Pinned by
  /// `ChatBubbleTests` and `ModelDownloadHostViewTests+Layout`.
  static let bubbleSpacing: CGFloat = 8
}

// MARK: - View conveniences

extension View {

  /// Paints the chat-bubble background + stroke + inner padding.
  /// Apply to the primary speech `Text`; pairs with ``thoughtLeftRule``
  /// on the sibling thought view.
  func bubbleBackground() -> some View {
    modifier(BubbleBackground())
  }

  /// Paints the moss-soft left rule + 8pt gutter used for inner-thought
  /// reveals. Apply to the thought `Text` directly.
  func thoughtLeftRule() -> some View {
    modifier(ThoughtLeftRule())
  }
}
