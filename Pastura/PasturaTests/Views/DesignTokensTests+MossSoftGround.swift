import SwiftUI
import Testing

@testable import Pastura

// Contrast guard for label text on an **opaque** `mossSoft` fill (#1407).
//
// Distinct from `DesignTokensTests+MossOnWash.swift`, which guards moss text on
// a *translucent* moss wash. The two look alike and are not interchangeable:
// `mossOnWash` was solved from the 4.5:1 target on composited washes, and on
// this opaque ground it reaches only 4.292. Same family, different ground,
// different answer — which is why #1407 was split out of #1327 rather than
// folded into it.
//
// Sibling-file extension of `DesignTokensTests` per `.claude/rules/testing.md`
// § "Splitting a Suite Across Files" — a fresh `@Suite` would run in parallel
// with the parent and is explicitly forbidden. Inherits the parent's
// `@MainActor` and `.timeLimit(.minutes(1))`, and reaches the `contrastRatio`
// helper at the foot of `DesignTokensTests+NightPalette.swift`.
extension DesignTokensTests {

  /// The three shipped views that lay text directly on an opaque `mossSoft`
  /// capsule. Hand-written against the views rather than derived, so a view
  /// changing its ground does **not** silently update the expectation — the row
  /// goes stale and a reviewer has to look.
  ///
  /// Exhaustive as of #1407, and corroborated rather than merely grepped:
  /// `nightMossSoft`'s own doc comment partitions the token's ten callsites as
  /// seven line/border jobs plus exactly these three text grounds.
  static let mossSoftTextSites = [
    "ContradictionBadge",
    "PredictionOutcomeBadge.hitArm",
    "HighlightCandidatesSection.revealedChip"
  ]

  /// WCAG 1.4.3 normal-text bar. All three labels are under the "large text"
  /// threshold (≥14pt bold / ≥18pt regular) — the largest is `caption`-class at
  /// ~12pt and the chip is 10pt bold — so 3:1 never applies to any of them.
  private static let textBar = 4.5

  /// The ground is the token itself, not a composite: unlike the wash sites,
  /// `mossSoft` here fills the capsule at full opacity, so whatever card or
  /// screen sits behind it is occluded and cannot move the ratio.
  @Test func mossInkClearsAAOnTheOpaqueMossSoftGround() {
    // Size pin, not decoration: the assertions below do not iterate the
    // fixture, so an emptied `mossSoftTextSites` would not make them vacuous —
    // but it *would* silently drop the record of which views this guard speaks
    // for, which is the fixture's whole job.
    #expect(Self.mossSoftTextSites.count == 3)

    let light = contrastRatio(PasturaPalette.mossInk, PasturaPalette.mossSoft)
    #expect(light >= Self.textBar, "light: \(light)")

    let dark = contrastRatio(PasturaPalette.nightMossInk, PasturaPalette.nightMossSoft)
    #expect(dark >= Self.textBar, "dark: \(dark)")
  }

  /// The negative control, and the reason the repoint happened.
  ///
  /// A guard's passing case proves nothing on its own — this arm constructs the
  /// state the guard above claims to catch and confirms it *does* fail the bar.
  /// If the `mossDark` assertion ever passes, `mossDark` or `mossSoft` was
  /// retuned; re-derive #1407's conclusion before "fixing" this test.
  ///
  /// Both rejected candidates are pinned, not just the shipped one. Asserting
  /// only `mossDark` would leave a reader thinking the answer was simply "use
  /// the newer role token", and invite exactly the `mossOnWash` substitution
  /// that does not clear the bar here.
  @Test func neitherMossDarkNorMossOnWashClearsTheBarOnThisGround() {
    let mossDark = contrastRatio(PasturaPalette.mossDark, PasturaPalette.mossSoft)
    #expect(mossDark < Self.textBar, "expected sub-AA for mossDark, got \(mossDark)")

    let mossOnWash = contrastRatio(PasturaPalette.mossOnWash, PasturaPalette.mossSoft)
    #expect(mossOnWash < Self.textBar, "expected sub-AA for mossOnWash, got \(mossOnWash)")

    // Dark was never the failing side here — `mossDark`'s dark half already
    // cleared the bar on this ground. Pinning it keeps the change's story
    // honest: this fix is light-only, the opposite asymmetry from #1408.
    let darkBefore = contrastRatio(PasturaPalette.nightMossDark, PasturaPalette.nightMossSoft)
    #expect(darkBefore >= Self.textBar, "dark was supposed to be passing already: \(darkBefore)")
  }

  /// Consumer pin per `.claude/rules/view-testing.md` § "Change-detector
  /// tripwire": the arms above assert token *values*, which cannot notice a
  /// view reverting to `Color.mossDark`. This reads the view's own style.
  ///
  /// One alias against itself, deliberately — asserting that two aliases
  /// *differ* can never fire while either side is a `PasturaDynamicColor`-backed
  /// pair, since those compare by provider instance.
  ///
  /// Only the chip is reachable: `ContradictionBadge` and
  /// `PredictionOutcomeBadge` build their colours inline in `body` with no
  /// extractable style type, so they stay code-review-gated. Extracting a style
  /// struct for them would be the way to close that, and is not done here.
  @Test func revealedChipReadsMossInk() {
    let style = HighlightCandidatesSection.ChipStyle(reason: .revealed)
    #expect(style.textColor == Color.mossInk)
    #expect(style.background == Color.mossSoft)
  }

  /// The §2.6 convention this repoint restores: every alert family pairs its
  /// `Soft` fill with its own `Ink` text, and moss was the sole deviation.
  ///
  /// Pins the *relation*, not the four values — `DesignTokensTests` owns those.
  /// It fires if a future family is added that skips the convention, or if one
  /// of the existing pairs is retuned below the bar.
  @Test func everySoftInkFamilyPairingClearsAAIncludingMoss() {
    // Two members, not three: swiftlint's `large_tuple` caps tuples at two, so
    // the ratio is folded here rather than the token pair carried through.
    let families: [(name: String, ratio: Double)] = [
      ("info", contrastRatio(PasturaPalette.infoInk, PasturaPalette.infoSoft)),
      ("success", contrastRatio(PasturaPalette.successInk, PasturaPalette.successSoft)),
      ("warning", contrastRatio(PasturaPalette.warningInk, PasturaPalette.warningSoft)),
      ("danger", contrastRatio(PasturaPalette.dangerInk, PasturaPalette.dangerSoft)),
      ("moss", contrastRatio(PasturaPalette.mossInk, PasturaPalette.mossSoft))
    ]
    #expect(families.count == 5)
    for family in families {
      #expect(family.ratio >= Self.textBar, "\(family.name): \(family.ratio)")
    }
  }
}
