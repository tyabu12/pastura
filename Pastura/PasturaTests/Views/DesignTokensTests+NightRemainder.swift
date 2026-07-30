import Foundation
import Testing

@testable import Pastura

// Design invariants for the §2.9 dark counterparts of the §2.1/§2.2/§2.3/§2.8
// remainder — slice 4 of ADR-028 gate 1, the slice that **closed** that gate.
//
// Its own file rather than an addition to `DesignTokensTests+NightPalette.swift`:
// that file was at 170 lines after slice 4's stage-0 split and this block is
// ~300, so the two together would cross swiftlint's 400-line `file_length` cap.
// Same per-section axis the rest of slice 4 used.
//
// Every guard here is a **pure predicate plus a matched pair of tests** — the
// shipped palette satisfies it, and a deliberately-broken input violates it. A
// guard's success case alone proves nothing, because it may be constant. Where
// the broken input is an alternative this slice actually rejected, that is said:
// a control drawn from the real decision is worth more than an invented one.
//
// Sibling-file extension of `DesignTokensTests` per `.claude/rules/testing.md`
// § "Splitting a Suite Across Files" — a fresh `@Suite` would run in parallel
// with the parent and is explicitly forbidden. Inherits the parent's
// `@MainActor` and `.timeLimit(.minutes(1))`, reaches its `approxEqual` helper,
// and reaches `relativeLuminance` / `contrastRatio` at the foot of
// `DesignTokensTests+NightPalette.swift`.
extension DesignTokensTests {

  @Test func nightRemainderTokensMatchSpec() {
    let cases: [(token: PasturaColorValue, hex: UInt32)] = [
      (PasturaPalette.nightPage, 0x11130F),
      (PasturaPalette.nightPromoBackground, 0x282C24),
      (PasturaPalette.nightPromoBorder, 0x35392F),
      (PasturaPalette.nightInkOnAccent, 0x2C2F28),
      (PasturaPalette.nightMossDark, 0xB3C197),
      (PasturaPalette.nightMossInk, 0xC6CBB1),
      (PasturaPalette.nightMossSoft, 0x384029),
      (PasturaPalette.nightLink, 0x699054),
      (PasturaPalette.nightLinkVisited, 0x9B9075),
      (PasturaPalette.nightLinkHover, 0x7FAA62)
    ]
    for (token, hex) in cases {
      #expect(approxEqual(token.red, Double((hex >> 16) & 0xFF) / 255.0))
      #expect(approxEqual(token.green, Double((hex >> 8) & 0xFF) / 255.0))
      #expect(approxEqual(token.blue, Double(hex & 0xFF) / 255.0))
      #expect(approxEqual(token.opacity, 1.0))
    }
  }

  /// §2.3's four steps run one way in light and the **other way** in dark. Light
  /// orders them ink < dark < moss < soft by luminance (ink darkest); dark orders
  /// them soft < moss < dark < ink (ink brightest). That inversion is the whole
  /// reason arm 3 is degenerate for `mossDark` — see this file's sibling MARK in
  /// `DesignTokens+NightPalette.swift`.
  @Test func mossFamilyOrderingInvertsBetweenAppearances() {
    #expect(
      isStrictlyBrightening([
        PasturaPalette.mossInk, PasturaPalette.mossDark,
        PasturaPalette.moss, PasturaPalette.mossSoft
      ]))
    #expect(
      isStrictlyBrightening([
        PasturaPalette.nightMossSoft, PasturaPalette.nightMoss,
        PasturaPalette.nightMossDark, PasturaPalette.nightMossInk
      ]))
  }

  /// The control for the above: the dark family arranged in **light's** role
  /// order must NOT be brightening. Without this the assertion could pass on a
  /// family that had not inverted at all — four tokens in any monotone order
  /// satisfy `isStrictlyBrightening` for *some* permutation.
  @Test func mossFamilyOrderingControlRejectsTheUninvertedArrangement() {
    #expect(
      !isStrictlyBrightening([
        PasturaPalette.nightMossInk, PasturaPalette.nightMossDark,
        PasturaPalette.nightMoss, PasturaPalette.nightMossSoft
      ]))
  }

  /// `inkOnAccent`'s contract is a pair of WCAG bars, not a single ratio: text AA
  /// (4.5:1) over the emphatic fill `mossDark`, and the 1.4.11 non-text bar
  /// (3:1) over base `moss`, where only shapes sit. Both appearances must clear
  /// both — dark does so with more room (7.117 / 6.395 against light's
  /// 4.737 / 3.035), which is what placing it at WCAG AAA bought.
  @Test func onAccentForegroundClearsBothBarsInBothAppearances() {
    #expect(
      onAccentForegroundClearsItsBars(
        foreground: PasturaPalette.inkOnAccent,
        emphaticFill: PasturaPalette.mossDark,
        baseFill: PasturaPalette.moss))
    #expect(
      onAccentForegroundClearsItsBars(
        foreground: PasturaPalette.nightInkOnAccent,
        emphaticFill: PasturaPalette.nightMossDark,
        baseFill: PasturaPalette.nightMoss))
  }

  /// The control, and it is **the alternative this slice rejected**: keeping
  /// `inkOnAccent` white in both appearances. White over `nightMoss` measures
  /// ≈2.13:1 — under even the non-text bar — which is precisely why ADR-028
  /// listed this token as owing gate 1 an answer rather than being fixed in both
  /// appearances. A control drawn from the real decision, not invented.
  @Test func onAccentForegroundControlRejectsHoldingWhiteInDark() {
    #expect(
      !onAccentForegroundClearsItsBars(
        foreground: PasturaPalette.inkOnAccent,
        emphaticFill: PasturaPalette.nightMossDark,
        baseFill: PasturaPalette.nightMoss))
  }

  /// A quiet line must read against **both** the surface it is drawn on and the
  /// ground behind that surface. In light such lines sit darker than their
  /// surface; in dark they must sit lighter, because holding the magnitude on the
  /// dark side instead collapses them into the ground. The original eight
  /// established this with `rule` -> `nightRule`; slice 4 follows it for
  /// `promoBorder` and `mossSoft`.
  @Test func quietLinesInvertDirectionAndStaySeparableInDark() {
    // Light: darker than its surface, and that is fine because a near-white
    // ground affords the step.
    #expect(relativeLuminance(PasturaPalette.rule) < relativeLuminance(PasturaPalette.screenBackground))
    #expect(
      relativeLuminance(PasturaPalette.promoBorder)
        < relativeLuminance(PasturaPalette.promoBackground))
    #expect(
      relativeLuminance(PasturaPalette.mossSoft)
        < relativeLuminance(PasturaPalette.screenBackground))

    // Dark: lighter, and separable from the ground behind.
    #expect(
      lineSeparatesSurfaceFromGround(
        line: PasturaPalette.nightPromoBorder,
        surface: PasturaPalette.nightPromoBackground,
        ground: PasturaPalette.nightBackground))
    #expect(
      lineSeparatesSurfaceFromGround(
        line: PasturaPalette.nightRule,
        surface: PasturaPalette.nightBubble,
        ground: PasturaPalette.nightBackground))
  }

  /// The control, again the rejected alternative: a `promoBorder` that keeps
  /// light's 1.204 but on the **darker** side of its card lands at #1A1C17, which
  /// measures 1.207 against the card — passing, if that were the only check — and
  /// **1.010 against the ground behind it**. The card edge would dissolve exactly
  /// where it has to read. This is why the predicate takes a ground at all.
  @Test func quietLineControlRejectsTheDarkerDirection() {
    #expect(
      !lineSeparatesSurfaceFromGround(
        line: PasturaColorValue(hex: 0x1A1C17),
        surface: PasturaPalette.nightPromoBackground,
        ground: PasturaPalette.nightBackground))
  }

  /// `mossSoft` + `mossDark` form a §2.6-shaped Soft/Ink badge pair
  /// (`ContradictionBadge`, `PredictionOutcomeBadge`, `HighlightCandidatesSection`),
  /// and its designed property is *relative*: it is the quietest of the five in
  /// both appearances. Neither token was placed against the other — `mossSoft` by
  /// its line job, `mossDark` by its ladder position — so this holding is a
  /// consequence worth pinning rather than a target that was aimed at.
  @Test func mossBadgeStaysTheQuietestOfTheFiveInBothAppearances() {
    #expect(mossBadgeIsQuietest(dark: false))
    #expect(mossBadgeIsQuietest(dark: true))
  }

  /// The control: substituting `nightInk` for `nightMossDark` lifts the moss
  /// badge into the §2.6 band and it stops being the quietest. Without this the
  /// assertion above could pass on a predicate that is simply always true.
  @Test func mossBadgeQuietestControlRejectsALiftedInk() {
    #expect(
      !isQuietestPair(
        ink: PasturaPalette.nightInk, soft: PasturaPalette.nightMossSoft,
        others: nightBadgePairs()))
  }

  /// `nightPage` **sinks** below the body ground, mirroring light's `page` sitting
  /// below `screenBackground` — the workbench stays the dim surface in both
  /// appearances rather than inverting into an elevated one. Pinned because the
  /// tempting dark-UI move is the opposite, and because at HSL L=6.7% this is the
  /// palette's darkest token, which reads like an error unless the intent is
  /// recorded. `ViewerPredictionSheet` renders it, so ADR-028 gate 4 carries the
  /// visual half of this decision.
  @Test func nightPageSinksBelowTheBodyGround() {
    #expect(
      relativeLuminance(PasturaPalette.page) < relativeLuminance(PasturaPalette.screenBackground))
    #expect(
      relativeLuminance(PasturaPalette.nightPage)
        < relativeLuminance(PasturaPalette.nightBackground))
  }

  /// `ModelPickerView`'s CTA is a `mossInk` fill carrying a `screenBackground`
  /// label. Both tokens are paired and both hold their ratio against their own
  /// appearance's extreme, so the button's label contrast survives the appearance
  /// flip without anyone having placed it — 10.190 in light, 10.187 in dark.
  ///
  /// Pinned because it is a *consequence*, and consequences are what a later edit
  /// silently breaks: changing either token alone would move it.
  @Test func ctaLabelContrastSurvivesTheAppearanceFlip() {
    let light = contrastRatio(PasturaPalette.screenBackground, PasturaPalette.mossInk)
    let dark = contrastRatio(PasturaPalette.nightBackground, PasturaPalette.nightMossInk)
    #expect(abs(light - dark) < 0.05)
    #expect(light > 10.0)
  }

  /// `nightInkOnAccent` is the same hex as `nightBubble`, exactly as light's
  /// `inkOnAccent` is the same hex as `bubbleBackground`. **The equality is a
  /// consequence, not the reason**: the value was placed to clear WCAG AAA over
  /// `nightMossDark`, and slice 3's rule licenses carrying a coincidence only
  /// when both tokens keep the same job — a foreground and a surface do not.
  ///
  /// Pinned for two reasons. A reader finding two identical hexes would otherwise
  /// reasonably collapse them; and `tokens.css`'s mirror gate is a substring
  /// match on the hex, so `--night-ink-on-accent`'s row can be deleted with the
  /// job still exiting 0 — the same blindness ADR-028 recorded for slice 2's
  /// three coincidences. This test is what stands in for that gate.
  @Test func nightInkOnAccentIntentionallyMatchesNightBubble() {
    #expect(PasturaPalette.nightInkOnAccent == PasturaPalette.nightBubble)
  }

  /// `nightMossInk` and `nightMetaBaseL3` land within 1.002 of each other in
  /// contrast and are **not** to be merged. Arithmetic coincidence: the card sits
  /// 1.251 above the ground, so "8.16 on the card" (where §2.4 renders) and
  /// "10.19 on the ground" (where §2.3 renders) resolve to the same luminance.
  /// Light's pair is a clear 1.240 apart, so the convergence is a dark-side
  /// artifact rather than a drift.
  ///
  /// The discriminator is chroma, not luminance, so that is what is asserted —
  /// a luminance-only guard here would be indistinguishable from asserting they
  /// are the same token.
  @Test func nightMossInkConvergesWithNightMetaBaseL3OnlyInLuminance() {
    #expect(contrastRatio(PasturaPalette.nightMossInk, PasturaPalette.nightMetaBaseL3) < 1.01)
    #expect(PasturaPalette.nightMossInk != PasturaPalette.nightMetaBaseL3)
    // Chroma proxy: the moss token keeps a wider channel spread than the neutral
    // meta one. Asserted as a range rather than an exact HSL saturation so the
    // test does not smuggle in a colour-space conversion of its own.
    #expect(channelSpread(PasturaPalette.nightMossInk) > channelSpread(PasturaPalette.nightMetaBaseL3))
  }
}

// MARK: - Slice-4 predicates
//
// Pure functions, so each has a matched control above. Kept separate from the
// tests that use them for exactly that reason: a predicate inlined into its
// success case cannot be handed a broken input.

/// True when every token is strictly brighter than the one before it.
@MainActor
func isStrictlyBrightening(_ tokens: [PasturaColorValue]) -> Bool {
  zip(tokens, tokens.dropFirst()).allSatisfy { relativeLuminance($0) < relativeLuminance($1) }
}

/// True when an on-accent foreground clears WCAG's text bar (4.5:1) over the
/// emphatic fill AND the 1.4.11 non-text bar (3:1) over the base fill. Both bars
/// together are the contract §2.3 documents; either alone would pass a value
/// that fails in half the app.
@MainActor
func onAccentForegroundClearsItsBars(
  foreground: PasturaColorValue, emphaticFill: PasturaColorValue, baseFill: PasturaColorValue
) -> Bool {
  contrastRatio(foreground, emphaticFill) >= 4.5 && contrastRatio(foreground, baseFill) >= 3.0
}

/// True when a hairline is separable from the surface it is drawn on *and* from
/// the ground behind that surface. The second clause is the load-bearing one on a
/// dark palette: a line placed only against its own surface can land on top of
/// the ground and vanish at the card edge.
@MainActor
func lineSeparatesSurfaceFromGround(
  line: PasturaColorValue, surface: PasturaColorValue, ground: PasturaColorValue
) -> Bool {
  contrastRatio(line, surface) >= 1.1 && contrastRatio(line, ground) >= 1.1
}

/// The four §2.6 Ink-over-Soft badge pairs of one appearance.
@MainActor
func nightBadgePairs() -> [(ink: PasturaColorValue, soft: PasturaColorValue)] {
  [
    (PasturaPalette.nightInfoInk, PasturaPalette.nightInfoSoft),
    (PasturaPalette.nightSuccessInk, PasturaPalette.nightSuccessSoft),
    (PasturaPalette.nightWarningInk, PasturaPalette.nightWarningSoft),
    (PasturaPalette.nightDangerInk, PasturaPalette.nightDangerSoft)
  ]
}

/// True when `ink`-over-`soft` is quieter than every pair in `others`.
@MainActor
func isQuietestPair(
  ink: PasturaColorValue, soft: PasturaColorValue,
  others: [(ink: PasturaColorValue, soft: PasturaColorValue)]
) -> Bool {
  let subject = contrastRatio(ink, soft)
  return others.allSatisfy { subject < contrastRatio($0.ink, $0.soft) }
}

/// The moss badge against its appearance's own four §2.6 pairs.
@MainActor
func mossBadgeIsQuietest(dark: Bool) -> Bool {
  if dark {
    return isQuietestPair(
      ink: PasturaPalette.nightMossDark, soft: PasturaPalette.nightMossSoft,
      others: nightBadgePairs())
  }
  return isQuietestPair(
    ink: PasturaPalette.mossDark, soft: PasturaPalette.mossSoft,
    others: [
      (PasturaPalette.infoInk, PasturaPalette.infoSoft),
      (PasturaPalette.successInk, PasturaPalette.successSoft),
      (PasturaPalette.warningInk, PasturaPalette.warningSoft),
      (PasturaPalette.dangerInk, PasturaPalette.dangerSoft)
    ])
}

/// Max minus min sRGB channel — a chroma proxy that needs no colour-space
/// conversion. Used only to discriminate a moss token from a neutral one at the
/// same luminance.
@MainActor
func channelSpread(_ token: PasturaColorValue) -> Double {
  max(token.red, max(token.green, token.blue)) - min(token.red, min(token.green, token.blue))
}
