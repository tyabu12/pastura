import SwiftUI

// SwiftUI-facing helpers for the Pastura design system.
//
// Kept separate from `DesignTokens.swift` so the token data sits in one file
// and the SwiftUI bindings (`Color` aliases, `View.textStyle(_:)`) in another
// — eases the future SPM split (tokens module vs UI module).

// MARK: - Color extension (SwiftUI-facing aliases)

extension Color {
  // The 26 aliases sourced from `PasturaDynamicPalette` resolve light/dark
  // against the ambient interface style (§2.9, ADR-028 plus the §2.6/§2.7
  // slice in #1282); every other alias below is light-only because its token
  // has no dark counterpart yet. The app is pinned to light via `Info.plist`'s
  // `UIUserInterfaceStyle`, so no half-dark surface can render while that is
  // true.
  //
  // Need a specific appearance regardless of the device — e.g. an
  // `ImageRenderer` export, which does not inherit the ambient environment?
  // Read `PasturaPalette.<token>.color` directly instead of these aliases.
  // `HighlightShareCard` is the reference consumer. That is the sanctioned
  // explicit-appearance accessor — note the `Color.night*` aliases below now
  // have ZERO consumers (this change moved their last one, that same card, to
  // the raw palette); they remain only as defined-ahead-of-need tokens, and are
  // not a second sanctioned route to a fixed appearance.

  // §2.1 Backgrounds
  static let page = PasturaPalette.page.color
  static let screenBackground = PasturaDynamicPalette.screenBackground.color
  static let bubbleBackground = PasturaDynamicPalette.bubbleBackground.color
  static let whisperBubble = PasturaDynamicPalette.whisperBubble.color
  static let promoBackground = PasturaPalette.promoBackground.color
  static let promoBorder = PasturaPalette.promoBorder.color

  // §2.2 Ink
  static let ink = PasturaDynamicPalette.ink.color
  static let inkSecondary = PasturaDynamicPalette.inkSecondary.color
  static let muted = PasturaDynamicPalette.muted.color
  static let rule = PasturaDynamicPalette.rule.color
  static let inkOnAccent = PasturaPalette.inkOnAccent.color

  // §2.3 Moss
  static let moss = PasturaDynamicPalette.moss.color
  static let mossDark = PasturaPalette.mossDark.color
  static let mossInk = PasturaPalette.mossInk.color
  static let mossSoft = PasturaPalette.mossSoft.color

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

  // §2.5 Avatars
  static let avatarBodyAlice = PasturaPalette.avatarBodyAlice.color
  static let avatarBodyBob = PasturaPalette.avatarBodyBob.color
  static let avatarBodyCarol = PasturaPalette.avatarBodyCarol.color
  static let avatarBodyDave = PasturaPalette.avatarBodyDave.color
  static let avatarFaceAlice = PasturaPalette.avatarFaceAlice.color
  static let avatarFaceBob = PasturaPalette.avatarFaceBob.color
  static let avatarFaceCarol = PasturaPalette.avatarFaceCarol.color
  static let avatarFaceDave = PasturaPalette.avatarFaceDave.color
  static let avatarHornAlice = PasturaPalette.avatarHornAlice.color
  static let avatarHornBob = PasturaPalette.avatarHornBob.color
  static let avatarHornCarol = PasturaPalette.avatarHornCarol.color
  static let avatarHornDave = PasturaPalette.avatarHornDave.color
  static let avatarEar = PasturaPalette.avatarEar.color
  static let avatarEarInner = PasturaPalette.avatarEarInner.color
  static let avatarNose = PasturaPalette.avatarNose.color
  static let avatarEye = PasturaPalette.avatarEye.color
  static let avatarHighlight = PasturaPalette.avatarHighlight.color

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
  static let link = PasturaPalette.link.color
  static let linkVisited = PasturaPalette.linkVisited.color
  static let linkHover = PasturaPalette.linkHover.color

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
