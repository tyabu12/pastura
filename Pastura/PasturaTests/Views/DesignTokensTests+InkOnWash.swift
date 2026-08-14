import SwiftUI
import Testing

@testable import Pastura

// Contrast guard for `inkOnWash` / `nightInkOnWash` (#1408).
//
// The ink-family sibling of `DesignTokensTests+MossOnWash.swift`, and the
// **opposite asymmetry**: there the failure was in light and dark already
// passed; here `inkSecondary` painted as both label and its own translucent
// wash is at or below the 4.5:1 bar in *dark* while light clears comfortably.
// That is a measurement, so it is asserted rather than left in a doc comment
// to rot.
//
// Sibling-file extension of `DesignTokensTests` per `.claude/rules/testing.md`
// § "Splitting a Suite Across Files" — a fresh `@Suite` would run in parallel
// with the parent and is explicitly forbidden. Inherits the parent's
// `@MainActor` and `.timeLimit(.minutes(1))`, and reaches the `contrastRatio` /
// `composite` / `relativeLuminance` helpers at the foot of
// `DesignTokensTests+NightPalette.swift`.
extension DesignTokensTests {

  /// One row per shipped **self-wash**: a site that paints `inkSecondary` as
  /// both the label and the capsule fill under it. Hand-written against the
  /// views rather than derived, so a view changing its opacity does **not**
  /// silently update the expectation — the row goes stale and a reviewer has to
  /// look.
  ///
  /// Hand-maintenance is not a convenience here, it is forced: three of the four
  /// compose the wash **indirectly** — `ScenarioBadgeStyle` through
  /// `fillToken` / `fillOpacity`, `PhaseTypeLabel` through `badgeFill`, and
  /// `fieldPill` through a `wash:` parameter the helper opacity-applies. So
  /// `rg 'Color\.inkSecondary\.opacity' Pastura/Pastura/` returns exactly **one**
  /// hit, and it is `ResultsView.pillBackground` — the only *direct* site, and the
  /// one that was not failing. Enumerating the bug class is what found the other
  /// three; nothing mechanical will find a fifth.
  static var inkWashSites: [InkWashSite] {
    [
      InkWashSite("PhaseEditorSheet.fieldPill", alpha: 0.16),
      InkWashSite("ScenarioBadgeStyle.secondary", alpha: 0.15),
      InkWashSite("PhaseTypeLabel", alpha: 0.15),
      InkWashSite("ResultsView.paused", alpha: 0.12)
    ]
  }

  /// WCAG 1.4.3 normal-text bar. Every one of these labels is under the "large
  /// text" threshold (≥14pt bold / ≥18pt regular) — the largest is
  /// `ResultsView`'s pill at `.caption` + `.semibold`, i.e. **12pt**, and the
  /// smallest is `PhaseTypeLabel` at `Typography.tagPhase`'s 9.5pt — so 3:1
  /// never applies to any of them at default Dynamic Type. At accessibility
  /// sizes `.caption` scales past 14pt and the large-text 3:1 bar *would* apply,
  /// which only **relaxes** the requirement — so pinning 4.5 stays conservative.
  /// Do not "correct" this in the other direction.
  ///
  /// **Re-derived here, not carried over from a sibling wash fixture.** Each
  /// fixture's site set is its own, so its largest label is its own question,
  /// and a figure cited from `+MossOnWash` / `+MossInkAsWashLabel` would be a
  /// cross-file mirror with nothing keeping it true. This paragraph used to be
  /// exactly that — it cited a `~11pt` superlative from `+MossOnWash`, which
  /// #1459 falsified by adding a 12pt row there. Do not reintroduce the
  /// comparison; state this fixture's own extreme and stop.
  private static let inkTextBar = 4.5

  /// "Clears the bar" and "has margin above it" are different claims, and this
  /// change is about the second. `ScenarioBadgeStyle.secondary` and
  /// `PhaseTypeLabel` measure **4.5010** today: green by arithmetic, one wash
  /// tweak from red. This band is what lets ``inkSecondaryHasNoMarginOnTheseWashes``
  /// state that without pretending they are already failing.
  ///
  /// **The value is derived, not fitted to the observed 4.5010.** On these
  /// washes the ratio moves ≈0.088 per 0.01 of wash alpha (0.16 → 4.4134,
  /// 0.15 → 4.5010). `inkTextBar + 0.05` is therefore "less than one alpha step
  /// of headroom" — the smallest change anyone would plausibly make to a wash is
  /// enough to cross it. Widening this to 4.6 would stop meaning that, so do not
  /// nudge it to accommodate a future measurement; re-derive it from the
  /// sensitivity if the wash alphas change.
  private static let inkMarginlessBand = inkTextBar + 0.05

  /// The wash alpha for a named fixture row, so an arm that needs one site's
  /// alpha cannot silently drift from the fixture the way a hardcoded literal
  /// would. Records an issue rather than defaulting: a missing name means the
  /// fixture was renamed and the caller is measuring nothing, and the returned
  /// `NaN` makes every downstream comparison false so the arm fails loudly.
  private static func inkWashAlpha(_ name: String) -> Double {
    guard let site = inkWashSites.first(where: { $0.name == name }) else {
      Issue.record("no inkWashSites row named \(name)")
      return .nan
    }
    return site.alpha
  }

  /// Grounds are the **worst case per appearance**, not the per-site truth —
  /// the convention `DesignTokensTests+MossOnWash.swift` established. These
  /// washes sit on either the card (`bubbleBackground` / `nightBubble`) or the
  /// screen (`screenBackground` / `nightBackground`); for dark-on-light the
  /// darker ground is the harder one, and for light-on-dark the lighter one is.
  /// Pinning the harder one each way keeps the assertion valid wherever a site
  /// actually sits.
  ///
  /// The cost is the same as there: this cannot catch a *new* site placed on a
  /// ground outside that pair. The enumeration above is the guard, and it is
  /// hand-maintained.
  @Test func inkOnWashClearsAAOnEverySelfWashItIsUsedOn() {
    // Size pin, not decoration: the body below is a bare loop over a
    // hand-maintained fixture, so trimming or emptying `inkWashSites` would make
    // this arm pass **vacuously** and green would mean nothing.
    #expect(Self.inkWashSites.count == 4)

    for site in Self.inkWashSites {
      let lightGround = composite(
        PasturaPalette.inkSecondary, over: PasturaPalette.screenBackground, alpha: site.alpha)
      let light = contrastRatio(PasturaPalette.inkOnWash, lightGround)
      #expect(light >= Self.inkTextBar, "light \(site.name): \(light)")

      let darkGround = composite(
        PasturaPalette.nightInkSecondary, over: PasturaPalette.nightBubble, alpha: site.alpha)
      let dark = contrastRatio(PasturaPalette.nightInkOnWash, darkGround)
      #expect(dark >= Self.inkTextBar, "dark \(site.name): \(dark)")
    }
  }

  /// The negative control, and the whole reason the token exists.
  ///
  /// A guard's passing case proves nothing on its own — this arm constructs the
  /// state the guard above claims to catch. It is deliberately **three rows, not
  /// four**: `ResultsView.paused` already clears the bar at 4.773 in dark, so a
  /// blanket control over all four would fail. That the scoping is the claim
  /// rather than a shortcut is what ``pausedPillGainsMarginRatherThanBeingRepaired``
  /// asserts from the other side.
  ///
  /// The claim is graded, because the sites are: `fieldPill` is **strictly
  /// under** the bar at 4.413, while the two 0.15 sites sit at 4.5010 — green
  /// by 0.001. Asserting only "under the bar" would have to drop those two and
  /// would lose the finding; asserting only "no margin" would understate
  /// `fieldPill`. Both are pinned.
  ///
  /// Paired with the wash-alpha **ceiling**, which does *not* have
  /// `mossOnWash`'s shape: there the ceiling sat under the bar, proving
  /// wash-tuning could not work at all. Here it is 5.975 — the lever exists and
  /// is cheap, and is rejected anyway on grounds this file cannot prove
  /// (**ADR-028 § Amendment 2026-08-13 (#1408)**). Do not read a passing ceiling
  /// assertion as endorsement of the route.
  @Test func inkSecondaryHasNoMarginOnTheseWashes() {
    // The exclusion is keyed on a **name string**, so renaming or replacing that
    // row would leave the filter matching nothing and this loop silently
    // covering all four — measured, not hypothesised: a probe that swapped the
    // row for a duplicate of another passed green with the filter inert. Pinning
    // the filtered size is what makes the exclusion falsifiable.
    let failing = Self.inkWashSites.filter { $0.name != "ResultsView.paused" }
    #expect(failing.count == 3)

    for site in failing {
      let ground = composite(
        PasturaPalette.nightInkSecondary, over: PasturaPalette.nightBubble, alpha: site.alpha)
      let ratio = contrastRatio(PasturaPalette.nightInkSecondary, ground)
      #expect(ratio < Self.inkMarginlessBand, "expected marginless for \(site.name), got \(ratio)")
    }

    let worst = composite(
      PasturaPalette.nightInkSecondary, over: PasturaPalette.nightBubble,
      alpha: Self.inkWashAlpha("PhaseEditorSheet.fieldPill"))
    #expect(
      contrastRatio(PasturaPalette.nightInkSecondary, worst) < Self.inkTextBar,
      "fieldPill is supposed to be the strictly-failing site")

    let ceiling = contrastRatio(PasturaPalette.nightInkSecondary, PasturaPalette.nightBubble)
    #expect(ceiling >= Self.inkTextBar, "the self-wash ceiling moved below the bar: \(ceiling)")
    // Headroom matched to the moss sibling's (~5.5%, 4.737 against a 5.0 cap)
    // rather than hugging the measured 5.975 — a routine `nightInkSecondary`
    // nudge changes nothing about this pair's justification and should not
    // redden a guard about the *lever*.
    #expect(ceiling < 6.3, "nightInkSecondary got materially brighter: \(ceiling)")
  }

  /// Executes the "margin, not repair" half of the change, which the negative
  /// control above has to leave out.
  ///
  /// `ResultsView.paused` was **not** broken — 4.773 under `nightInkSecondary`
  /// — so repointing it is a consistency move, and the honest way to say that is
  /// to pin both facts: it passed before, and it is strictly better after. If a
  /// future reader concludes "all four were failing", this arm is what corrects
  /// them.
  @Test func pausedPillGainsMarginRatherThanBeingRepaired() {
    let ground = composite(
      PasturaPalette.nightInkSecondary, over: PasturaPalette.nightBubble,
      alpha: Self.inkWashAlpha("ResultsView.paused"))
    let before = contrastRatio(PasturaPalette.nightInkSecondary, ground)
    let after = contrastRatio(PasturaPalette.nightInkOnWash, ground)

    // Clearing the bar is the weaker claim and is not the one the negative
    // control above depends on. That arm excludes this row on the grounds that a
    // blanket four-row control would *fail* — which needs this site outside the
    // marginless band, not merely above 4.5. Without this line a retune pulling
    // it to 4.52 would leave every arm green while the stated scoping rationale
    // quietly became false.
    #expect(
      before >= Self.inkMarginlessBand,
      "the paused pill must sit outside the marginless band, else the three-not-four scoping in inkSecondaryHasNoMarginOnTheseWashes is wrong: \(before)"
    )
    #expect(after > before, "repointing must not cost margin: \(after) vs \(before)")
  }

  /// The arm that stops a future reader "simplifying" the token away.
  ///
  /// Unlike `mossOnWash` there is **no impossibility proof** behind this pair —
  /// `nightInk` would clear the bar on every one of these washes, and the
  /// justification is **role** rather than contrast (`nightInkOnWash`'s doc
  /// comment carries it). That argument is only honest if the cheaper answer
  /// really does work, so this asserts that it does: a reader who wants to
  /// overturn the decision has to argue about hierarchy, not rediscover the
  /// arithmetic.
  @Test func nightInkWouldAlsoClearTheBarAndIsRejectedOnRoleNotContrast() {
    for site in Self.inkWashSites {
      let ground = composite(
        PasturaPalette.nightInkSecondary, over: PasturaPalette.nightBubble, alpha: site.alpha)
      let ratio = contrastRatio(PasturaPalette.nightInk, ground)
      #expect(ratio >= Self.inkTextBar, "expected nightInk to pass \(site.name), got \(ratio)")
    }
  }

  /// `inkOnWash` is a role token, not a fifth rung of §2.2 — but it still has to
  /// sit *between* the two steps it was derived from. In dark that is
  /// `nightInkSecondary` (below) and `nightInk` (above); if a later retune of
  /// either crosses it, the §2.2 prose describing where it sits stops being true.
  ///
  /// Light has no such relation to assert: the light half **is**
  /// `inkSecondary`'s value, which the next arm pins.
  @Test func nightInkOnWashSitsBetweenNightInkSecondaryAndNightInk() {
    let value = relativeLuminance(PasturaPalette.nightInkOnWash)
    #expect(value > relativeLuminance(PasturaPalette.nightInkSecondary))
    #expect(value < relativeLuminance(PasturaPalette.nightInk))
  }

  /// The pair's defining asymmetry, executed rather than described: the light
  /// half is `inkSecondary` **copied, not aliased**, so this pins the copy
  /// (light halves equal) and the separation (dark halves differ).
  ///
  /// **Reddening the equality arm is a decision point, not a repair
  /// instruction.** The two tokens are independent by design, so a legitimate
  /// light-side retune of `inkSecondary` may well be answered by updating the
  /// expectation and letting the values diverge — what the arm buys is that the
  /// divergence is chosen rather than stumbled into. Do **not** read a red here
  /// as "`inkOnWash` forgot to follow" and copy the new value across without
  /// re-measuring. Same wording as ``headerMetaInkSharesHexWithMetaBaseL3``, the
  /// repo's precedent for this shape. The dark clause is the opposite kind: a
  /// "these are the same token, collapse them" refactor reddens it, and that one
  /// really is a repair instruction.
  ///
  /// Comparing raw `PasturaColorValue`s, never `Color` aliases —
  /// `.claude/rules/view-testing.md` warns that a `PasturaDynamicColor`-backed
  /// alias compares by provider instance, so an alias-level `!=` would pass
  /// vacuously and could never fire.
  @Test func inkOnWashCopiesTheLightHalfAndDivergesOnlyInDark() {
    #expect(PasturaPalette.inkOnWash == PasturaPalette.inkSecondary)
    #expect(PasturaPalette.nightInkOnWash != PasturaPalette.nightInkSecondary)
  }
}

// MARK: - Helpers

/// One shipped self-wash consumer: a site painting `inkSecondary` as both its
/// label and its capsule fill, and the alpha it fills at.
///
/// A struct rather than a tuple for consistency with ``MossWashSite``, whose
/// four members exceed swiftlint's `large_tuple` cap. This one carries only two
/// — every row fills with the same token, and none of them re-base the alpha per
/// appearance — so the wash token is not stored.
///
/// File scope per `.claude/rules/testing.md` § "Splitting a Suite Across Files":
/// helpers in a sibling file live outside the suite struct.
struct InkWashSite {
  let name: String
  let alpha: Double

  init(_ name: String, alpha: Double) {
    self.name = name
    self.alpha = alpha
  }
}
