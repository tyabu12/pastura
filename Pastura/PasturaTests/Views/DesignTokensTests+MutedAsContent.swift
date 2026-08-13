import SwiftUI
import Testing

@testable import Pastura

// Contrast guard for `muted` used as **content** text (#1427).
//
// The token's value is not the defect: design-system §8 makes `muted` a
// deliberately sub-AA "quietude" tier, exempt from the 4.5:1 bar. What these arms
// pin is the *shape* of that exemption — §8 justifies it with one measurement
// («#FCFAF4 上で ≈ 3.3:1», the `screenBackground` ground), and the token degrades
// well past it on the other grounds the app ships, so a label legitimately
// ambient on the page ground can sit at 2.136 on a tinted capsule and still read
// as sanctioned. The app-wide sweep of the remaining sites is #1448.
//
// Sibling-file extension rather than a fresh `@Suite`, per
// `.claude/rules/testing.md` § "Splitting a Suite Across Files". `contrastRatio`
// lives at the foot of `DesignTokensTests+NightPalette.swift`.
extension DesignTokensTests {

  /// WCAG 1.4.3 normal-text bar. Both #1427 labels are `caption`-class (~12pt),
  /// under the "large text" threshold, so 3:1 never applies to either.
  private static let contentTextBar = 4.5

  /// Every opaque ground the app ships that `muted` is or could be drawn on,
  /// per appearance. Hand-written against the palette rather than derived from
  /// `PasturaDynamicPalette.all`, which would sweep in fills that never carry
  /// text.
  ///
  /// Deliberately **not** "grounds `muted` is drawn on today" — occupancy is the
  /// per-site question #1448 answers, and scoping to it would churn this fixture
  /// on every unrelated repoint. The bar applies to the ground either way.
  ///
  /// The two lists are symmetric, six against six, and the count pins below are
  /// what keep an omission from silently skewing a "worst case".
  private static let mutedLightGrounds: [(name: String, ratio: Double)] = [
    ("screenBackground", contrastRatio(PasturaPalette.muted, PasturaPalette.screenBackground)),
    ("page", contrastRatio(PasturaPalette.muted, PasturaPalette.page)),
    ("bubbleBackground", contrastRatio(PasturaPalette.muted, PasturaPalette.bubbleBackground)),
    ("whisperBubble", contrastRatio(PasturaPalette.muted, PasturaPalette.whisperBubble)),
    ("promoBackground", contrastRatio(PasturaPalette.muted, PasturaPalette.promoBackground)),
    ("mossSoft", contrastRatio(PasturaPalette.muted, PasturaPalette.mossSoft))
  ]

  private static let mutedDarkGrounds: [(name: String, ratio: Double)] = [
    ("nightBackground", contrastRatio(PasturaPalette.nightMuted, PasturaPalette.nightBackground)),
    ("nightPage", contrastRatio(PasturaPalette.nightMuted, PasturaPalette.nightPage)),
    ("nightBubble", contrastRatio(PasturaPalette.nightMuted, PasturaPalette.nightBubble)),
    (
      "nightWhisperBubble",
      contrastRatio(PasturaPalette.nightMuted, PasturaPalette.nightWhisperBubble)
    ),
    (
      "nightPromoBackground",
      contrastRatio(PasturaPalette.nightMuted, PasturaPalette.nightPromoBackground)
    ),
    ("nightMossSoft", contrastRatio(PasturaPalette.nightMuted, PasturaPalette.nightMossSoft))
  ]

  /// `muted` clears the bar on **no** ground the app ships, in either appearance:
  /// not "close enough everywhere" but 2.1–4.2 against a 4.5 bar, so anything
  /// placed in this tier is placed below AA deliberately.
  @Test func mutedIsSubAAOnEveryGroundItShipsOn() {
    // Anti-vacuity: the loops iterate these literals, so an emptied array would
    // pass silently.
    #expect(Self.mutedLightGrounds.count == 6)
    #expect(Self.mutedDarkGrounds.count == 6)

    for ground in Self.mutedLightGrounds {
      #expect(ground.ratio < Self.contentTextBar, "light \(ground.name): \(ground.ratio)")
    }
    for ground in Self.mutedDarkGrounds {
      #expect(ground.ratio < Self.contentTextBar, "dark \(ground.name): \(ground.ratio)")
    }
  }

  /// The narrowest margin, pinned **by name** rather than as a range — a range
  /// reads as a safety claim while hiding which ground is nearest the bar, and
  /// goes stale the moment a ground is added or retuned.
  ///
  /// `nightMuted` on `nightPage` sits **7.7%** below 4.5 against **22.8%** for
  /// the narrowest light ground (`bubbleBackground`, 3.475), so a modest retune
  /// of either token flips `nightPage` first and that is the one to re-measure.
  @Test func nightPageIsTheGroundNearestTheBar() {
    let worst = Self.mutedDarkGrounds.max(by: { $0.ratio < $1.ratio })
    #expect(worst?.name == "nightPage", "narrowest dark margin moved to \(worst?.name ?? "nil")")

    let lightWorst = Self.mutedLightGrounds.max(by: { $0.ratio < $1.ratio })
    #expect(lightWorst?.name == "bubbleBackground", "narrowest light margin moved")

    // Still sub-AA — if this ever passes the bar, §8's framing needs re-deriving
    // before anything here is "fixed".
    #expect((worst?.ratio ?? 0) < Self.contentTextBar, "nightPage: \(worst?.ratio ?? 0)")
  }

  /// The two repoints #1427 shipped, on their real grounds: `PredictionOutcomeBadge`'s
  /// miss arm on the neutral card surface, its streak sub-label on the opaque
  /// `mossSoft` capsule (the §2.6 pairing #1407 gave the same badge's hit arm).
  @Test func bothPredictionBadgeRepointsClearTheBar() {
    let missLight = contrastRatio(PasturaPalette.inkSecondary, PasturaPalette.bubbleBackground)
    #expect(missLight >= Self.contentTextBar, "miss light: \(missLight)")
    let missDark = contrastRatio(PasturaPalette.nightInkSecondary, PasturaPalette.nightBubble)
    #expect(missDark >= Self.contentTextBar, "miss dark: \(missDark)")

    let streakLight = contrastRatio(PasturaPalette.mossInk, PasturaPalette.mossSoft)
    #expect(streakLight >= Self.contentTextBar, "streak light: \(streakLight)")
    let streakDark = contrastRatio(PasturaPalette.nightMossInk, PasturaPalette.nightMossSoft)
    #expect(streakDark >= Self.contentTextBar, "streak dark: \(streakDark)")
  }

  /// Negative control for the streak ground — **light only**, and the asymmetry
  /// is the point. `inkSecondary` is the obvious quieter candidate and the token
  /// the miss arm above *does* ship; it simply does not reach here, at 4.262 in
  /// light while **dark** clears at 4.772. A symmetric "inkSecondary fails here"
  /// would be false in one appearance.
  ///
  /// Read with ``bothPredictionBadgeRepointsClearTheBar``: one token shipped on
  /// `bubbleBackground` and refused on `mossSoft` is a statement about grounds,
  /// not about the token.
  @Test func inkSecondaryDoesNotRescueTheStreakOnMossSoftInLight() {
    let light = contrastRatio(PasturaPalette.inkSecondary, PasturaPalette.mossSoft)
    #expect(light < Self.contentTextBar, "expected sub-AA in light, got \(light)")

    let dark = contrastRatio(PasturaPalette.nightInkSecondary, PasturaPalette.nightMossSoft)
    #expect(dark >= Self.contentTextBar, "dark was supposed to be passing already: \(dark)")
  }

  /// `metaBaseL3` **would** have worked (5.272 / 6.518 on the streak ground) and
  /// would have kept the colour-based subordination `mossInk` gives up. Pinned so
  /// the next reader does not "discover" it as an unmeasured option: it is
  /// refused as a §2.4 DL-progress rung, per ADR-028 § "Three narrower
  /// rejections".
  ///
  /// **A failure here means the ratio moved, not that the decision changed** —
  /// the §2.4 coupling argument is unaffected either way.
  @Test func metaBaseL3ClearsTheStreakGroundButIsARungNotARole() {
    let light = contrastRatio(PasturaPalette.metaBaseL3, PasturaPalette.mossSoft)
    #expect(light >= Self.contentTextBar, "metaBaseL3 light: \(light)")

    let dark = contrastRatio(PasturaPalette.nightMetaBaseL3, PasturaPalette.nightMossSoft)
    #expect(dark >= Self.contentTextBar, "metaBaseL3 dark: \(dark)")
  }
}
