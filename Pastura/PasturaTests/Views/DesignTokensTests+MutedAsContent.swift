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
  /// **The composited arms further down are occupancy-derived, and that is an
  /// exception rather than a drift from this rule.** A wash has no existence
  /// apart from the site painting it: alpha, tint and base are all per-site
  /// choices, so there is no "the app's translucent grounds" to hand-write
  /// against the palette. The churn that buys is bounded and stated: a repoint
  /// away from `muted` at one of those sites **deletes** its entry, which for a
  /// wash is correct rather than a loss — nothing remains to measure.
  ///
  /// **The reverse — a new muted-on-wash ground arriving with no entry — is
  /// only partly covered, and the gap is worth naming.** `MutedSweepLedgerTests`
  /// fires on a new `Color.muted` *occurrence*, so a wash painted behind an
  /// occurrence that already exists moves no map and reddens nothing. Adding a
  /// `.background(Color.moss.opacity(0.2))` under an existing muted caption is
  /// invisible to both files. Nothing here closes that; a ground is a property
  /// of the view hierarchy and neither a census nor a palette can be asked
  /// about it.
  ///
  /// One shipped muted-on-translucent ground is **excluded on purpose**:
  /// `SimulationView`'s loading-scrim subtitle sits on `.regularMaterial`,
  /// which composites whatever is behind it at render time, so no static ratio
  /// exists to assert. `DLCompleteOverlay` states the same reasoning at its own
  /// site. Ledger § 3.3 carries both.
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

  // MARK: - Composited grounds (#1448)

  /// The opaque grounds as *tokens*, so the wash arms can composite over them.
  /// Mirrors ``mutedLightGrounds`` / ``mutedDarkGrounds`` in name and order —
  /// pinned as such in ``compositedGroundListsMirrorTheOpaqueOnes``, which is
  /// what keeps the duplication a checked mirror rather than a second source.
  private static let lightGroundTokens: [(name: String, token: PasturaColorValue)] = [
    ("screenBackground", PasturaPalette.screenBackground),
    ("page", PasturaPalette.page),
    ("bubbleBackground", PasturaPalette.bubbleBackground),
    ("whisperBubble", PasturaPalette.whisperBubble),
    ("promoBackground", PasturaPalette.promoBackground),
    ("mossSoft", PasturaPalette.mossSoft)
  ]

  private static let darkGroundTokens: [(name: String, token: PasturaColorValue)] = [
    ("nightBackground", PasturaPalette.nightBackground),
    ("nightPage", PasturaPalette.nightPage),
    ("nightBubble", PasturaPalette.nightBubble),
    ("nightWhisperBubble", PasturaPalette.nightWhisperBubble),
    ("nightPromoBackground", PasturaPalette.nightPromoBackground),
    ("nightMossSoft", PasturaPalette.nightMossSoft)
  ]

  /// `ResultsView`'s `.pending` pill — `muted` text over `muted@0.14`, a
  /// **self-wash**. `ResultsView` sets `screenBackground` and the rows carry no
  /// card, so the base is the screen ground in both appearances.
  private static let mutedSelfWashGrounds: [(name: String, ratio: Double)] = [
    (
      "light muted@0.14 over screenBackground",
      contrastRatio(
        PasturaPalette.muted,
        composite(PasturaPalette.muted, over: PasturaPalette.screenBackground, alpha: 0.14))
    ),
    (
      "dark nightMuted@0.14 over nightBackground",
      contrastRatio(
        PasturaPalette.nightMuted,
        composite(PasturaPalette.nightMuted, over: PasturaPalette.nightBackground, alpha: 0.14))
    )
  ]

  /// The two moss washes `muted` text actually sits on.
  ///
  /// `ActiveModelChip` is a `HomeView` `ToolbarItem` with the bar's own
  /// background hidden, so it reads against Home's screen ground — **not** the
  /// card ground. `ModelRow`'s selected background is `moss@0.06` inside
  /// `ModelPickerView.listCard`, which fills `bubbleBackground`.
  ///
  /// `ModelRow`'s other moss washes (`moss@0.08` avatar disc, `moss@0.12`
  /// recommended tag) are deliberately absent: neither has `muted` text on it —
  /// the disc is decorative and the tag draws `mossOnWash`.
  private static let mutedMossWashGrounds: [(name: String, ratio: Double)] = [
    (
      "light ActiveModelChip mossDark@0.10 over screenBackground",
      contrastRatio(
        PasturaPalette.muted,
        composite(PasturaPalette.mossDark, over: PasturaPalette.screenBackground, alpha: 0.10))
    ),
    (
      "dark ActiveModelChip nightMossDark@0.10 over nightBackground",
      contrastRatio(
        PasturaPalette.nightMuted,
        composite(
          PasturaPalette.nightMossDark, over: PasturaPalette.nightBackground, alpha: 0.10))
    ),
    (
      "light ModelRow moss@0.06 over bubbleBackground",
      contrastRatio(
        PasturaPalette.muted,
        composite(PasturaPalette.moss, over: PasturaPalette.bubbleBackground, alpha: 0.06))
    ),
    (
      "dark ModelRow nightMoss@0.06 over nightBubble",
      contrastRatio(
        PasturaPalette.nightMuted,
        composite(PasturaPalette.nightMoss, over: PasturaPalette.nightBubble, alpha: 0.06))
    )
  ]

  /// `ReportSheet`'s meta chip — `rule@0.45`, over a ground that **is not a
  /// Pastura token**: the sheet sets no background, so it renders on the system
  /// sheet surface (ledger §3.3). Guessing a base would put an invented figure
  /// in the record, so this arm quantifies instead.
  ///
  /// **The twelve Pastura grounds alone would not license "whatever the sheet
  /// resolves to"** — the system surface is not among them, so an arm over just
  /// those measures twelve grounds the site never sits on and never the one it
  /// does. The last two entries close that: compositing at a fixed alpha is
  /// per-channel, so every channel of the result lies between its value over
  /// **black** and over **white**, relative luminance is monotone in each
  /// channel, and contrast against a fixed foreground is maximal at an endpoint
  /// of that luminance interval. Sub-AA at both extremes therefore implies
  /// sub-AA over *every* opaque ground, chromatic ones included — which is the
  /// claim the site needs and the twelve are then illustration rather than
  /// evidence.
  private static let mutedRuleWashGrounds: [(name: String, ratio: Double)] = {
    lightGroundTokens.map {
      (
        "light rule@0.45 over \($0.name)",
        contrastRatio(
          PasturaPalette.muted, composite(PasturaPalette.rule, over: $0.token, alpha: 0.45))
      )
    }
      + darkGroundTokens.map {
        (
          "dark nightRule@0.45 over \($0.name)",
          contrastRatio(
            PasturaPalette.nightMuted,
            composite(PasturaPalette.nightRule, over: $0.token, alpha: 0.45))
        )
      }
  }()

  /// The bracket itself — pure white and pure black are **luminance extremes,
  /// not shipped grounds**, which is why they live in their own array. They
  /// belong to the sub-AA claim and must stay out of
  /// ``compositedGroundsStayAboveTheOpaqueWorstCase``. **One extreme per
  /// appearance** lands below the 2.136 opaque floor — 1.739 light-over-black
  /// and 1.825 dark-over-white, against 3.018 and 3.919 at the other ends — and
  /// one is enough to make that arm assert something false about the app. Not
  /// "an extreme is always below the floor": two of the four are above it.
  private static let mutedRuleWashBrackets: [(name: String, ratio: Double)] = [
    (
      "light rule@0.45 over pure white",
      contrastRatio(
        PasturaPalette.muted, composite(PasturaPalette.rule, over: pureWhite, alpha: 0.45))
    ),
    (
      "light rule@0.45 over pure black",
      contrastRatio(
        PasturaPalette.muted, composite(PasturaPalette.rule, over: pureBlack, alpha: 0.45))
    ),
    (
      "dark nightRule@0.45 over pure white",
      contrastRatio(
        PasturaPalette.nightMuted,
        composite(PasturaPalette.nightRule, over: pureWhite, alpha: 0.45))
    ),
    (
      "dark nightRule@0.45 over pure black",
      contrastRatio(
        PasturaPalette.nightMuted,
        composite(PasturaPalette.nightRule, over: pureBlack, alpha: 0.45))
    )
  ]

  private static let pureWhite = PasturaColorValue(hex: 0xFFFFFF)
  private static let pureBlack = PasturaColorValue(hex: 0x000000)

  /// Every composited ground is sub-AA too, so §8's exemption is what carries
  /// them — and §8 never measured a wash. This is the arm that makes "the
  /// exemption was not measured here" a fact in the fixture rather than only a
  /// sentence in the ledger.
  @Test func mutedIsSubAAOnEveryCompositedGroundToo() {
    #expect(Self.mutedSelfWashGrounds.count == 2)
    #expect(Self.mutedMossWashGrounds.count == 4)
    #expect(Self.mutedRuleWashGrounds.count == 12)
    #expect(Self.mutedRuleWashBrackets.count == 4)

    let all =
      Self.mutedSelfWashGrounds + Self.mutedMossWashGrounds + Self.mutedRuleWashGrounds
      + Self.mutedRuleWashBrackets
    for ground in all {
      #expect(ground.ratio < Self.contentTextBar, "\(ground.name): \(ground.ratio)")
    }
  }

  /// The washes are *unmeasured*, not a new floor: every one lands above the
  /// 2.136 `mossSoft` opaque worst, so the twelve-ground span still bounds the
  /// token and §8's «判読が要る情報» test is unchanged by them.
  ///
  /// Pinned as a comparison against the opaque list rather than as a literal —
  /// retuning `mossSoft` moves the floor, and the claim is about the ordering.
  ///
  /// **Shipped grounds only.** ``mutedRuleWashBrackets`` is excluded: those two
  /// extremes sit below the floor by construction and are about the *universal*
  /// sub-AA claim, not about anything the app renders. Note also that "lowest"
  /// here means minimum ratio, while ``nightPageIsTheGroundNearestTheBar``'s
  /// "nearest" means maximum — opposite ends, same file.
  @Test func compositedGroundsStayAboveTheOpaqueWorstCase() {
    let opaqueLowest =
      (Self.mutedLightGrounds + Self.mutedDarkGrounds)
      .map(\.ratio).min() ?? 0
    #expect(opaqueLowest > 0)

    let washes = Self.mutedSelfWashGrounds + Self.mutedMossWashGrounds + Self.mutedRuleWashGrounds
    let washLowest = washes.min(by: { $0.ratio < $1.ratio })
    #expect(
      (washLowest?.ratio ?? 0) > opaqueLowest,
      """
      a composited ground (\(washLowest?.name ?? "nil") at \(washLowest?.ratio ?? 0)) now sits \
      below the opaque worst case (\(opaqueLowest)). The ledger's "unmeasured, not a new worst \
      case" framing was load-bearing — re-derive it before updating this.
      """)
  }

  /// The token lists the wash arms composite over must stay the same grounds,
  /// in the same order, as the opaque arms measure. Without this the two drift
  /// and a "worst case" is drawn from two different populations.
  @Test func compositedGroundListsMirrorTheOpaqueOnes() {
    #expect(Self.lightGroundTokens.map(\.name) == Self.mutedLightGrounds.map(\.name))
    #expect(Self.darkGroundTokens.map(\.name) == Self.mutedDarkGrounds.map(\.name))
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
