import SwiftUI

// SwiftUI-facing helpers for the Pastura design system.
//
// Kept separate from `DesignTokens.swift` so the token data sits in one file
// and the SwiftUI bindings (`Color` aliases, `View.textStyle(_:)`) in another
// — eases the future SPM split (tokens module vs UI module).

// MARK: - Color extension (SwiftUI-facing aliases)

extension Color {
  // §2.1 Backgrounds
  static let page = PasturaPalette.page.color
  static let screenBackground = PasturaPalette.screenBackground.color
  static let bubbleBackground = PasturaPalette.bubbleBackground.color
  static let promoBackground = PasturaPalette.promoBackground.color
  static let promoBorder = PasturaPalette.promoBorder.color

  // §2.2 Ink
  static let ink = PasturaPalette.ink.color
  static let inkSecondary = PasturaPalette.inkSecondary.color
  static let muted = PasturaPalette.muted.color
  static let rule = PasturaPalette.rule.color

  // §2.3 Moss
  static let moss = PasturaPalette.moss.color
  static let mossDark = PasturaPalette.mossDark.color
  static let mossInk = PasturaPalette.mossInk.color
  static let mossSoft = PasturaPalette.mossSoft.color

  // §2.4 Meta L1
  static let metaBaseL1 = PasturaPalette.metaBaseL1.color
  static let metaStrongL1 = PasturaPalette.metaStrongL1.color
  static let metaDotOnL1 = PasturaPalette.metaDotOnL1.color

  // §2.4 Meta L2
  static let metaBaseL2 = PasturaPalette.metaBaseL2.color
  static let metaStrongL2 = PasturaPalette.metaStrongL2.color
  static let metaDotOnL2 = PasturaPalette.metaDotOnL2.color

  // §2.4 Meta L3 (default)
  static let metaBaseL3 = PasturaPalette.metaBaseL3.color
  static let metaStrongL3 = PasturaPalette.metaStrongL3.color
  static let metaDotOnL3 = PasturaPalette.metaDotOnL3.color

  // §2.4 Meta L4
  static let metaBaseL4 = PasturaPalette.metaBaseL4.color
  static let metaStrongL4 = PasturaPalette.metaStrongL4.color
  static let metaDotOnL4 = PasturaPalette.metaDotOnL4.color

  // §2.5 Avatars
  static let avatarAlice = PasturaPalette.avatarAlice.color
  static let avatarBob = PasturaPalette.avatarBob.color
  static let avatarCarol = PasturaPalette.avatarCarol.color
  static let avatarDave = PasturaPalette.avatarDave.color
  static let avatarEar = PasturaPalette.avatarEar.color
  static let avatarEarInner = PasturaPalette.avatarEarInner.color
  static let avatarNose = PasturaPalette.avatarNose.color
  static let avatarEye = PasturaPalette.avatarEye.color
  static let avatarHighlight = PasturaPalette.avatarHighlight.color
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
