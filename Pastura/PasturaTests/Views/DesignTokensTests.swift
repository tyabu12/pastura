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

  @Test func aliceCreamMatchesSpec() {
    let token = PasturaPalette.avatarAlice
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

  // MARK: - Helpers

  private func approxEqual(_ lhs: Double, _ rhs: Double, tolerance: Double = 0.001) -> Bool {
    abs(lhs - rhs) < tolerance
  }
}
