import SwiftUI
import Testing

@testable import Pastura

// Contrast guard for `mossInk` / `nightMossInk` used as a **label on a
// translucent moss-family wash** (#1455).
//
// **There is no `mossInkOnWash` token, and this file is not named for one.**
// Its siblings `+MossOnWash` and `+InkOnWash` are named after tokens that
// exist; this one is named after a *bug class* — the §2.3 Ink step painted over
// a translucent wash of its own family — because that is the set a future site
// joins. Naming it for a component would have made the sibling below
// unaddable.
//
// Only one member was ever failing: `GameHeader`'s status pill read `mossDark`
// as both its label and its own wash (3.832 in light, under the 4.5:1 bar) until
// #1455 moved the label. The others already read `mossInk` and are here as
// guards, not repairs — see ``theResultsPillIsEnumeratedNotRepaired``. The size
// pin is the authority on how many; this comment deliberately states no count.
//
// Sibling-file extension of `DesignTokensTests` per `.claude/rules/testing.md`
// § "Splitting a Suite Across Files" — a fresh `@Suite` would run in parallel
// with the parent and is explicitly forbidden. Inherits the parent's
// `@MainActor` and `.timeLimit(.minutes(1))`, and reaches the `contrastRatio` /
// `composite` helpers at the foot of `DesignTokensTests+NightPalette.swift`.
extension DesignTokensTests {

  /// One row per shipped site painting `mossInk` on a translucent moss-family
  /// wash. Hand-written against the views rather than derived, so a view
  /// changing its opacity does **not** silently update the expectation — the row
  /// goes stale and a reviewer has to look.
  ///
  /// Reuses ``MossWashSite`` rather than declaring a near-identical row type:
  /// the two fixtures ask different questions of the same shape (which wash
  /// token, at which alpha, per appearance). Neither row re-bases its alpha
  /// between appearances, unlike `mossWashSites`' category-chip row.
  ///
  /// The rows are what a sweep of the moss-family translucent washes leaves once
  /// the genuinely non-text fills are dropped:
  ///
  /// ```sh
  /// rg 'Color\.moss(Dark)?\.opacity\(' Pastura/Pastura/ --type swift
  /// ```
  ///
  /// That reaches `ResultsView.completed` and `HomePausedCard` directly but
  /// **not** `GameHeader.statusPill`, which composes its wash through
  /// `GameHeaderStatus.washToken` — so the grep is a starting point, not the
  /// guard.
  ///
  /// **Triaging its remaining hits by the API that produced them is what misses
  /// a row.** `HomePausedCard`'s two hits build a `LinearGradient`, and a first
  /// pass here dropped them as "gradients" alongside the icon tiles and progress
  /// dots — but that gradient is the card's surface, and text sits on it: the
  /// eyebrow (already a `mossWashSites` row) and the progress label below. The
  /// question is what the wash is *under*, never which API drew it. Both text
  /// rows model the harder 0.16 stop rather than the 0.07 one.
  ///
  /// Two neighbours are enumerated and excluded, both **cross-family** and both
  /// clearing comfortably, so the next reader does not re-derive them:
  /// `ActiveModelChip` (`inkSecondary` on a `mossDark@0.10` wash, worst 4.843 in
  /// dark) and `ResultDetailView+ResumeBanner` (`ink` on a `moss@0.08` wash).
  static var mossInkWashSites: [MossWashSite] {
    [
      MossWashSite("GameHeader.statusPill", wash: .mossDark, light: 0.14, dark: 0.14),
      MossWashSite("ResultsView.completed", wash: .moss, light: 0.16, dark: 0.16),
      MossWashSite("HomePausedCard.progress", wash: .moss, light: 0.16, dark: 0.16)
    ]
  }

  /// WCAG 1.4.3 normal-text bar. Both labels are under the "large text"
  /// threshold (≥14pt bold / ≥18pt regular) at default Dynamic Type — the
  /// status pill is `Typography.pillStatus` at 9pt and the results pill is
  /// `.caption` + `.semibold`, i.e. 12pt — so 3:1 never applies. At
  /// accessibility sizes `.caption` scales past 14pt and the 3:1 bar *would*
  /// apply, which only relaxes the requirement, so pinning 4.5 stays
  /// conservative. Do not "correct" this in the other direction.
  private static let mossInkTextBar = 4.5

  /// Grounds are the **worst case per appearance** — the convention
  /// `DesignTokensTests+MossOnWash.swift` established. These washes sit on
  /// either the card (`bubbleBackground` / `nightBubble`) or the screen
  /// (`screenBackground` / `nightBackground`); for dark-on-light the darker
  /// ground is the harder one and for light-on-dark the lighter one is.
  ///
  /// The status-pill row carries the same caveat its `mossWashSites` sibling
  /// does: `GameHeader`'s real ground is a translucent material bar over
  /// scrolling content, so for that row this is a nominal ground rather than a
  /// bound. It clears the bar by a wide enough margin (8.604 light) that the
  /// pathological case still measures 5.347.
  @Test func mossInkClearsAAOnEveryMossWashItLabels() {
    // Size pin, not decoration: the body below is a bare loop over a
    // hand-maintained fixture, so trimming or emptying `mossInkWashSites` would
    // make this arm pass **vacuously** and green would mean nothing.
    #expect(Self.mossInkWashSites.count == 3)

    for site in Self.mossInkWashSites {
      let lightGround = composite(
        site.lightToken, over: PasturaPalette.screenBackground, alpha: site.lightAlpha)
      let light = contrastRatio(PasturaPalette.mossInk, lightGround)
      #expect(light >= Self.mossInkTextBar, "light \(site.name): \(light)")

      let darkGround = composite(
        site.darkToken, over: PasturaPalette.nightBubble, alpha: site.darkAlpha)
      let dark = contrastRatio(PasturaPalette.nightMossInk, darkGround)
      #expect(dark >= Self.mossInkTextBar, "dark \(site.name): \(dark)")
    }
  }

  /// The negative control, and the whole reason `.completed` moved.
  ///
  /// A guard's passing case proves nothing on its own — this arm constructs the
  /// state the guard above claims to catch: the status pill's **previous**
  /// label, `mossDark`, painted on the very wash it also filled. It is
  /// deliberately scoped to **that one row**; the other rows never read a
  /// failing token, so a blanket control over the fixture would fail. That the
  /// scoping is the claim rather than a shortcut is what
  /// ``theResultsPillIsEnumeratedNotRepaired`` asserts from the other side.
  @Test func onlyTheStatusPillWasFailingBeforeThisChange() {
    // The exclusion is keyed on a **name string**, so renaming or replacing that
    // row would leave the filter matching nothing and this loop silently
    // covering neither site. Pinning the filtered size is what makes the
    // exclusion falsifiable.
    let failing = Self.mossInkWashSites.filter { $0.name == "GameHeader.statusPill" }
    #expect(failing.count == 1)

    for site in failing {
      let ground = composite(
        site.lightToken, over: PasturaPalette.screenBackground, alpha: site.lightAlpha)
      let before = contrastRatio(PasturaPalette.mossDark, ground)
      #expect(before < Self.mossInkTextBar, "expected sub-AA before for \(site.name): \(before)")

      // The paired positive: the same ground clears the bar once the label moves.
      let after = contrastRatio(PasturaPalette.mossInk, ground)
      #expect(after >= Self.mossInkTextBar, "still under the bar after: \(after)")
    }
  }

  /// Executes the "guarded, not repaired" half, which the negative control above
  /// has to leave out.
  ///
  /// `ResultsView.completed` and `HomePausedCard.progress` have read `mossInk`
  /// on a moss wash since before #1455 and measure 8.807 light / 5.927 dark —
  /// identical, because they share a wash token and an alpha. They are
  /// enumerated because they are the same bug class — #1455 was filed precisely
  /// because the sibling fixture had *not* enumerated one of its members — not
  /// because anything is wrong with them. If a future reader concludes "every
  /// site was failing", this arm corrects them.
  ///
  /// It is the **exact complement** of the negative control above rather than a
  /// hand-listed pair, so the two arms cannot drift apart as the fixture grows:
  /// a row added and left out of both would redden the size pin here. Both
  /// appearances are asserted — the light half duplicates
  /// ``mossInkClearsAAOnEveryMossWashItLabels``, but the dark one is otherwise
  /// claimed only in prose.
  @Test func theResultsPillIsEnumeratedNotRepaired() {
    let alreadyPassing = Self.mossInkWashSites.filter { $0.name != "GameHeader.statusPill" }
    #expect(alreadyPassing.count == Self.mossInkWashSites.count - 1)

    for site in alreadyPassing {
      let lightGround = composite(
        site.lightToken, over: PasturaPalette.screenBackground, alpha: site.lightAlpha)
      #expect(
        contrastRatio(PasturaPalette.mossInk, lightGround) >= Self.mossInkTextBar,
        "\(site.name) is supposed to have been passing all along (light)")

      let darkGround = composite(
        site.darkToken, over: PasturaPalette.nightBubble, alpha: site.darkAlpha)
      #expect(
        contrastRatio(PasturaPalette.nightMossInk, darkGround) >= Self.mossInkTextBar,
        "\(site.name) is supposed to have been passing all along (dark)")
    }
  }

  /// Rules out the cheap answer, and it is a **pair** of facts, not one.
  ///
  /// #1455 weighed "just raise the wash alpha so the existing labels clear the
  /// bar" against repointing them. For the pill's active arm that has **no
  /// solution at all**: `moss`'s alpha→0 limit — the bare token on the lightest
  /// ground, i.e. the capsule erased entirely — is 2.908, already under the bar.
  /// For `.completed`, `mossDark`'s limit is 4.538, so it clears *only* in that
  /// same degenerate limit and every alpha the design would actually ship puts
  /// it under.
  ///
  /// `DesignTokensTests+MossOnWash` and ADR-028 § "Why not `mossInk`" call that
  /// same limit **4.737** — the identical alpha→0 ceiling measured on
  /// `bubbleBackground` (pure white) rather than `screenBackground`. Both are
  /// right and neither should be edited to match the other; the ground is what
  /// separates them, and this file uses `screenBackground` because that is the
  /// light worst case its fixture composites over.
  ///
  /// Asserting only the `moss` half would leave a reader thinking the completed
  /// arm could have been tuned; asserting only the `mossDark` half would suggest
  /// wash-tuning was viable in general. Both have to be pinned for the
  /// conclusion to survive. Do not "fix" a red here by flipping a comparison —
  /// re-derive the decision (design-system §8, ADR-028) first.
  @Test func washAlphaTuningCouldNotHaveRepairedThisPill() {
    let activeCeiling = contrastRatio(PasturaPalette.moss, PasturaPalette.screenBackground)
    #expect(
      activeCeiling < Self.mossInkTextBar,
      "moss is supposed to be unfixable by wash tuning: \(activeCeiling)")

    let completedCeiling = contrastRatio(PasturaPalette.mossDark, PasturaPalette.screenBackground)
    #expect(
      completedCeiling >= Self.mossInkTextBar,
      "mossDark's ceiling moved below the bar: \(completedCeiling)")
    #expect(completedCeiling < 5.0, "mossDark got materially darker: \(completedCeiling)")
  }

  /// The load-bearing condition of the design-system §8 exception, which nothing
  /// executed before this arm.
  ///
  /// ADR-028 § "Why not `mossInk`, when a shipped pill already uses it on a moss
  /// wash" rejects `mossInk` as an on-wash label **on hierarchy grounds** — a
  /// supporting element must not become the loudest thing in its row. §8's
  /// exception for `GameHeaderStatus.completed` is only sound while that
  /// condition holds *here*: the header's own title out-contrasts the pill, so
  /// the pill does not out-shout the row's primary. Today 13.147 vs 8.604 in
  /// light and 10.769 vs 6.047 in dark.
  ///
  /// A red here is a **decision point, not a repair instruction**: it means a
  /// retune inverted the relation the exception rests on, and §8 has to be
  /// re-derived before this expectation is updated.
  @Test func theCompletedPillDoesNotOutShoutTheHeaderTitle() {
    let pillWashLight = composite(
      PasturaPalette.mossDark, over: PasturaPalette.screenBackground,
      alpha: GameHeaderStatus.washAlpha)
    let titleLight = contrastRatio(PasturaPalette.ink, PasturaPalette.screenBackground)
    let pillLight = contrastRatio(PasturaPalette.mossInk, pillWashLight)
    #expect(titleLight > pillLight, "light: title \(titleLight) vs pill \(pillLight)")

    let pillWashDark = composite(
      PasturaPalette.nightMossDark, over: PasturaPalette.nightBubble,
      alpha: GameHeaderStatus.washAlpha)
    let titleDark = contrastRatio(PasturaPalette.nightInk, PasturaPalette.nightBubble)
    let pillDark = contrastRatio(PasturaPalette.nightMossInk, pillWashDark)
    #expect(titleDark > pillDark, "dark: title \(titleDark) vs pill \(pillDark)")
  }
}
