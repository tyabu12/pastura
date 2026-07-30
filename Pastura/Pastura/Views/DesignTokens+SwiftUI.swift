import SwiftUI

// SwiftUI-facing helpers for the Pastura design system.
//
// Kept separate from `DesignTokens.swift` so the token data sits in one file
// and the SwiftUI bindings (`Color` aliases, `View.textStyle(_:)`) in another
// — eases the future SPM split (tokens module vs UI module).

// MARK: - Color extension (SwiftUI-facing aliases)

extension Color {
  // The 67 aliases sourced from `PasturaDynamicPalette` resolve light/dark
  // against the ambient interface style (§2.9 — ADR-028's original eight, the
  // §2.6/§2.7 slice in #1282, the §2.4 meta presets plus two §2.12 header
  // slots in #1313, the §2.5 character palette in #1319, and the §2.1/§2.3/§2.8
  // remainder plus `inkOnAccent` in slice 4, which closed gate 1). **Exactly one
  // light token is left in pairing scope and it is resolved, not pending**:
  // `headerMetaSubdued`, fixed in both appearances by decision — see
  // `DesignTokens+NightPalette`'s §2.12 MARK. The remaining aliases below are
  // outside that scope entirely: the 67 §2.9 `night*` ones are the dark halves
  // themselves (note `night` alone is §2.10, not one of them — grepping the
  // prefix returns 68), and §2.10 time-of-day / §2.11 chart are decorative
  // reservations that were never candidates for pairing. The app is pinned to
  // light via `Info.plist`'s `UIUserInterfaceStyle`, so no half-dark surface can
  // render while that is true — and after slice 4 that lock waits on ADR-028's
  // gates 4/5 (real-device QA) rather than on any missing value.
  //
  // Need a specific appearance regardless of the device — e.g. an
  // `ImageRenderer` export, which does not inherit the ambient environment?
  // Read `PasturaPalette.<token>.color` directly instead of these aliases.
  // `HighlightShareCard` is the reference consumer. That is the sanctioned
  // explicit-appearance accessor — note the `Color.night*` aliases below now
  // have ZERO consumers (#1319 moved their last one, that same card, to
  // the raw palette); they remain only as defined-ahead-of-need tokens, and are
  // not a second sanctioned route to a fixed appearance.

  // §2.1 Backgrounds
  static let page = PasturaDynamicPalette.page.color
  static let screenBackground = PasturaDynamicPalette.screenBackground.color
  static let bubbleBackground = PasturaDynamicPalette.bubbleBackground.color
  static let whisperBubble = PasturaDynamicPalette.whisperBubble.color
  static let promoBackground = PasturaDynamicPalette.promoBackground.color
  static let promoBorder = PasturaDynamicPalette.promoBorder.color

  // §2.2 Ink
  static let ink = PasturaDynamicPalette.ink.color
  static let inkSecondary = PasturaDynamicPalette.inkSecondary.color
  static let muted = PasturaDynamicPalette.muted.color
  static let rule = PasturaDynamicPalette.rule.color
  static let inkOnAccent = PasturaDynamicPalette.inkOnAccent.color

  // §2.3 Moss
  static let moss = PasturaDynamicPalette.moss.color
  static let mossDark = PasturaDynamicPalette.mossDark.color
  static let mossInk = PasturaDynamicPalette.mossInk.color
  static let mossSoft = PasturaDynamicPalette.mossSoft.color

  // §2.4 Meta L1
  static let metaBaseL1 = PasturaDynamicPalette.metaBaseL1.color
  static let metaStrongL1 = PasturaDynamicPalette.metaStrongL1.color
  static let metaDotOnL1 = PasturaDynamicPalette.metaDotOnL1.color

  // §2.4 Meta L2
  static let metaBaseL2 = PasturaDynamicPalette.metaBaseL2.color
  static let metaStrongL2 = PasturaDynamicPalette.metaStrongL2.color
  static let metaDotOnL2 = PasturaDynamicPalette.metaDotOnL2.color

  // §2.4 Meta L3 (default)
  static let metaBaseL3 = PasturaDynamicPalette.metaBaseL3.color
  static let metaStrongL3 = PasturaDynamicPalette.metaStrongL3.color
  static let metaDotOnL3 = PasturaDynamicPalette.metaDotOnL3.color

  // §2.4 Meta L4
  static let metaBaseL4 = PasturaDynamicPalette.metaBaseL4.color
  static let metaStrongL4 = PasturaDynamicPalette.metaStrongL4.color
  static let metaDotOnL4 = PasturaDynamicPalette.metaDotOnL4.color

  // §2.5 Avatars — paired, and with **no production consumer**. Avatar painting
  // goes through `SheepAvatarPalette`, which reads raw `PasturaPalette` so the
  // `HighlightShareCard` export can pin an appearance (ADR-028 slice 3). Reaching
  // for one of these in a new avatar-adjacent view gets correct in-app behaviour
  // and silently re-opens the export hazard the moment that view is composed
  // into a card — use `SheepAvatarPalette` instead.
  static let avatarBodyAlice = PasturaDynamicPalette.avatarBodyAlice.color
  static let avatarBodyBob = PasturaDynamicPalette.avatarBodyBob.color
  static let avatarBodyCarol = PasturaDynamicPalette.avatarBodyCarol.color
  static let avatarBodyDave = PasturaDynamicPalette.avatarBodyDave.color
  static let avatarFaceAlice = PasturaDynamicPalette.avatarFaceAlice.color
  static let avatarFaceBob = PasturaDynamicPalette.avatarFaceBob.color
  static let avatarFaceCarol = PasturaDynamicPalette.avatarFaceCarol.color
  static let avatarFaceDave = PasturaDynamicPalette.avatarFaceDave.color
  static let avatarHornAlice = PasturaDynamicPalette.avatarHornAlice.color
  static let avatarHornBob = PasturaDynamicPalette.avatarHornBob.color
  static let avatarHornCarol = PasturaDynamicPalette.avatarHornCarol.color
  static let avatarHornDave = PasturaDynamicPalette.avatarHornDave.color
  static let avatarEar = PasturaDynamicPalette.avatarEar.color
  static let avatarEarInner = PasturaDynamicPalette.avatarEarInner.color
  static let avatarNose = PasturaDynamicPalette.avatarNose.color
  static let avatarEye = PasturaDynamicPalette.avatarEye.color
  static let avatarHighlight = PasturaDynamicPalette.avatarHighlight.color

  // §2.6 Alert family
  static let info = PasturaDynamicPalette.info.color
  static let infoSoft = PasturaDynamicPalette.infoSoft.color
  static let infoInk = PasturaDynamicPalette.infoInk.color
  static let success = PasturaDynamicPalette.success.color
  static let successSoft = PasturaDynamicPalette.successSoft.color
  static let successInk = PasturaDynamicPalette.successInk.color
  static let warning = PasturaDynamicPalette.warning.color
  static let warningSoft = PasturaDynamicPalette.warningSoft.color
  static let warningInk = PasturaDynamicPalette.warningInk.color
  static let danger = PasturaDynamicPalette.danger.color
  static let dangerSoft = PasturaDynamicPalette.dangerSoft.color
  static let dangerInk = PasturaDynamicPalette.dangerInk.color

  // §2.7 Interactive states
  static let hover = PasturaDynamicPalette.hover.color
  static let pressed = PasturaDynamicPalette.pressed.color
  static let selected = PasturaDynamicPalette.selected.color
  static let focusRing = PasturaDynamicPalette.focusRing.color
  static let disabledText = PasturaDynamicPalette.disabledText.color
  static let disabledBackground = PasturaDynamicPalette.disabledBackground.color

  // §2.8 Link / Action
  static let link = PasturaDynamicPalette.link.color
  static let linkVisited = PasturaDynamicPalette.linkVisited.color
  static let linkHover = PasturaDynamicPalette.linkHover.color

  // §2.9 Dark mode (night pasture)
  static let nightBackground = PasturaPalette.nightBackground.color
  static let nightBubble = PasturaPalette.nightBubble.color
  static let nightWhisperBubble = PasturaPalette.nightWhisperBubble.color
  static let nightInk = PasturaPalette.nightInk.color
  static let nightInkSecondary = PasturaPalette.nightInkSecondary.color
  static let nightMuted = PasturaPalette.nightMuted.color
  static let nightRule = PasturaPalette.nightRule.color
  static let nightMoss = PasturaPalette.nightMoss.color
  static let nightInfo = PasturaPalette.nightInfo.color
  static let nightInfoSoft = PasturaPalette.nightInfoSoft.color
  static let nightInfoInk = PasturaPalette.nightInfoInk.color
  static let nightSuccess = PasturaPalette.nightSuccess.color
  static let nightSuccessSoft = PasturaPalette.nightSuccessSoft.color
  static let nightSuccessInk = PasturaPalette.nightSuccessInk.color
  static let nightWarning = PasturaPalette.nightWarning.color
  static let nightWarningSoft = PasturaPalette.nightWarningSoft.color
  static let nightWarningInk = PasturaPalette.nightWarningInk.color
  static let nightDanger = PasturaPalette.nightDanger.color
  static let nightDangerSoft = PasturaPalette.nightDangerSoft.color
  static let nightDangerInk = PasturaPalette.nightDangerInk.color
  static let nightHover = PasturaPalette.nightHover.color
  static let nightPressed = PasturaPalette.nightPressed.color
  static let nightSelected = PasturaPalette.nightSelected.color
  static let nightFocusRing = PasturaPalette.nightFocusRing.color
  static let nightDisabledText = PasturaPalette.nightDisabledText.color
  static let nightDisabledBackground = PasturaPalette.nightDisabledBackground.color
  static let nightMetaBaseL1 = PasturaPalette.nightMetaBaseL1.color
  static let nightMetaStrongL1 = PasturaPalette.nightMetaStrongL1.color
  static let nightMetaDotOnL1 = PasturaPalette.nightMetaDotOnL1.color
  static let nightMetaBaseL2 = PasturaPalette.nightMetaBaseL2.color
  static let nightMetaStrongL2 = PasturaPalette.nightMetaStrongL2.color
  static let nightMetaDotOnL2 = PasturaPalette.nightMetaDotOnL2.color
  static let nightMetaBaseL3 = PasturaPalette.nightMetaBaseL3.color
  static let nightMetaStrongL3 = PasturaPalette.nightMetaStrongL3.color
  static let nightMetaDotOnL3 = PasturaPalette.nightMetaDotOnL3.color
  static let nightMetaBaseL4 = PasturaPalette.nightMetaBaseL4.color
  static let nightMetaStrongL4 = PasturaPalette.nightMetaStrongL4.color
  static let nightMetaDotOnL4 = PasturaPalette.nightMetaDotOnL4.color
  static let nightHeaderRule = PasturaPalette.nightHeaderRule.color
  static let nightHeaderMetaInk = PasturaPalette.nightHeaderMetaInk.color
  static let nightAvatarBodyAlice = PasturaPalette.nightAvatarBodyAlice.color
  static let nightAvatarBodyBob = PasturaPalette.nightAvatarBodyBob.color
  static let nightAvatarBodyCarol = PasturaPalette.nightAvatarBodyCarol.color
  static let nightAvatarBodyDave = PasturaPalette.nightAvatarBodyDave.color
  static let nightAvatarFaceAlice = PasturaPalette.nightAvatarFaceAlice.color
  static let nightAvatarFaceBob = PasturaPalette.nightAvatarFaceBob.color
  static let nightAvatarFaceCarol = PasturaPalette.nightAvatarFaceCarol.color
  static let nightAvatarFaceDave = PasturaPalette.nightAvatarFaceDave.color
  static let nightAvatarHornAlice = PasturaPalette.nightAvatarHornAlice.color
  static let nightAvatarHornBob = PasturaPalette.nightAvatarHornBob.color
  static let nightAvatarHornCarol = PasturaPalette.nightAvatarHornCarol.color
  static let nightAvatarHornDave = PasturaPalette.nightAvatarHornDave.color
  static let nightAvatarEar = PasturaPalette.nightAvatarEar.color
  static let nightAvatarEarInner = PasturaPalette.nightAvatarEarInner.color
  static let nightAvatarNose = PasturaPalette.nightAvatarNose.color
  static let nightAvatarEye = PasturaPalette.nightAvatarEye.color
  static let nightAvatarHighlight = PasturaPalette.nightAvatarHighlight.color
  static let nightPage = PasturaPalette.nightPage.color
  static let nightPromoBackground = PasturaPalette.nightPromoBackground.color
  static let nightPromoBorder = PasturaPalette.nightPromoBorder.color
  static let nightInkOnAccent = PasturaPalette.nightInkOnAccent.color
  static let nightMossDark = PasturaPalette.nightMossDark.color
  static let nightMossInk = PasturaPalette.nightMossInk.color
  static let nightMossSoft = PasturaPalette.nightMossSoft.color
  static let nightLink = PasturaPalette.nightLink.color
  static let nightLinkVisited = PasturaPalette.nightLinkVisited.color
  static let nightLinkHover = PasturaPalette.nightLinkHover.color

  // §2.10 Time-of-Day (decorative ambient)
  static let dawn = PasturaPalette.dawn.color
  static let noon = PasturaPalette.noon.color
  static let dusk = PasturaPalette.dusk.color
  static let night = PasturaPalette.night.color

  // §2.11 Chart
  static let chart1 = PasturaPalette.chart1.color
  static let chart2 = PasturaPalette.chart2.color
  static let chart3 = PasturaPalette.chart3.color
  static let chart4 = PasturaPalette.chart4.color

  // §2.12 Header Slots — GameHeader role-anchored
  static let headerRule = PasturaDynamicPalette.headerRule.color
  static let headerMetaInk = PasturaDynamicPalette.headerMetaInk.color
  static let headerMetaSubdued = PasturaPalette.headerMetaSubdued.color
}

// MARK: - View modifier

extension View {
  /// Applies a ``PasturaTextStyle`` by combining `.font`, `.lineSpacing`,
  /// `.tracking`, and `.textCase` in one call.
  ///
  /// Prefer this over manually chaining those four modifiers at each callsite —
  /// keeps the token intent (one `Typography.*` reference) visible and avoids
  /// forgetting a modifier (e.g. `.textCase(.uppercase)` on `tagPhase`).
  ///
  /// Applied to the result of a `Text + Text` concatenation, `.lineSpacing` and
  /// `.tracking` cover both halves uniformly — load-bearing for callsites like
  /// `AgentOutputRow.primaryView` that use the concat trick for reflow-stable
  /// typing reveals.
  func textStyle(_ style: PasturaTextStyle) -> some View {
    self
      .font(style.font)
      .lineSpacing(style.lineSpacingPoints)
      .tracking(style.trackingPoints)
      .textCase(style.textCase)
  }
}
