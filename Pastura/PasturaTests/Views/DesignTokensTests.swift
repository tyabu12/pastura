import SwiftUI
import Testing

@testable import Pastura

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct DesignTokensTests {

  // MARK: - §2.1 Backgrounds

  @Test func pageBackgroundMatchesSpec() {
    let token = PasturaPalette.page
    #expect(approxEqual(token.red, 0xF3 / 255.0))
    #expect(approxEqual(token.green, 0xEF / 255.0))
    #expect(approxEqual(token.blue, 0xE7 / 255.0))
    #expect(approxEqual(token.opacity, 1.0))
  }

  @Test func screenBackgroundMatchesSpec() {
    let token = PasturaPalette.screenBackground
    #expect(approxEqual(token.red, 0xFC / 255.0))
    #expect(approxEqual(token.green, 0xFA / 255.0))
    #expect(approxEqual(token.blue, 0xF4 / 255.0))
    #expect(approxEqual(token.opacity, 1.0))
  }

  @Test func bubbleBackgroundIsPureWhite() {
    let token = PasturaPalette.bubbleBackground
    #expect(approxEqual(token.red, 1.0))
    #expect(approxEqual(token.green, 1.0))
    #expect(approxEqual(token.blue, 1.0))
  }

  // MARK: - §2.2 Ink

  @Test func inkPrimaryIsNotPureBlack() {
    let token = PasturaPalette.ink
    #expect(approxEqual(token.red, 0x2D / 255.0))
    #expect(approxEqual(token.green, 0x2E / 255.0))
    #expect(approxEqual(token.blue, 0x26 / 255.0))
    #expect(token.red > 0)
    #expect(token.green > 0)
    #expect(token.blue > 0)
  }

  @Test func mutedMatchesSpec() {
    let token = PasturaPalette.muted
    #expect(approxEqual(token.red, 0x8A / 255.0))
    #expect(approxEqual(token.green, 0x8A / 255.0))
    #expect(approxEqual(token.blue, 0x83 / 255.0))
  }

  // MARK: - §2.3 Moss Accent

  @Test func mossPrimaryMatchesSpec() {
    let token = PasturaPalette.moss
    #expect(approxEqual(token.red, 0x8A / 255.0))
    #expect(approxEqual(token.green, 0x9A / 255.0))
    #expect(approxEqual(token.blue, 0x6C / 255.0))
  }

  @Test func mossDarkMatchesSpec() {
    let token = PasturaPalette.mossDark
    #expect(approxEqual(token.red, 0x6B / 255.0))
    #expect(approxEqual(token.green, 0x78 / 255.0))
    #expect(approxEqual(token.blue, 0x52 / 255.0))
  }

  // MARK: - §2.4 Meta Contrast Presets

  @Test func metaL3IsTheDocumentedDefault() {
    let base = PasturaPalette.metaBaseL3
    #expect(approxEqual(base.red, 0x4A / 255.0))
    #expect(approxEqual(base.green, 0x4E / 255.0))
    #expect(approxEqual(base.blue, 0x3D / 255.0))

    let strong = PasturaPalette.metaStrongL3
    #expect(approxEqual(strong.red, 0x2D / 255.0))
    #expect(approxEqual(strong.green, 0x2E / 255.0))
    #expect(approxEqual(strong.blue, 0x26 / 255.0))

    let dotOn = PasturaPalette.metaDotOnL3
    #expect(approxEqual(dotOn.red, 0x6B / 255.0))
    #expect(approxEqual(dotOn.green, 0x78 / 255.0))
    #expect(approxEqual(dotOn.blue, 0x52 / 255.0))
  }

  @Test func metaContrastRangesFromL1ToL4() {
    // L1 is the lightest (highest R/G/B on base), L4 the darkest — verify the gradient
    // exists, without locking every hex (those are covered by L3 above).
    #expect(PasturaPalette.metaBaseL1.red > PasturaPalette.metaBaseL2.red)
    #expect(PasturaPalette.metaBaseL2.red > PasturaPalette.metaBaseL3.red)
    #expect(PasturaPalette.metaBaseL3.red > PasturaPalette.metaBaseL4.red)
  }

  // MARK: - §2.5 Avatars

  @Test func aliceBodyMatchesSpec() {
    let token = PasturaPalette.avatarBodyAlice
    #expect(approxEqual(token.red, 0xF2 / 255.0))
    #expect(approxEqual(token.green, 0xE3 / 255.0))
    #expect(approxEqual(token.blue, 0xC8 / 255.0))
  }

  @Test func avatarHighlightIsTranslucentWhite() {
    let token = PasturaPalette.avatarHighlight
    #expect(approxEqual(token.red, 1.0))
    #expect(approxEqual(token.green, 1.0))
    #expect(approxEqual(token.blue, 1.0))
    #expect(approxEqual(token.opacity, 0.6))
  }

  // MARK: - §4.3 Shadow

  @Test func softShadowIsMossTinted() {
    let shadow = PasturaShadows.soft
    // rgba(90,100,60,.2): moss-tinted, not neutral black
    #expect(approxEqual(shadow.color.red, 90 / 255.0))
    #expect(approxEqual(shadow.color.green, 100 / 255.0))
    #expect(approxEqual(shadow.color.blue, 60 / 255.0))
    #expect(approxEqual(shadow.color.opacity, 0.2))
    #expect(shadow.y == 12)
    #expect(shadow.radius == 26)
  }

  @Test func tightShadowIsMossTinted() {
    let shadow = PasturaShadows.tight
    #expect(approxEqual(shadow.color.red, 90 / 255.0))
    #expect(approxEqual(shadow.color.green, 100 / 255.0))
    #expect(approxEqual(shadow.color.blue, 60 / 255.0))
    #expect(approxEqual(shadow.color.opacity, 0.04))
    #expect(shadow.y == 1)
    #expect(shadow.radius == 2)
  }

  // MARK: - §3 Typography

  @Test func titlePhaseMatchesSpec() {
    let style = Typography.titlePhase
    #expect(style.size == 13)
    #expect(style.weight == .semibold)
    #expect(style.design == .default)
    #expect(approxEqual(style.lineHeight, 1.3))
    #expect(approxEqual(style.letterSpacingEm, 0.02))
    #expect(style.isItalic == false)
    #expect(style.textCase == nil)
  }

  @Test func tagPhaseIsMonoUpper() {
    let style = Typography.tagPhase
    #expect(style.design == .monospaced)
    #expect(style.textCase == .uppercase)
    #expect(approxEqual(style.letterSpacingEm, 0.22))
  }

  @Test func thinkingBodyIsItalic() {
    let style = Typography.thinkingBody
    #expect(style.isItalic == true)
    #expect(approxEqual(style.lineHeight, 1.7))
  }

  @Test func metaValueIsMonoRegular() {
    let style = Typography.metaValue
    #expect(style.design == .monospaced)
    #expect(style.weight == .regular)
    #expect(style.size == 9)
  }

  @Test func lineSpacingPointsDerivedFromLineHeight() {
    // body/bubble: 13pt × (1.65 − 1.0) = 8.45pt
    let style = Typography.bodyBubble
    #expect(approxEqual(Double(style.lineSpacingPoints), 13 * 0.65))
  }

  @Test func trackingPointsDerivedFromLetterSpacing() {
    // tag/phase: 9.5pt × 0.22 = 2.09pt
    let style = Typography.tagPhase
    #expect(approxEqual(Double(style.trackingPoints), 9.5 * 0.22))
  }

  @Test func thinkingBodyLineSpacingDerivedFromLineHeight() {
    // thinking/body: 10.5pt × (1.7 − 1.0) = 7.35pt
    let style = Typography.thinkingBody
    #expect(approxEqual(Double(style.lineSpacingPoints), 10.5 * 0.7))
  }

  @Test func thinkingBodyTrackingDerivedFromLetterSpacing() {
    // thinking/body: 10.5pt × 0.02em = 0.21pt
    let style = Typography.thinkingBody
    #expect(approxEqual(Double(style.trackingPoints), 10.5 * 0.02))
  }

  // MARK: - §4 Spacing

  @Test func spacingScaleMatchesSpec() {
    #expect(Spacing.xxs == 4)
    #expect(Spacing.xs == 8)
    #expect(Spacing.s == 12)
    #expect(Spacing.m == 14)
    #expect(Spacing.l == 20)
    #expect(Spacing.xl == 32)
    #expect(Spacing.xxl == 48)
  }

  // MARK: - §4 Radius

  @Test func radiusScaleMatchesSpec() {
    #expect(Radius.deviceInner == 31)
    #expect(Radius.bubbleTail == 4)
    #expect(Radius.bubbleBody == 14)
    #expect(Radius.promo == 14)
    #expect(Radius.button == 8)
    #expect(Radius.dot == .infinity)
  }

  // MARK: - Helpers

  private func approxEqual(_ lhs: Double, _ rhs: Double, tolerance: Double = 0.001) -> Bool {
    abs(lhs - rhs) < tolerance
  }
}
