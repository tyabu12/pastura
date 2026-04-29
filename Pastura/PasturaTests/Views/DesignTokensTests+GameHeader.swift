import SwiftUI
import Testing

@testable import Pastura

// GameHeader-specific design-token tests (#297 PR 3). Sibling-file
// extension of `DesignTokensTests` per `.claude/rules/testing.md` —
// keeps the parent suite's struct body under the 250-line
// `type_body_length` cap. Splitting to a fresh `@Suite` would race
// against the parent suite on shared state, which testing.md explicitly
// forbids.
extension DesignTokensTests {

  // MARK: - §2.12 Header Slots (GameHeader)

  @Test func headerRuleIsLighterThanGeneralRule() {
    let token = PasturaPalette.headerRule
    #expect(approxEqual(token.red, 0xC2 / 255.0))
    #expect(approxEqual(token.green, 0xC0 / 255.0))
    #expect(approxEqual(token.blue, 0xAE / 255.0))
    // Header separator is intentionally lighter than the general-purpose
    // rule (#E0DBCE) — tighter visual weight inside one mono line.
    #expect(token.red < PasturaPalette.rule.red)
    #expect(token.green < PasturaPalette.rule.green)
    #expect(token.blue < PasturaPalette.rule.blue)
  }

  @Test func headerMetaInkSharesHexWithMetaBaseL3() {
    // Role-anchored token: same hex as `metaBaseL3` (#4A4E3D) but a
    // distinct semantic anchor. Pinning the equality so a future change
    // to `metaBaseL3` flags the divergence (the two roles are
    // independent — pick one to update without dragging the other).
    let header = PasturaPalette.headerMetaInk
    let metaL3 = PasturaPalette.metaBaseL3
    #expect(approxEqual(header.red, 0x4A / 255.0))
    #expect(approxEqual(header.green, 0x4E / 255.0))
    #expect(approxEqual(header.blue, 0x3D / 255.0))
    #expect(approxEqual(header.red, metaL3.red))
    #expect(approxEqual(header.green, metaL3.green))
    #expect(approxEqual(header.blue, metaL3.blue))
  }

  @Test func headerMetaSubduedSitsBetweenMetaBaseL1AndL2() {
    let token = PasturaPalette.headerMetaSubdued
    #expect(approxEqual(token.red, 0x7B / 255.0))
    #expect(approxEqual(token.green, 0x7D / 255.0))
    #expect(approxEqual(token.blue, 0x68 / 255.0))
    // Lightness gradient invariant: L1 (lightest) > headerMetaSubdued > L2.
    #expect(PasturaPalette.metaBaseL1.red > token.red)
    #expect(token.red > PasturaPalette.metaBaseL2.red)
  }

  // MARK: - §3 Typography (GameHeader scale)

  @Test func titleScenarioIsHeavierThanTitlePhase() {
    let style = Typography.titleScenario
    #expect(style.size == 16)
    #expect(style.weight == .semibold)
    #expect(style.design == .default)
    #expect(approxEqual(style.lineHeight, 1.2))
    #expect(approxEqual(style.letterSpacingEm, 0.02))
    #expect(style.textCase == nil)
    // Anchors the row above sub-labels.
    #expect(style.size > Typography.titlePhase.size)
  }

  @Test func metaRoundIsMonoSemiboldUpper() {
    let style = Typography.metaRound
    #expect(style.size == 10)
    #expect(style.weight == .semibold)
    #expect(style.design == .monospaced)
    #expect(style.textCase == .uppercase)
    #expect(approxEqual(style.letterSpacingEm, 0.06))
  }

  @Test func metaInlineIsMonoRegularMatchingMetaRoundSize() {
    let style = Typography.metaInline
    #expect(style.size == 10)
    #expect(style.weight == .regular)
    #expect(style.design == .monospaced)
    #expect(style.textCase == nil)
    #expect(approxEqual(style.letterSpacingEm, 0.04))
    // Same size as `metaRound` for vertical-rhythm alignment within row 2.
    #expect(style.size == Typography.metaRound.size)
  }

  @Test func pillStatusHasWideTracking() {
    let style = Typography.pillStatus
    #expect(style.size == 9)
    #expect(style.weight == .semibold)
    #expect(style.design == .monospaced)
    #expect(approxEqual(style.letterSpacingEm, 0.18))
    // Wider than metaLabel (0.06em) so the pill reads as small-caps-y
    // at its reduced size.
    #expect(style.letterSpacingEm > Typography.metaLabel.letterSpacingEm)
  }
}
