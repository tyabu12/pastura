import SwiftUI
import Testing

@testable import Pastura

// Contrast guard for label text on an **opaque** `mossSoft` fill (#1407).
//
// Distinct from `DesignTokensTests+MossOnWash.swift`, which guards moss text on
// a *translucent* moss wash. The two look alike and are not interchangeable:
// `mossOnWash` was solved from the 4.5:1 target on composited washes, and on
// this opaque ground it reaches only 4.292 — same family, different ground,
// different answer.
//
// Sibling-file extension rather than a fresh `@Suite`, per
// `.claude/rules/testing.md` § "Splitting a Suite Across Files". `contrastRatio`
// lives at the foot of `DesignTokensTests+NightPalette.swift`.
extension DesignTokensTests {

  /// The shipped **labels** that lay text directly on an opaque `mossSoft`
  /// capsule. Hand-written against the views rather than derived, so a view
  /// changing its ground does **not** silently update the expectation — the row
  /// goes stale and a reviewer has to look.
  ///
  /// Exhaustive as of #1427 **for moss-family text**, and corroborated rather
  /// than merely grepped: `nightMossSoft`'s own doc comment partitions the
  /// token's ten callsites as seven line/border jobs plus three tinted fills
  /// under `mossInk` text.
  ///
  /// **That corroboration counts grounds, this list counts labels** — four
  /// entries against three fills, because `PredictionOutcomeBadge`'s hit capsule
  /// carries two. Do not "reconcile" them.
  ///
  /// The blind spot they share outlives the count: both start from `mossSoft`
  /// **fill** sites, so neither sees a label drawn on this ground by another
  /// family's token. #1427 repointed the last one (the streak sub-label, `muted`
  /// at 2.136 / 2.413), but that is a fact about today's tree, not a property of
  /// this fixture — so still read this guard as "the moss-family labels clear
  /// AA", never "every label on `mossSoft` does".
  static let mossSoftTextSites = [
    "ContradictionBadge",
    "PredictionOutcomeBadge.hitArm",
    "PredictionOutcomeBadge.streak",
    "HighlightCandidatesSection.revealedChip"
  ]

  /// WCAG 1.4.3 normal-text bar. All four labels are under the "large text"
  /// threshold (≥14pt bold / ≥18pt regular) — the largest is `caption`-class at
  /// ~12pt and the chip is 10pt bold — so 3:1 never applies to any of them.
  ///
  /// ⚠️ **Prose, observed by nothing** — `mossSoftTextSites` is a `[String]`,
  /// so neither that claim nor the superlative inside it can redden when a
  /// fifth label arrives. This is the shape #1466 falsified in
  /// `DesignTokensTests+MossOnWash.swift`; #1468 made it executable for the
  /// three *wash* fixtures via ``WashLabelWeight``, and #1495 tracks bringing
  /// this one along. Do not re-derive the superlative by hand when adding a row
  /// — promote the list instead.
  private static let textBar = 4.5

  /// The ground is the token itself, not a composite: unlike the wash sites,
  /// `mossSoft` here fills the capsule at full opacity, so whatever card or
  /// screen sits behind it is occluded and cannot move the ratio.
  @Test func mossInkClearsAAOnTheOpaqueMossSoftGround() {
    // Size pin: the assertions below don't iterate the fixture, so an emptied
    // list wouldn't make them vacuous — it would silently drop the record of
    // which views this guard speaks for. Residual: it catches a row added or
    // removed, never one *renamed* to a view that no longer draws on this ground.
    #expect(Self.mossSoftTextSites.count == 4)

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
  /// `PredictionOutcomeBadge` has its own pin since #1427 extracted its colours
  /// into accessors (``PredictionOutcomeBadgeTokenTests``). That leaves
  /// `ContradictionBadge`, still inline with no extractable style type and so
  /// code-review-gated; the same extraction would close it.
  @Test func revealedChipReadsMossInk() {
    let style = HighlightCandidatesSection.ChipStyle(reason: .revealed)
    #expect(style.textColor == Color.mossInk)
    #expect(style.background == Color.mossSoft)
  }

  /// The §2.6 convention: every alert family pairs its `Soft` fill with its own
  /// `Ink` text, and moss was the sole deviation.
  ///
  /// **Pins the five pairings that exist today, in both appearances** — not the
  /// individual values, which `DesignTokensTests` owns. It fires when one of
  /// these ten ratios is retuned below the bar.
  ///
  /// It does **not** fire when a *sixth* family is added that skips the
  /// convention: the lists are hand-written literals, so a new `noticeSoft` /
  /// `noticeInk` pair simply would not appear here. Deriving them from
  /// `PasturaDynamicPalette.all` by name suffix would buy that, at the cost of
  /// a guard whose subject is a naming pattern rather than a stated convention.
  /// The `count` pins are what make a silent shrink visible instead.
  @Test func everySoftInkFamilyPairingClearsAAIncludingMoss() {
    // Two members, not three: swiftlint's `large_tuple` caps tuples at two, so
    // the ratio is folded here rather than the token pair carried through.
    let light: [(name: String, ratio: Double)] = [
      ("info", contrastRatio(PasturaPalette.infoInk, PasturaPalette.infoSoft)),
      ("success", contrastRatio(PasturaPalette.successInk, PasturaPalette.successSoft)),
      ("warning", contrastRatio(PasturaPalette.warningInk, PasturaPalette.warningSoft)),
      ("danger", contrastRatio(PasturaPalette.dangerInk, PasturaPalette.dangerSoft)),
      ("moss", contrastRatio(PasturaPalette.mossInk, PasturaPalette.mossSoft))
    ]
    let dark: [(name: String, ratio: Double)] = [
      ("info", contrastRatio(PasturaPalette.nightInfoInk, PasturaPalette.nightInfoSoft)),
      ("success", contrastRatio(PasturaPalette.nightSuccessInk, PasturaPalette.nightSuccessSoft)),
      ("warning", contrastRatio(PasturaPalette.nightWarningInk, PasturaPalette.nightWarningSoft)),
      ("danger", contrastRatio(PasturaPalette.nightDangerInk, PasturaPalette.nightDangerSoft)),
      ("moss", contrastRatio(PasturaPalette.nightMossInk, PasturaPalette.nightMossSoft))
    ]
    // Anti-vacuity: the loops below iterate these literals, so an emptied array
    // would pass silently.
    #expect(light.count == 5)
    #expect(dark.count == 5)
    for family in light {
      #expect(family.ratio >= Self.textBar, "light \(family.name): \(family.ratio)")
    }
    for family in dark {
      #expect(family.ratio >= Self.textBar, "dark \(family.name): \(family.ratio)")
    }
  }
}
