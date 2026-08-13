import SwiftUI
import Testing

@testable import Pastura

// Contrast guard for `muted` used as **content** text (#1427).
//
// The token's value is not the defect. design-system §8 records `muted` as a
// deliberately sub-AA "quietude" tier, exempt from the 4.5:1 bar, with a
// standing instruction not to place must-read information there. What this file
// pins is the *shape* of that exemption: §8 justifies it with one measurement,
// «#FCFAF4 上で ≈ 3.3:1» — the `screenBackground` ground — and the token degrades
// well past that figure on the other grounds the app ships. A label that is
// legitimately ambient on the page ground can be sitting at 2.136 on a tinted
// capsule while still reading as sanctioned.
//
// So these arms are not "muted is broken, fix it". They are the record that the
// exemption is ground-relative, so a future reader repointing a `muted` label
// can see which grounds the §8 figure does and does not speak for. The
// app-wide sweep of the remaining sites is #1448.
//
// Sibling-file extension rather than a fresh `@Suite`, per
// `.claude/rules/testing.md` § "Splitting a Suite Across Files". `contrastRatio`
// lives at the foot of `DesignTokensTests+NightPalette.swift`.
extension DesignTokensTests {

  /// WCAG 1.4.3 normal-text bar. Both #1427 labels are `caption`-class (~12pt),
  /// under the "large text" threshold, so 3:1 never applies to either.
  private static let contentTextBar = 4.5

  /// Every opaque ground `muted` is drawn on, per appearance. Hand-written
  /// against the palette rather than derived from `PasturaDynamicPalette.all`,
  /// which would sweep in fills that never carry text.
  ///
  /// The two lists are deliberately symmetric — six against six. An earlier
  /// draft of #1427 enumerated five dark grounds, omitting `nightPromoBackground`,
  /// and reported a "worst case" that was accordingly wrong; the count pins below
  /// are what make that shape visible instead of silent.
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

  /// `muted` clears the bar on **no** ground the app ships, in either appearance.
  ///
  /// This is the arm that makes §8's exemption legible: it is not "close enough
  /// everywhere", it is 2.1–4.2 against a 4.5 bar. Anything placed in this tier
  /// is being placed below AA deliberately.
  @Test func mutedIsSubAAOnEveryGroundItShipsOn() {
    // Anti-vacuity: the loops iterate these literals, so an emptied array would
    // pass silently. Six per appearance — see the fixture's doc comment for why
    // the symmetry is load-bearing.
    #expect(Self.mutedLightGrounds.count == 6)
    #expect(Self.mutedDarkGrounds.count == 6)

    for ground in Self.mutedLightGrounds {
      #expect(ground.ratio < Self.contentTextBar, "light \(ground.name): \(ground.ratio)")
    }
    for ground in Self.mutedDarkGrounds {
      #expect(ground.ratio < Self.contentTextBar, "dark \(ground.name): \(ground.ratio)")
    }
  }

  /// The narrowest margin, pinned **by name** rather than as a range.
  ///
  /// A range ("2.1–4.2, all sub-AA") reads as a safety claim while hiding which
  /// ground is nearest the bar, and it is exactly what goes stale when a ground
  /// is added or retuned. `nightMuted` on `nightPage` sits **8%** below 4.5, not
  /// the ~19% the light figures alone would suggest — so a modest retune of
  /// either token flips this ground first, and it is the one to re-measure.
  @Test func nightPageIsTheGroundNearestTheBar() {
    let worst = Self.mutedDarkGrounds.max(by: { $0.ratio < $1.ratio })
    #expect(worst?.name == "nightPage", "narrowest dark margin moved to \(worst?.name ?? "nil")")

    let lightWorst = Self.mutedLightGrounds.max(by: { $0.ratio < $1.ratio })
    #expect(lightWorst?.name == "bubbleBackground", "narrowest light margin moved")

    // Still sub-AA — if this ever passes the bar, §8's framing needs re-deriving
    // before anything here is "fixed".
    #expect((worst?.ratio ?? 0) < Self.contentTextBar, "nightPage: \(worst?.ratio ?? 0)")
  }

  /// The two repoints #1427 shipped, on their real grounds.
  ///
  /// `PredictionOutcomeBadge`'s miss arm takes `inkSecondary` on the neutral card
  /// surface; its streak sub-label takes `mossInk` on the opaque `mossSoft`
  /// capsule — the §2.6 `<family>Soft` + `<family>Ink` pairing that #1407 already
  /// applied to the same badge's hit arm.
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
  /// is the point.
  ///
  /// `inkSecondary` is the obvious candidate for a quieter sub-label, and it is
  /// the token the miss arm above *does* ship. It simply does not reach on this
  /// ground: 4.262 in light. In **dark** it clears at 4.772, so a symmetric
  /// "inkSecondary fails here" claim would be false in one appearance — the same
  /// per-appearance care ADR-028 takes over #1407 (light-only) versus #1408
  /// (dark-only).
  ///
  /// Read together with ``bothPredictionBadgeRepointsClearTheBar``: the same
  /// token is shipped on `bubbleBackground` and rejected on `mossSoft`, in one
  /// PR. That is a statement about grounds, not about the token.
  @Test func inkSecondaryDoesNotRescueTheStreakOnMossSoftInLight() {
    let light = contrastRatio(PasturaPalette.inkSecondary, PasturaPalette.mossSoft)
    #expect(light < Self.contentTextBar, "expected sub-AA in light, got \(light)")

    let dark = contrastRatio(PasturaPalette.nightInkSecondary, PasturaPalette.nightMossSoft)
    #expect(dark >= Self.contentTextBar, "dark was supposed to be passing already: \(dark)")
  }

  /// `metaBaseL3` **would** have worked, and was rejected on convention.
  ///
  /// Pinned so the next reader does not "discover" it as an unmeasured option.
  /// It clears the bar on the streak ground (5.272 / 6.518) and would have kept
  /// colour-based subordination to "Correct!", which `mossInk` gives up. It is
  /// refused because it is a §2.4 DL-progress ladder rung: ADR-028 § "Three
  /// narrower rejections" declines to borrow one ("borrowing it would couple two
  /// families"), and `DesignTokens+ExtendedPalette.swift` minted `headerMetaInk`
  /// at the *same hex* rather than collapse the two roles.
  ///
  /// **So a failure here means the ratio moved, not that the decision changed.**
  /// If this arm ever drops below the bar, `metaBaseL3` or `mossSoft` was
  /// retuned — the §2.4 coupling argument is unaffected either way.
  @Test func metaBaseL3ClearsTheStreakGroundButIsARungNotARole() {
    let light = contrastRatio(PasturaPalette.metaBaseL3, PasturaPalette.mossSoft)
    #expect(light >= Self.contentTextBar, "metaBaseL3 light: \(light)")

    let dark = contrastRatio(PasturaPalette.nightMetaBaseL3, PasturaPalette.nightMossSoft)
    #expect(dark >= Self.contentTextBar, "metaBaseL3 dark: \(dark)")
  }
}
