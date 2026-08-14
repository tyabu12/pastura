import SwiftUI
import Testing

@testable import Pastura

// Contrast guard for `mossInk` / `nightMossInk` used as a **label on a
// translucent moss-family wash** (#1455).
//
// **There is no `mossInkOnWash` token, and this file is not named for one.**
// Its siblings `+MossOnWash` and `+InkOnWash` are named after tokens that exist;
// this one is named after a *bug class* — the §2.3 Ink step painted over a
// translucent wash of its own family — because that is the set a future site
// joins, and a component name would have made the sibling rows below
// unaddable.
//
// Only one member was ever failing: `GameHeader`'s status pill read `mossDark`
// as both its label and its own wash (3.832 in light, under the 4.5:1 bar) until
// #1455 moved the label. The rest of the fixture already read `mossInk` and is
// here as a guard, not a repair — see ``theResultsPillIsEnumeratedNotRepaired``.
// The size pin is the authority on how many; this comment deliberately states no
// count, and is worded to stay true at any size.
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
  /// It reaches `ResultsView.completed` and `HomePausedCard` directly but
  /// **not** `GameHeader.statusPill`, which composes its wash through
  /// `GameHeaderStatus.washToken` — a starting point, not the guard. And
  /// **triaging its hits by the API that produced them is what misses a row**:
  /// `HomePausedCard`'s two build a `LinearGradient` and a first pass dropped
  /// them as "gradients" alongside the icon tiles and progress dots — but that
  /// gradient is the card's surface, and text sits on it (the eyebrow and the
  /// progress label). Ask what the wash is *under*, never which API drew it.
  ///
  /// The derivation stays here, with the bug class it was learned enumerating,
  /// even though **neither** `HomePausedCard` row now lives in this file — both
  /// are `mossWashSites` rows in `DesignTokensTests+MossOnWash.swift` (the
  /// eyebrow since #1327, the progress label since #1459). Both model the harder
  /// 0.16 stop rather than the 0.07 one.
  ///
  /// The rest is decided by criteria rather than a list, because the list keeps
  /// turning out incomplete — each time because a shape was excluded by how it
  /// was drawn rather than by what it carries:
  ///
  /// - **Large text is out** — ≥14pt bold / ≥18pt regular takes WCAG 1.4.11's
  ///   3:1, not this file's 4.5. `ModelPickerView`'s 26pt-bold `mossInk` title
  ///   over the `moss@0.10` halo is otherwise the same shape as a row here.
  /// - **Cross-family is out** — it belongs to whichever fixture owns the label's
  ///   family, not this one. Seen so far: `ActiveModelChip` (`inkSecondary` on
  ///   `mossDark@0.10`, worst 4.843 dark), `ResultDetailView+ResumeBanner` and
  ///   `ModelRow`'s selected row (both `ink` on a thin `moss` wash).
  /// - **A role-token label is out** even though it is same-family: this file is
  ///   about the §2.3 **Ink** step specifically, so `mossOnWash` labels are
  ///   `mossWashSites`' business. `ModelRow` supplies one of each — its selected
  ///   row above, and its `recommendedTag` here.
  ///
  /// Membership is a **contrast** class, not the set design-system §8's
  /// exception admits by role; this file does not certify the second. No row
  /// below is currently unjustified, but that is an outcome, not a property of
  /// the fixture — **a row landing here does not thereby become justified, and
  /// none of them is precedent for the next site.** §8's closing ⚠️ owns the
  /// per-row reasons (they differ, and do not generalise); do not restate them
  /// here, or the two copies drift.
  ///
  /// `HomePausedCard.progress` was the one divergence until #1459 repointed it
  /// to `mossOnWash`: it cleared the bar, yet "Round X / Y" is none of the roles
  /// §2.3 assigns `--moss-ink`. That is the shape a future row can take again.
  static var mossInkWashSites: [MossWashSite] {
    [
      MossWashSite("GameHeader.statusPill", wash: .mossDark, light: 0.14, dark: 0.14),
      MossWashSite("ResultsView.completed", wash: .moss, light: 0.16, dark: 0.16)
    ]
  }

  /// WCAG 1.4.3 normal-text bar. Every label in the fixture is under the "large
  /// text" threshold (≥14pt bold / ≥18pt regular) at default Dynamic Type — the
  /// status pill is `Typography.pillStatus` at 9pt and the results pill is
  /// `.caption` + `.semibold` at 12pt — so 3:1 never applies. That is
  /// the fixture's admission criterion, not an incidental property: a same-shaped
  /// site above the threshold is excluded (the large-text bullet above). Pinning
  /// 4.5 stays conservative at accessibility sizes for the reason `+InkOnWash`'s
  /// `inkTextBar` gives — do not "correct" it in the other direction.
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
    #expect(Self.mossInkWashSites.count == 2)

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
  /// `ResultsView.completed` has read `mossInk` on a moss wash since before
  /// #1455 and measures 8.807 light / 5.927 dark. It is enumerated because it is
  /// the same bug class — #1455 was filed precisely because the sibling fixture
  /// had *not* enumerated one of its members — not because anything is wrong
  /// with it. If a future reader concludes "every site was failing", this arm
  /// corrects them.
  ///
  /// It is the **exact complement** of the negative control above rather than a
  /// hand-listed pair, so the two arms cannot drift apart as the fixture grows.
  /// What the pins below state is narrower: exactly one row is excluded, and the
  /// complement is non-empty. A row *added* is caught by the size pin in
  /// ``mossInkClearsAAOnEveryMossWashItLabels``, not here — the two are
  /// complementary and neither subsumes the other.
  ///
  /// Both appearances are asserted — the light half duplicates that same arm,
  /// but the dark one is otherwise claimed only in prose.
  @Test func theResultsPillIsEnumeratedNotRepaired() {
    let alreadyPassing = Self.mossInkWashSites.filter { $0.name != "GameHeader.statusPill" }
    #expect(alreadyPassing.count == Self.mossInkWashSites.count - 1)
    // `count - 1` alone is satisfied by an empty complement (0 == 0) if the
    // fixture were ever trimmed to the status pill, and the loop below would
    // then run zero times. This is what bars that.
    #expect(!alreadyPassing.isEmpty)

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
  /// Both halves are pinned because either alone misleads: the `moss` one
  /// suggests the completed arm could have been tuned, the `mossDark` one that
  /// wash-tuning was viable in general. Do not "fix" a red here by flipping a
  /// comparison — re-derive the decision (design-system §8, ADR-028) first.
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
  /// the pill does not out-shout the row's primary. The arm computes both
  /// appearances rather than mirroring the figures §8 and the ADR quote.
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
