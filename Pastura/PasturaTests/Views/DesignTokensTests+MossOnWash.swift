import SwiftUI
import Testing

@testable import Pastura

// Contrast guard for `mossOnWash` / `nightMossOnWash` (#1327).
//
// The token exists for one reason — moss-family label text over a translucent
// moss-family wash was below WCAG AA in light at every site that read it. That
// reason is a *measurement*, so it is asserted here rather than written into a
// doc comment and left to rot.
//
// The fixture grows as sites adopt the token (#1327 enumerated the original
// set; #1455 added the `GameHeader` status pill on the same grounds). The count
// pin inside ``mossOnWashClearsAAOnEveryWashItIsUsedOn`` is the authority on its
// size — not restated as a number in prose here, because a prose count goes
// stale.
//
// **That origin says why the token exists; it is not a property every row
// shares.** #1459 added `HomePausedCard.progress` on **routing** grounds — it
// read `mossInk` and cleared at 8.807 light, but §2.3 gives the Ink step no
// round-readout role — so it is the first member that was not already failing.
// Nothing below can tell the two motives apart: ``MossWashSite`` records the
// wash, its alphas and the label's type size, and none of those is why a row
// joined. So do not read a row as evidence that its site was once sub-AA. The
// type size is the one property of a label the fixture does observe (#1468),
// and it observes it as an **admission criterion** — the reason `textBar` is
// 4.5 — not as a motive.
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
  ///
  /// `HomePausedCard`'s two rows are **identical under every arm** — same card,
  /// same gradient, same 0.16 pin — so they recompute the same pairs twice and
  /// discriminate nothing between them. That is the "one row per shipped
  /// consumer" contract working as intended, not an accidental duplicate: two
  /// labels ship on that ground and either could be retuned alone. A de-dup
  /// pass would redden the size pin without explaining why, so do not take one.
  ///
  /// `GameHeaderStatus.active` is **one row for three enum cases**: `.simulating`
  /// / `.demoing` / `.replaying` share a foreground and render through the one
  /// `GameHeader.statusPill`, so this is a single site, not three. The fourth
  /// moss arm, `.completed`, is that same pill on a different route and does not
  /// read this token at all — `DesignTokensTests+MossInkAsWashLabel.swift`
  /// guards it.
  ///
  /// That row is also the first whose true ground is **not** an opaque surface:
  /// `GameHeader` composites `screenBackground.opacity(0.78)` over
  /// `.ultraThinMaterial`, with the screen's content scrolling beneath. So for
  /// that row alone the ground pinned below is *nominal* rather than a worst
  /// case — dark enough content under the bar puts the real ratio below what
  /// this fixture asserts (#1455 measured the pathological bound at 3.690, still
  /// a large strict improvement on 1.604 before). Light-appearance device QA is
  /// what covers the gap; do not read this row as a bound the way the others are.
  static var mossWashSites: [MossWashSite] {
    [
      // `.caption2.bold()`
      MossWashSite(
        "GalleryCatalogRow.badgeView", wash: .moss, light: 0.20, dark: 0.20,
        pointSize: WashLabelSemanticSize.caption2, weight: .bold),
      // `.caption2.weight(.semibold)`
      MossWashSite(
        "GalleryCatalogRow.categoryChip", wash: .moss, light: 0.18, dark: 0.24,
        pointSize: WashLabelSemanticSize.caption2, weight: .semibold),
      // `.textStyle(Typography.tagPhase)`
      MossWashSite(
        "PhaseTypeLabel", wash: .moss, light: 0.15, dark: 0.15,
        pointSize: Double(Typography.tagPhase.size), weight: .semibold),
      // The one row whose view **inlines** its size rather than reading a token
      // — `.font(.system(size: 9.5, weight: .semibold, design: .monospaced))`.
      // `recommendedTagRowMatchesTheTokenItsViewDocClaimsToReuse` ties this
      // transcription to `tagPhase`, which is what that view's doc claims it
      // reuses.
      MossWashSite(
        "ModelRow.recommendedTag", wash: .moss, light: 0.12, dark: 0.12,
        pointSize: 9.5, weight: .semibold),
      // `.font(.system(size: HomeHeroLayout.eyebrowFontSize, weight: .semibold, …))`
      MossWashSite(
        "HomePausedCard.eyebrow", wash: .moss, light: 0.16, dark: 0.16,
        pointSize: Double(HomeHeroLayout.eyebrowFontSize), weight: .semibold),
      // `.font(.system(size: HomeHeroLayout.progressFontSize, design: .monospaced))`
      // — no `weight:`, so regular. The largest row in the fixture, and the one
      // whose 12pt falsified `textBar`'s old superlative (#1466).
      MossWashSite(
        "HomePausedCard.progress", wash: .moss, light: 0.16, dark: 0.16,
        pointSize: Double(HomeHeroLayout.progressFontSize), weight: .regular),
      // `.caption2.weight(.semibold)` — one helper serves this and the ink
      // fixture's row of the same name, so the two genuinely share a font.
      MossWashSite(
        "PhaseEditorSheet.fieldPill", wash: .mossDark, light: 0.16, dark: 0.16,
        pointSize: WashLabelSemanticSize.caption2, weight: .semibold),
      // `.textStyle(Typography.pillStatus)`
      MossWashSite(
        "GalleryHighlightRunFigure.recordedPill", wash: .mossDark, light: 0.14, dark: 0.14,
        pointSize: Double(Typography.pillStatus.size), weight: .semibold),
      // `.textStyle(Typography.pillStatus)`, via `GameHeader.statusPill`
      MossWashSite(
        "GameHeaderStatus.active", wash: .moss, light: 0.14, dark: 0.14,
        pointSize: Double(Typography.pillStatus.size), weight: .semibold)
    ]
  }

  /// WCAG 1.4.3 normal-text bar, and it is the right bar only because every
  /// label in the fixture is under the "large text" threshold at the default
  /// content size.
  ///
  /// That is now a **guard rather than a convention** (#1468): each row carries
  /// its point size and weight, and
  /// ``mossOnWashClearsAAOnEveryWashItIsUsedOn`` rejects a row that is large
  /// text before it applies this bar to it. ``WashLabelWeight`` owns the
  /// threshold and the `.semibold` half; a large-text row is *excluded*, not
  /// relaxed to 3:1, because no site in this family is meant to be one.
  ///
  /// **No superlative is restated here.** The rows are the authority on which
  /// is largest, and a prose extreme is precisely the mirror that went stale in
  /// #1466 — it survived until a 12pt row falsified it, and a second claim
  /// citing it from `+InkOnWash.swift` died at the same moment.
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
    #expect(Self.mossWashSites.count == 9)

    for site in Self.mossWashSites {
      // The admission criterion, applied before the bar it licenses: `textBar`
      // is 4.5 rather than 3.0 only because this label is WCAG normal text. A
      // large-text row would answer to 3:1, and until #1468 nothing observed
      // the difference — the row type stored no font.
      #expect(
        site.isNormalText,
        "\(largeTextRejection(site.name, pointSize: site.pointSize, weight: site.weight))")

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

  /// `ModelRow.recommendedTag` is the only row whose point size is a literal:
  /// its view inlines `.system(size: 9.5, …)` instead of reading a token, so the
  /// fixture has nothing to reference live. What that view's own doc comment
  /// claims is that the tag "reuses the existing `tagPhase` typography token",
  /// which is why the fixture's transcription is 9.5 rather than some other
  /// number.
  ///
  /// **What this observes is the fixture's transcription against the token —
  /// not the view.** A red means `tagPhase` moved and the row did not, which is
  /// the cue to open `ModelRow` and decide whether the tag was meant to follow;
  /// fix the view (or its doc comment) before the row, since updating the
  /// literal alone would restore the arithmetic while leaving that doc lying.
  ///
  /// **Residual**: the view's own literal is read by nothing here. Retype it as
  /// 11 without touching the fixture and this stays green — the
  /// hand-transcription hazard ``MossWashSite/pointSize`` admits is caught by
  /// nothing, and this arm narrows it rather than closing it.
  @Test func recommendedTagRowMatchesTheTokenItsViewDocClaimsToReuse() {
    let tag = Self.mossWashSites.first { $0.name == "ModelRow.recommendedTag" }
    #expect(tag?.pointSize == Double(Typography.tagPhase.size))
    #expect(tag?.weight == .semibold)
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
  ///
  /// **For `HomePausedCard.progress` this loop is a counterfactual, not a
  /// history** — that row never read `mossDark` (header has why). Still the
  /// right guard; just not evidence that this site was ever failing.
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

  /// The dark-side negative control, and it is deliberately **one row, not the
  /// whole fixture**.
  ///
  /// The claim it defends is narrow: dark was not broken in general — the
  /// gallery category chip was the single site already under the bar there,
  /// because `nightSelected` re-bases the wash alpha 0.18 -> 0.24 and lightens
  /// its ground. That claim is asserted in prose in three places (this file's
  /// fixture doc, `nightMossOnWash`'s doc comment, and ADR-028 § Amendment
  /// 2026-08-08) and was executed by nothing until this test.
  ///
  /// A blanket dark control over the whole fixture would **fail**: every other
  /// row gives `nightMossDark` 4.77–5.62, i.e. they pass. Widening this loop
  /// would therefore not strengthen the guard, it would break it — which is the
  /// tell that the chip-scoping is the claim, not a shortcut. The range has
  /// survived every row added since — #1455's at 5.397, and #1459's at 5.180,
  /// which is **not** fresh evidence: that value was already in the set as
  /// `HomePausedCard.eyebrow`'s, the row it duplicates. So only the membership
  /// moved.
  @Test func onlyTheCategoryChipWasFailingInDarkBeforeThisToken() {
    let chipGround = composite(
      PasturaPalette.nightMoss, over: PasturaPalette.nightBubble, alpha: 0.24)
    let before = contrastRatio(PasturaPalette.nightMossDark, chipGround)
    #expect(before < Self.textBar, "the chip is supposed to be the dark failure: \(before)")

    // The paired positive: the same ground clears the bar once the label moves.
    let after = contrastRatio(PasturaPalette.nightMossOnWash, chipGround)
    #expect(after >= Self.textBar, "chip still under the bar in dark: \(after)")

    // ...and the rest of the fixture was NOT failing, so "dark was broken" would
    // be the wrong story to tell about this change. Deliberately uncounted: the
    // number that stood here went stale as rows were added, and the size pin is
    // the authority on it.
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

/// One shipped consumer of the moss wash: which token fills its capsule, at
/// what alpha in each appearance, and the type size of the label on it.
///
/// A struct rather than a tuple because swiftlint's `large_tuple` caps tuples at
/// two members and this row needs six — the dark token stays **derived** from
/// `wash` rather than stored, since the light and dark halves of a wash are
/// always a registered §2.9 pair.
///
/// File scope per `.claude/rules/testing.md` § "Splitting a Suite Across Files":
/// helpers in a sibling file live outside the suite struct.
struct MossWashSite {

  /// Which token the capsule is filled with. Only two occur across the fixtures
  /// this type backs — most fill with base `moss`, while `fieldPill`,
  /// `recordedPill` and (in `mossInkWashSites`) `GameHeader.statusPill` tint
  /// with `mossDark` itself.
  enum Wash {
    case moss
    case mossDark
  }

  let name: String
  let wash: Wash
  let lightAlpha: Double
  let darkAlpha: Double

  /// The label's point size at the default `.large` content size.
  ///
  /// **Two regimes share this field**, and the split is fixed-size vs scaling
  /// rather than which expression the view wrote.
  ///
  /// *Fixed size* covers every `.system(size:)` label — whether it comes from a
  /// `Typography.*` token (referenced live via the token's `size`, and
  /// fixed-size by design per ``PasturaTextStyle/font``), from a layout constant
  /// read live (`HomeHeroLayout.*FontSize`), or from a literal the view inlines.
  /// For those the value is the size at every content size.
  ///
  /// *Scaling* covers the semantic SwiftUI fonts (`.caption` / `.caption2`),
  /// which name a ``WashLabelSemanticSize`` constant: that is the size **at the
  /// default**, and at accessibility sizes such a label crosses into large text
  /// — which only **relaxes** the bar the fixture applies. So this field decides
  /// admission at the default and nothing else.
  ///
  /// **Hand-recorded against the view, and a wrong transcription is caught by
  /// nothing.** Live references and
  /// ``DesignTokensTests/semanticLabelSizesMatchUIKitAtTheDefaultContentSize``
  /// remove the guesswork from every figure that has a source, but which figure
  /// a row *takes* is still a reader's judgement — same standing as the grounds
  /// the arms below pin. A reviewer has to open the view when a row is added.
  let pointSize: Double

  /// Which WCAG large-text half the label's weight selects — see
  /// ``WashLabelWeight`` for the `.semibold` decision.
  let weight: WashLabelWeight

  init(
    _ name: String, wash: Wash, light: Double, dark: Double, pointSize: Double,
    weight: WashLabelWeight
  ) {
    self.name = name
    self.wash = wash
    self.lightAlpha = light
    self.darkAlpha = dark
    self.pointSize = pointSize
    self.weight = weight
  }

  /// Whether this row's label is still WCAG **normal** text, i.e. whether the
  /// 4.5:1 bar the fixtures pin is the bar it actually answers to.
  ///
  /// Both parameters are required at construction, so a row cannot join a
  /// fixture without declaring a font — which is the half of #1466's failure
  /// this closes.
  var isNormalText: Bool { weight.admitsAsNormalText(pointSize: pointSize) }

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
