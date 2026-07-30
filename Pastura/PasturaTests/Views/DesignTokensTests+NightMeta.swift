import Foundation
import Testing

@testable import Pastura

// sRGB component assertions and design invariants for the §2.9 dark counterparts
// of §2.4's meta-contrast presets and §2.12's GameHeader slots — slice 2 of
// ADR-028 gate 1 (#1313).
//
// Split out of `DesignTokensTests+NightPalette.swift` when slice 4 landed, on the
// per-section axis ADR-028's #1319 Amendment set for slices 3-4: that file had
// reached 338 lines and slice 4 adds §2.1/§2.3/§2.8 invariants to it.
//
// Sibling-file extension of `DesignTokensTests` per `.claude/rules/testing.md`
// § "Splitting a Suite Across Files" — a fresh `@Suite` would run in parallel
// with the parent and is explicitly forbidden. Inherits the parent's
// `@MainActor` and `.timeLimit(.minutes(1))`, and reaches the `contrastRatio` /
// `composite` / `relativeLuminance` helpers at the foot of
// `DesignTokensTests+NightPalette.swift`, which are internal-not-private for
// exactly this reason.
extension DesignTokensTests {

  // MARK: - §2.9 dark counterparts of the §2.4 meta presets + §2.12 header slots

  @Test func nightMetaAndHeaderTokensMatchSpec() {
    let cases: [(token: PasturaColorValue, hex: UInt32)] = [
      (PasturaPalette.nightMetaBaseL1, 0x7E7F6B),
      (PasturaPalette.nightMetaStrongL1, 0xA0AC88),
      (PasturaPalette.nightMetaDotOnL1, 0xA8B888),
      (PasturaPalette.nightMetaBaseL2, 0x9DA08C),
      (PasturaPalette.nightMetaStrongL2, 0xD5DBCB),
      (PasturaPalette.nightMetaDotOnL2, 0xB7C49C),
      (PasturaPalette.nightMetaBaseL3, 0xC7CABC),
      (PasturaPalette.nightMetaStrongL3, 0xE8E5D8),
      (PasturaPalette.nightMetaDotOnL3, 0xC3CEAE),
      (PasturaPalette.nightMetaBaseL4, 0xE8E5D8),
      (PasturaPalette.nightMetaStrongL4, 0xF1F0E8),
      (PasturaPalette.nightMetaDotOnL4, 0xD5DDC6),
      (PasturaPalette.nightHeaderRule, 0x474535),
      (PasturaPalette.nightHeaderMetaInk, 0xB2B6A2)
    ]

    for (token, hex) in cases {
      #expect(approxEqual(token.red, Double((hex >> 16) & 0xFF) / 255.0))
      #expect(approxEqual(token.green, Double((hex >> 8) & 0xFF) / 255.0))
      #expect(approxEqual(token.blue, Double(hex & 0xFF) / 255.0))
      #expect(approxEqual(token.opacity, 1.0))
    }
  }

  /// The §2.4 ladder must run the OTHER WAY in dark. Light's sibling assertion
  /// (`metaContrastRangesFromL1ToL4`) checks L1 > L2 > L3 > L4 on the red
  /// channel; here the comparator inverts, because in dark a higher preset
  /// gains contrast by getting brighter rather than darker.
  ///
  /// This is the executable form of the constraint slice 2 otherwise left as
  /// prose. Slice 2 designed the ladder against `nightBubble` as a provisional
  /// ground and armed a tripwire on the companion assertion below; slice 4 paired
  /// `promoBackground`, the tripwire fired, and the ladder was re-measured
  /// against the real ground. Ordering by channel is ground-independent, so this
  /// test did not move — the companion one carries the re-measurement.
  @Test func nightMetaLadderRunsBrighterFromL1ToL4() {
    #expect(PasturaPalette.nightMetaBaseL1.red < PasturaPalette.nightMetaBaseL2.red)
    #expect(PasturaPalette.nightMetaBaseL2.red < PasturaPalette.nightMetaBaseL3.red)
    #expect(PasturaPalette.nightMetaBaseL3.red < PasturaPalette.nightMetaBaseL4.red)

    #expect(PasturaPalette.nightMetaStrongL1.red < PasturaPalette.nightMetaStrongL2.red)
    #expect(PasturaPalette.nightMetaStrongL2.red < PasturaPalette.nightMetaStrongL3.red)
    #expect(PasturaPalette.nightMetaStrongL3.red < PasturaPalette.nightMetaStrongL4.red)

    #expect(PasturaPalette.nightMetaDotOnL1.red < PasturaPalette.nightMetaDotOnL2.red)
    #expect(PasturaPalette.nightMetaDotOnL2.red < PasturaPalette.nightMetaDotOnL3.red)
    #expect(PasturaPalette.nightMetaDotOnL3.red < PasturaPalette.nightMetaDotOnL4.red)
  }

  /// Each dark preset must deliver more contrast than the one below it
  /// **against the surface it renders on**, and `strong` must stay strictly
  /// louder than `base` within a step. Ordering by channel (above) is necessary but not
  /// sufficient — it survives a change of ground, this does not.
  ///
  /// Honest about its limit: it catches an *inversion*, not a shrinking step.
  /// Nothing here pins a minimum gap, because no threshold could be derived
  /// rather than invented.
  ///
  /// **The ground is now the real one.** Slice 2 measured this ladder against
  /// `nightBubble` as a stand-in and left a tripwire here — an assertion that
  /// `promoBackground` was absent from the pair registry — so that pairing it
  /// would redden this test and force a re-measurement rather than leaving one as
  /// an instruction. Slice 4 paired it, the tripwire fired, and the ground is
  /// repointed at `PasturaDynamicPalette.promoBackground.dark`. The tripwire is
  /// gone because it has been discharged; deleting it is the *point*, not a
  /// silencing.
  ///
  /// What the re-measurement found: `promoBackground`'s dark value came out at
  /// #282C24, **outside** the #2A2D26-#2F3229 band slice 2 assumed (Y 0.0238 vs
  /// the band floor's 0.0251), and the ladder holds anyway — base ratios rose
  /// 3.33/5.08/8.16/10.77 to 3.48/5.31/8.54/11.27, monotone, with L3 at 8.54
  /// against the 4.5 the design system promises. That is the tripwire working as
  /// designed: slice 2 deliberately did **not** check the band, on the grounds
  /// that the ladder stays monotone at either end of it and such a check would
  /// pass by construction while the ladder had never been measured against the
  /// real surface.
  @Test func nightMetaLadderStaysMonotonicAgainstTheCardSurface() {
    let ground = PasturaPalette.nightPromoBackground
    let base = [
      PasturaPalette.nightMetaBaseL1, PasturaPalette.nightMetaBaseL2,
      PasturaPalette.nightMetaBaseL3, PasturaPalette.nightMetaBaseL4
    ].map { contrastRatio($0, ground) }
    let strong = [
      PasturaPalette.nightMetaStrongL1, PasturaPalette.nightMetaStrongL2,
      PasturaPalette.nightMetaStrongL3, PasturaPalette.nightMetaStrongL4
    ].map { contrastRatio($0, ground) }

    for index in 0..<3 {
      #expect(base[index] < base[index + 1])
      #expect(strong[index] < strong[index + 1])
    }
    for index in 0..<4 {
      #expect(strong[index] > base[index])
    }
    // L3 is the documented default and the only preset with app consumers;
    // design-system.md § 9 promises it clears 4.5:1 for meta information.
    #expect(base[2] >= 4.5)
  }

  /// The lit progress dot is placed by lit-vs-unlit contrast, not by contrast
  /// against the ground — its job is telling a lit dot from an unlit one. The
  /// unlit dot is `moss` at 38%, and `moss` is already paired, so in dark that
  /// floor rises to `nightMoss` @38% composited over the card. Mirroring the
  /// ground ratio instead would drop L1 to ~1.34:1 and the indicator stops
  /// working; this pins the property that placement exists to protect.
  ///
  /// **Both sides now composite over the same role.** The light leg always used
  /// `promoBackground`; the dark leg used `nightBubble` because
  /// `promoBackground` was unpaired, so the two legs measured different surfaces.
  /// Slice 4 closed that asymmetry — a latent one, since nothing asserted the
  /// legs were comparable.
  @Test func nightLitDotsStayDistinguishableFromUnlitOnes() {
    let unlit = composite(
      PasturaPalette.nightMoss, over: PasturaPalette.nightPromoBackground, alpha: 0.38)
    let lit = [
      PasturaPalette.nightMetaDotOnL1, PasturaPalette.nightMetaDotOnL2,
      PasturaPalette.nightMetaDotOnL3, PasturaPalette.nightMetaDotOnL4
    ].map { contrastRatio($0, unlit) }

    // Light's own lit-vs-unlit ladder, which dark must not fall below. Derived
    // rather than frozen: the claim is about *light's* ladder, so an edit to
    // `moss`, `promoBackground` or any `metaDotOnL*` has to move this floor too
    // — a literal would silently stop representing what it is named after.
    let lightUnlit = composite(
      PasturaPalette.moss, over: PasturaPalette.promoBackground, alpha: 0.38)
    let lightFloor = [
      PasturaPalette.metaDotOnL1, PasturaPalette.metaDotOnL2,
      PasturaPalette.metaDotOnL3, PasturaPalette.metaDotOnL4
    ].map { contrastRatio($0, lightUnlit) }
    // Margins run [1.02, 1.02, 0.78, 0.30] against the real ground (they were
    // [0.93, 0.91, 0.66, 0.16] against the `nightBubble` stand-in). L4 is still
    // the tightest step and so the one an edit to `metaDotOnL4` or to light's
    // ground flips first — but it is no longer "an order of magnitude" tighter as
    // the stand-in figures made it look, only ~3.4x. Named so the next red is
    // diagnosed, not re-derived; the claim is restated rather than just the
    // numbers, because repointing the ground changed which of the two is true.
    for (measured, floor) in zip(lit, lightFloor) {
      #expect(measured >= floor)
    }
    for index in 0..<3 {
      #expect(lit[index] < lit[index + 1])
    }
  }

  /// `metaDotOnL1` re-states `moss` and `focusRing` in light (#8A9A6C); the dark
  /// side carries that three-way coincidence across deliberately. Pinned because
  /// a reader finding three identical hexes would otherwise reasonably collapse
  /// them — and because the `tokens.css` mirror gate cannot see these rows at
  /// all (it substring-matches the hex, which already appears under two other
  /// names).
  @Test func nightMetaDotOnL1IntentionallyMatchesNightMoss() {
    #expect(PasturaPalette.nightMetaDotOnL1 == PasturaPalette.nightMoss)
    #expect(PasturaPalette.nightMetaDotOnL1 == PasturaPalette.nightFocusRing)
  }

  /// Same shape for the ceiling-bound top of the ladder: light's `metaBaseL4`
  /// and `metaStrongL3` are both `ink`, and both dark values are `nightInk`.
  @Test func nightMetaLadderTopIntentionallyMatchesNightInk() {
    #expect(PasturaPalette.nightMetaBaseL4 == PasturaPalette.nightInk)
    #expect(PasturaPalette.nightMetaStrongL3 == PasturaPalette.nightInk)
  }

  /// `headerMetaSubdued` is deliberately **not** paired — it is fixed in both
  /// appearances, which ADR-028 gate 1 admits as an equal alternative to a
  /// designed dark value. The reason is measurable, so it is measured: a
  /// mid-lightness tone reads the same against a pale ground and a dark one, so
  /// solving its own light contrast on the night ground returns its own value.
  ///
  /// This is the guard on that decision, on both halves of it. Changing the
  /// token breaks the measurement below; pairing it trips the registry check,
  /// which is here rather than left to `exactlySixtySevenPairsAreWired` so that the
  /// *reason* fixing is right is what reddens, not just an arithmetic count.
  @Test func headerMetaSubduedReadsTheSameOnBothGrounds() {
    #expect(!PasturaDynamicPalette.all.contains { $0.name == "headerMetaSubdued" })

    let onLight = contrastRatio(PasturaPalette.headerMetaSubdued, PasturaPalette.screenBackground)
    let onNight = contrastRatio(PasturaPalette.headerMetaSubdued, PasturaPalette.nightBackground)
    #expect(abs(onLight - onNight) < 0.05)

    // And it must keep sitting between the separator and the phase name in dark,
    // which is the hierarchy §2.12 actually describes.
    let rule = contrastRatio(PasturaPalette.nightHeaderRule, PasturaPalette.nightBackground)
    let ink = contrastRatio(PasturaPalette.nightHeaderMetaInk, PasturaPalette.nightBackground)
    #expect(rule < onNight)
    #expect(onNight < ink)
  }
}
