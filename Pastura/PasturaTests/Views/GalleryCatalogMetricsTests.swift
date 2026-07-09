import CoreGraphics
import Testing

@testable import Pastura

/// Change-detector tripwire for the さがす (Browse) catalog-card layout tokens
/// (``GalleryCatalogMetrics``; tab-identity redesign PR2, #777) plus unit
/// coverage of the pure ``GalleryCatalogRowFormat`` helpers.
///
/// The metric assertions mirror the source-of-truth constants **by design**.
/// The card's rendered appearance (art tile, cluster, chip, spacing) is
/// code-review-gated only (ADR-009 decision 3 — frame / layout tuning is out of
/// scope for automated tests; the final values are tuned on-device). A failure
/// here does NOT mean a bug was found: it means a code-review-gated layout token
/// drifted (typically in an unrelated refactor), and the editor must confirm the
/// change passed code review before updating the expected value. See
/// `.claude/rules/view-testing.md` § "Change-detector tripwire".
///
/// The suite is intentionally **not** `@MainActor`: ``GalleryCatalogMetrics``
/// and ``GalleryCatalogRowFormat`` are `nonisolated`, so a nonisolated test
/// reads them directly — this suite also documents that isolation contract.
@Suite("GalleryCatalogMetrics", .timeLimit(.minutes(1)))
struct GalleryCatalogMetricsTests {

  @Test func artTileGeometryUnchanged() {
    #expect(GalleryCatalogMetrics.artTileSize == 74)
    #expect(GalleryCatalogMetrics.artTileCornerRadius == 13)
    #expect(GalleryCatalogMetrics.artSheepSize == 26)
    #expect(GalleryCatalogMetrics.artClusterSpacing == 1)
    #expect(GalleryCatalogMetrics.artTileBorderWidth == 1)
    #expect(GalleryCatalogMetrics.maxClusterSheep == 6)
  }

  @Test func clusterSheepSizeTiersUnchanged() {
    // Sheep shrink as the count grows so 5–6 fit the 74pt tile in a 2×3 grid.
    #expect(GalleryCatalogMetrics.clusterSheepSize(forCount: 1) == 40)
    #expect(GalleryCatalogMetrics.clusterSheepSize(forCount: 2) == 30)
    #expect(GalleryCatalogMetrics.clusterSheepSize(forCount: 3) == 26)
    #expect(GalleryCatalogMetrics.clusterSheepSize(forCount: 4) == 26)
    #expect(GalleryCatalogMetrics.clusterSheepSize(forCount: 5) == 21)
    #expect(GalleryCatalogMetrics.clusterSheepSize(forCount: 6) == 21)
  }

  @Test func signatureBadgeGeometryUnchanged() {
    #expect(GalleryCatalogMetrics.badgeDiameter == 26)
    #expect(GalleryCatalogMetrics.badgeGlyphSize == 15)
    #expect(GalleryCatalogMetrics.badgeBorderWidth == 1)
    #expect(GalleryCatalogMetrics.badgeOffset == 6)
  }

  @Test func cardChromeUnchanged() {
    #expect(GalleryCatalogMetrics.cardSpacing == 13)
    #expect(GalleryCatalogMetrics.cardCornerRadius == 16)
    #expect(GalleryCatalogMetrics.cardPadding == 13)
  }

  @Test func listRhythmUnchanged() {
    #expect(GalleryCatalogMetrics.listSpacing == 12)
    #expect(GalleryCatalogMetrics.listHorizontalMargin == 16)
    // ADR-020 D4 — the engine-incompatible card dim.
    #expect(GalleryCatalogMetrics.incompatibleCardOpacity == 0.5)
  }

  @Test func bodySpacingUnchanged() {
    #expect(GalleryCatalogMetrics.descriptionLineLimit == 2)
    #expect(GalleryCatalogMetrics.titleChipSpacing == 5)
    #expect(GalleryCatalogMetrics.descriptionTopPadding == 6)
    #expect(GalleryCatalogMetrics.footerTopPadding == 7)
  }

  @Test func categoryChipMetricsUnchanged() {
    #expect(GalleryCatalogMetrics.catchipHorizontalPadding == 7)
    #expect(GalleryCatalogMetrics.catchipVerticalPadding == 2)
    #expect(GalleryCatalogMetrics.catchipCornerRadius == 6)
  }

  // MARK: - footerSegments

  @Test func footerSegmentsJoinsBothHalvesWithDot() {
    let segments = GalleryCatalogRowFormat.footerSegments(agentCount: 4, rounds: 6)
    #expect(segments.count == 3)
    #expect(segments[1] == "·")
    // The numeric halves render through the existing %lld keys; assert the
    // count digit appears so a swapped placeholder is caught.
    #expect(segments[0].contains("4"))
    #expect(segments[2].contains("6"))
  }

  @Test func footerSegmentsOmitsMissingHalves() {
    #expect(GalleryCatalogRowFormat.footerSegments(agentCount: 3, rounds: nil).count == 1)
    #expect(GalleryCatalogRowFormat.footerSegments(agentCount: nil, rounds: 5).count == 1)
    // No dangling separator when only one half is present.
    #expect(!GalleryCatalogRowFormat.footerSegments(agentCount: 3, rounds: nil).contains("·"))
  }

  @Test func footerSegmentsEmptyWhenNeitherPresent() {
    #expect(GalleryCatalogRowFormat.footerSegments(agentCount: nil, rounds: nil).isEmpty)
  }

  // MARK: - clusterSheepCount

  @Test func clusterSheepCountClampsToRange() {
    #expect(GalleryCatalogRowFormat.clusterSheepCount(agentCount: 1) == 1)
    #expect(GalleryCatalogRowFormat.clusterSheepCount(agentCount: 3) == 3)
    #expect(GalleryCatalogRowFormat.clusterSheepCount(agentCount: 4) == 4)
    // Exact through the real gallery max (5) and the clamp ceiling (6).
    #expect(GalleryCatalogRowFormat.clusterSheepCount(agentCount: 5) == 5)
    #expect(GalleryCatalogRowFormat.clusterSheepCount(agentCount: 6) == 6)
    // Clamped to maxClusterSheep — the footer's "N agents" carries the exact
    // count, so the tile may approximate beyond the ceiling.
    #expect(GalleryCatalogRowFormat.clusterSheepCount(agentCount: 9) == 6)
  }

  @Test func clusterSheepCountEmptyWhenUnknownOrNonPositive() {
    // Unknown (nil) and non-positive counts draw no sheep — the catalog never
    // fabricates agent data the rest of the app hides.
    #expect(GalleryCatalogRowFormat.clusterSheepCount(agentCount: nil) == 0)
    #expect(GalleryCatalogRowFormat.clusterSheepCount(agentCount: 0) == 0)
    #expect(GalleryCatalogRowFormat.clusterSheepCount(agentCount: -2) == 0)
  }

  // MARK: - signaturePhase (fixed priority derivation)

  @Test func signaturePhaseNilOrEmptyYieldsNoBadge() {
    #expect(GalleryCatalogRowFormat.signaturePhase(phases: nil) == nil)
    #expect(GalleryCatalogRowFormat.signaturePhase(phases: []) == nil)
  }

  @Test func signaturePhaseScaffoldingOnlyFallsBackToDiscuss() {
    // asch_conformity shape — only scaffolding phases present.
    #expect(
      GalleryCatalogRowFormat.signaturePhase(phases: ["speak_each", "summarize"]) == .discuss)
    #expect(GalleryCatalogRowFormat.signaturePhase(phases: ["assign", "speak_all"]) == .discuss)
  }

  @Test func signaturePhaseUnknownKindsFallBackToDiscuss() {
    // Unknown phase kinds (lenient [String] decode) contribute no signature;
    // with nothing else present the badge falls back to discuss.
    #expect(GalleryCatalogRowFormat.signaturePhase(phases: ["future_kind"]) == .discuss)
  }

  @Test func signaturePhaseIgnoresUnknownKindsAlongsideKnown() {
    // A mix of unknown + known: the unknown is dropped by compactMap and the
    // known phase still wins its priority slot.
    #expect(GalleryCatalogRowFormat.signaturePhase(phases: ["future_kind", "vote"]) == .vote)
  }

  @Test func signaturePhasePicksHighestPriorityPresent() {
    // oogiri: eliminate is top priority.
    #expect(
      GalleryCatalogRowFormat.signaturePhase(
        phases: ["assign", "speak_all", "vote", "eliminate", "summarize"]) == .eliminate)
    // detective: conditional beats vote / score_calc.
    #expect(
      GalleryCatalogRowFormat.signaturePhase(
        phases: ["speak_each", "vote", "score_calc", "conditional"]) == .conditional)
  }

  @Test func signaturePhaseRanksEventInjectAboveVote() {
    // hapning_ranyu shape — event_inject must win over the also-present vote
    // (mechanic-salience: the disruption is the scenario's real hook).
    #expect(
      GalleryCatalogRowFormat.signaturePhase(
        phases: ["event_inject", "speak_all", "vote", "score_calc", "summarize"]) == .eventInject)
  }

  @Test func signaturePhaseRanksVoteAboveScoreCalc() {
    #expect(GalleryCatalogRowFormat.signaturePhase(phases: ["score_calc", "vote"]) == .vote)
  }

  @Test func signaturePhasePriorityOrderIsFixed() {
    // The priority order is corpus-independent — pin it so a reorder is a
    // deliberate, reviewed change (and so event_inject stays above vote).
    #expect(
      ScenarioSignaturePhase.priorityOrder == [
        .eliminate, .choose, .conditional, .eventInject, .vote, .scoreCalc
      ])
  }

  @Test func signaturePriorityOrderCoversEveryMappableCase() {
    // Every case except the `discuss` fallback must appear in priorityOrder —
    // so a newly-added mappable case can't silently fall through to discuss
    // (it forces a deliberate priority placement instead).
    let mappable = Set(ScenarioSignaturePhase.allCases).subtracting([.discuss])
    #expect(Set(ScenarioSignaturePhase.priorityOrder) == mappable)
    // No duplicates / no `discuss` snuck in.
    #expect(ScenarioSignaturePhase.priorityOrder.count == mappable.count)
    #expect(!ScenarioSignaturePhase.priorityOrder.contains(.discuss))
  }

  @Test func signatureMappingTracksPhaseTypeRawValues() {
    // `ScenarioSignaturePhase.init?(phaseRawValue:)` is now a no-default
    // exhaustive switch over `PhaseType` (ADR-022 D2), so the compiler is the
    // primary guard that every phase kind gets a headline decision. This test
    // is the `allCases`-driven backstop: it partitions the FULL `PhaseType`
    // set into the six signature kinds and the seven signature-less kinds and
    // asserts both sides, so it can never silently lag the enum the way a
    // hand-listed nil-side did (it previously covered only 4 of 7).
    let expected: [PhaseType: ScenarioSignaturePhase] = [
      .eliminate: .eliminate, .choose: .choose, .conditional: .conditional,
      .eventInject: .eventInject, .vote: .vote, .scoreCalc: .scoreCalc
    ]
    for phase in PhaseType.allCases {
      // `expected[phase]` is `nil` for the signature-less kinds, which is
      // exactly the mapping we assert — no headline for scaffolding /
      // interaction phases.
      #expect(ScenarioSignaturePhase(phaseRawValue: phase.rawValue) == expected[phase])
    }
  }

  // MARK: - badge (compatibility-driven, ADR-020 D4)

  @Test func badgeIncompatibleAlwaysUpdateRequired() {
    // Incompatibility wins over any install/update state — the scenario can't
    // run on this build, so provenance signals are suppressed.
    #expect(
      GalleryCatalogRowFormat.badge(compatible: false, hasUpdate: true, isInstalled: true)
        == .updateRequired)
    #expect(
      GalleryCatalogRowFormat.badge(compatible: false, hasUpdate: false, isInstalled: false)
        == .updateRequired)
  }

  @Test func badgeCompatibleUpdateWinsOverInstalled() {
    #expect(
      GalleryCatalogRowFormat.badge(compatible: true, hasUpdate: true, isInstalled: true)
        == .update)
  }

  @Test func badgeCompatibleInstalledWhenNoUpdate() {
    #expect(
      GalleryCatalogRowFormat.badge(compatible: true, hasUpdate: false, isInstalled: true)
        == .installed)
  }

  @Test func badgeCompatibleNoneWhenFresh() {
    #expect(
      GalleryCatalogRowFormat.badge(compatible: true, hasUpdate: false, isInstalled: false)
        == nil)
  }

  // MARK: - signature glyph mapping (change-detector)

  @Test func signatureGlyphSymbolsUnchanged() {
    #expect(ScenarioSignaturePhase.eliminate.sfSymbolName == "xmark.circle")
    #expect(ScenarioSignaturePhase.choose.sfSymbolName == "arrow.triangle.branch")
    #expect(ScenarioSignaturePhase.conditional.sfSymbolName == "diamond")
    #expect(ScenarioSignaturePhase.eventInject.sfSymbolName == "bolt.fill")
    #expect(ScenarioSignaturePhase.vote.sfSymbolName == "checkmark.square")
    #expect(ScenarioSignaturePhase.scoreCalc.sfSymbolName == "chart.bar")
    #expect(ScenarioSignaturePhase.discuss.sfSymbolName == "bubble.left.and.bubble.right")
  }
}
