import SwiftUI

// The tap-to-view-persona avatar / name affordances for `AgentOutputRow`,
// split into a sibling extension to keep the main file's struct body under
// swiftlint's `type_body_length` cap. These are pure view helpers — they
// touch none of the file-private reveal-state machine, only the non-private
// `agent`, `agentPosition`, and `onAvatarTap` members — so the split needs no
// visibility widening of the reveal internals. See #942.
extension AgentOutputRow {

  /// The leading avatar column. When ``onAvatarTap`` is set the sheep becomes
  /// a **sighted-only** tap target and stays `.accessibilityHidden` (it is
  /// decorative — VoiceOver reaches the persona sheet through ``nameLabel``,
  /// avoiding `SheepAvatar`'s color-slot label surfacing as a spurious
  /// button). The gesture sits on the leaf `AvatarSlot`, so the row's
  /// `@State` identity is untouched.
  @ViewBuilder var avatarColumn: some View {
    let slot = AvatarSlot(agentName: agent, position: agentPosition)
    if let onAvatarTap {
      slot
        .contentShape(Rectangle())
        .onTapGesture { onAvatarTap(agent) }
        .accessibilityHidden(true)
    } else {
      slot
    }
  }

  /// The agent-name caption. When ``onAvatarTap`` is set it becomes the single
  /// VoiceOver entry point to the persona sheet: the `Text` already announces
  /// the agent's display name, so adding `.isButton` + a default accessibility
  /// action (plus a pointer `.onTapGesture`) makes the name a button without
  /// duplicating the identity onto the hidden avatar. The hint describes the
  /// action, not the target.
  @ViewBuilder var nameLabel: some View {
    let label = Text(agent)
      .textStyle(Typography.captionName)
      .foregroundStyle(Color.inkSecondary)
    if let onAvatarTap {
      label
        .contentShape(Rectangle())
        .onTapGesture { onAvatarTap(agent) }
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(Text(String(localized: "Shows this agent's persona")))
        .accessibilityAction { onAvatarTap(agent) }
    } else {
      label
    }
  }
}
