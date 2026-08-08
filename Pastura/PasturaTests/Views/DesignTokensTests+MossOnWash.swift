import SwiftUI
import Testing

@testable import Pastura

// Contrast guard for `mossOnWash` / `nightMossOnWash` (#1327).
//
// The token exists for one reason — moss-family label text over a translucent
// moss-family wash was below WCAG AA in light at all seven of its sites. That
// reason is a *measurement*, so it is asserted here rather than written into a
// doc comment and left to rot.
//
// Sibling-file extension of `DesignTokensTests` per `.claude/rules/testing.md`
// § "Splitting a Suite Across Files" — a fresh `@Suite` would run in parallel
// with the parent and is explicitly forbidden. Inherits the parent's
// `@MainActor` and `.timeLimit(.minutes(1))`, and reaches the `contrastRatio` /
// `composite` helpers at the foot of `DesignTokensTests+NightPalette.swift`,
// which are internal-not-private for exactly this reason.
extension DesignTokensTests {

  /// One row per shipped consumer: the wash token it fills with, and the alpha
  /// it fills at. Hand-written against the views rather than derived, so a view
  /// changing its opacity does **not** silently update the expectation — the
  /// row goes stale and a reviewer has to look.
  ///
  /// The category chip fills with `Color.selected`, which is `moss` with its
  /// alpha baked *into* the token — unrolled here into the underlying token plus
  /// an explicit alpha so every row composites the same way. Unrolling is also
  /// what makes its asymmetry visible: `nightSelected` re-bases 0.18 -> 0.24, so
  /// it is the only row whose two appearances differ, and that re-basing is why
  /// the chip was the one site already failing in **dark** before this token
  /// existed (4.39 — asserted by
  /// ``onlyTheCategoryChipWasFailingInDarkBeforeThisToken``, not just stated).
  static var mossWashSites: [MossWashSite] {
    [
      MossWashSite("GalleryCatalogRow.badgeView", wash: .moss, light: 0.20, dark: 0.20),
      MossWashSite("GalleryCatalogRow.categoryChip", wash: .moss, light: 0.18, dark: 0.24),
      MossWashSite("PhaseTypeLabel", wash: .moss, light: 0.15, dark: 0.15),
      MossWashSite("ModelRow.recommendedTag", wash: .moss, light: 0.12, dark: 0.12),
      MossWashSite("HomePausedCard.eyebrow", wash: .moss, light: 0.16, dark: 0.16),
      MossWashSite("PhaseEditorSheet.fieldPill", wash: .mossDark, light: 0.16, dark: 0.16),
      MossWashSite(
        "GalleryHighlightRunFigure.recordedPill", wash: .mossDark, light: 0.14, dark: 0.14)
    ]
  }

  /// WCAG 1.4.3 normal-text bar. Every one of these labels is under the
  /// "large text" threshold (≥14pt bold / ≥18pt regular) — the largest is
  /// `caption2.bold` at ~11pt — so 3:1 never applies to any of them.
  private static let textBar = 4.5

  /// The grounds are deliberately the **worst case per appearance**, not the
  /// per-site truth: these washes sit on either the card (`bubbleBackground` /
  /// `nightBubble`) or the screen (`screenBackground` / `nightBackground`), and
  /// for dark-on-light the darker ground is the harder one, while for
  /// light-on-dark the lighter ground is. Pinning the harder one each way keeps
  /// the assertion valid wherever a site actually sits, and keeps it from
  /// encoding a per-site ground that a layout change could quietly invalidate.
  ///
  /// The cost is that this cannot catch a *new* site placed on a ground outside
  /// that pair. Nothing here detects one; the enumeration above is the guard,
  /// and it is hand-maintained.
  @Test func mossOnWashClearsAAOnEveryWashItIsUsedOn() {
    // Size pin, not decoration: the body below is a bare loop over a
    // hand-maintained fixture, so trimming or emptying `mossWashSites` would
    // make this arm pass **vacuously** and green would mean nothing. The
    // negative control has its two non-loop ceiling assertions as a floor;
    // this arm had none.
    #expect(Self.mossWashSites.count == 7)

    for site in Self.mossWashSites {
      let lightGround = composite(
        site.lightToken, over: PasturaPalette.screenBackground, alpha: site.lightAlpha)
      let light = contrastRatio(PasturaPalette.mossOnWash, lightGround)
      #expect(light >= Self.textBar, "light \(site.name): \(light)")

      let darkGround = composite(
        site.darkToken, over: PasturaPalette.nightBubble, alpha: site.darkAlpha)
      let dark = contrastRatio(PasturaPalette.nightMossOnWash, darkGround)
      #expect(dark >= Self.textBar, "dark \(site.name): \(dark)")
    }
  }

  /// The negative control, and the whole reason the token exists.
  ///
  /// A guard's passing case proves nothing on its own — this arm constructs the
  /// state the guard above claims to catch and confirms it *does* fail the bar.
  /// If this ever passes, one of two things moved: `mossDark` was retuned, or
  /// the wash was. Either way `mossOnWash`'s justification has to be re-derived
  /// before this test is "fixed" — do not simply flip the comparison.
  ///
  /// The shape that rules out the cheaper answer, and it is a **pair** of facts,
  /// not one: `mossDark`'s ceiling — the alpha→0 limit, i.e. the bare token on
  /// the lightest ground in the palette — *clears* the bar at 4.737, and yet
  /// every wash the app actually renders puts it under. So "just lighten the
  /// wash" has no solution short of erasing the capsule, which is why this was
  /// answered with a new token.
  ///
  /// Asserting only the sub-AA half would leave the reader thinking `mossDark`
  /// is simply too light, and invite exactly the wash-tuning attempt that cannot
  /// work. Both halves have to be pinned for the conclusion to survive.
  @Test func mossDarkCannotClearTheBarOnAnyOfThoseWashes() {
    for site in Self.mossWashSites {
      let ground = composite(
        site.lightToken, over: PasturaPalette.screenBackground, alpha: site.lightAlpha)
      let ratio = contrastRatio(PasturaPalette.mossDark, ground)
      #expect(ratio < Self.textBar, "expected sub-AA for \(site.name), got \(ratio)")
    }

    let ceiling = contrastRatio(PasturaPalette.mossDark, PasturaPalette.bubbleBackground)
    #expect(ceiling >= Self.textBar, "mossDark's ceiling moved below the bar: \(ceiling)")
    #expect(ceiling < 5.0, "mossDark got materially darker: \(ceiling)")
  }

  /// The dark-side negative control, and it is deliberately **one row, not
  /// seven**.
  ///
  /// The claim it defends is narrow: dark was not broken in general — the
  /// gallery category chip was the single site already under the bar there,
  /// because `nightSelected` re-bases the wash alpha 0.18 -> 0.24 and lightens
  /// its ground. That claim is asserted in prose in three places (this file's
  /// fixture doc, `nightMossOnWash`'s doc comment, and ADR-028 § Amendment
  /// 2026-08-08) and was executed by nothing until this test.
  ///
  /// A blanket dark control over all seven would **fail**: the other six give
  /// `nightMossDark` 4.77–5.62, i.e. they pass. Widening this loop would
  /// therefore not strengthen the guard, it would break it — which is the
  /// tell that the chip-scoping is the claim, not a shortcut.
  @Test func onlyTheCategoryChipWasFailingInDarkBeforeThisToken() {
    let chipGround = composite(
      PasturaPalette.nightMoss, over: PasturaPalette.nightBubble, alpha: 0.24)
    let before = contrastRatio(PasturaPalette.nightMossDark, chipGround)
    #expect(before < Self.textBar, "the chip is supposed to be the dark failure: \(before)")

    // The paired positive: the same ground clears the bar once the label moves.
    let after = contrastRatio(PasturaPalette.nightMossOnWash, chipGround)
    #expect(after >= Self.textBar, "chip still under the bar in dark: \(after)")

    // ...and the six others were NOT failing, so "dark was broken" would be the
    // wrong story to tell about this change.
    for site in Self.mossWashSites where site.name != "GalleryCatalogRow.categoryChip" {
      let ground = composite(
        site.darkToken, over: PasturaPalette.nightBubble, alpha: site.darkAlpha)
      let ratio = contrastRatio(PasturaPalette.nightMossDark, ground)
      #expect(ratio >= Self.textBar, "expected dark-passing for \(site.name), got \(ratio)")
    }
  }

  /// `mossOnWash` is a role token, not a fifth rung — but it still has to sit
  /// *between* the two ladder steps it was derived from, in both appearances.
  /// If a later retune of `mossDark` or `mossInk` crosses it, the §2.3 prose
  /// describing where it sits stops being true.
  @Test func mossOnWashSitsBetweenMossDarkAndMossInk() {
    let light = relativeLuminance(PasturaPalette.mossOnWash)
    #expect(light < relativeLuminance(PasturaPalette.mossDark))
    #expect(light > relativeLuminance(PasturaPalette.mossInk))

    // Dark inverts: the §2.3 family runs soft < moss < dark < ink by luminance
    // there, so the emphatic half is the *brighter* one.
    let dark = relativeLuminance(PasturaPalette.nightMossOnWash)
    #expect(dark > relativeLuminance(PasturaPalette.nightMossDark))
    #expect(dark < relativeLuminance(PasturaPalette.nightMossInk))
  }
}

// MARK: - Helpers

/// One shipped consumer of the moss wash: which token fills its capsule, and at
/// what alpha in each appearance.
///
/// A struct rather than a tuple because swiftlint's `large_tuple` caps tuples at
/// two members and this row needs four — the fifth field (the dark token) is
/// derived from `wash` rather than stored, since the light and dark halves of a
/// wash are always a registered §2.9 pair.
///
/// File scope per `.claude/rules/testing.md` § "Splitting a Suite Across Files":
/// helpers in a sibling file live outside the suite struct.
struct MossWashSite {

  /// Which token the capsule is filled with. Only two occur across the seven
  /// sites — most fill with base `moss`, while `fieldPill` and `recordedPill`
  /// tint with `mossDark` itself.
  enum Wash {
    case moss
    case mossDark
  }

  let name: String
  let wash: Wash
  let lightAlpha: Double
  let darkAlpha: Double

  init(_ name: String, wash: Wash, light: Double, dark: Double) {
    self.name = name
    self.wash = wash
    self.lightAlpha = light
    self.darkAlpha = dark
  }

  /// `@MainActor` for the reason in `.claude/rules/swift-isolation.md` Pattern 5
  /// § "Cross-module corollary": the `let`-read exemption for a global-actor
  /// type's immutable storage is module-local, and this is the test module.
  @MainActor var lightToken: PasturaColorValue {
    switch wash {
    case .moss: PasturaPalette.moss
    case .mossDark: PasturaPalette.mossDark
    }
  }

  /// The registered §2.9 dark half of ``lightToken``.
  @MainActor var darkToken: PasturaColorValue {
    switch wash {
    case .moss: PasturaPalette.nightMoss
    case .mossDark: PasturaPalette.nightMossDark
    }
  }
}
