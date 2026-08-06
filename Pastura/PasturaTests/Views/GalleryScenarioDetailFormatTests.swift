import Testing

@testable import Pastura

/// Unit coverage of the pure ``GalleryScenarioDetailFormat`` helpers backing
/// the shared-scenario detail screen's enriched metadata rows and the
/// "What happens" phase step (view-testing.md rule 1 — logic extracted from
/// the View so it is testable without rendering).
///
/// `@MainActor`: ``GalleryScenarioDetailFormat`` sits at the default (MainActor)
/// isolation because it composes the MainActor ``PhaseDisplayName`` helper
/// (swift-isolation.md Pattern 5) — the suite matches so it can call directly.
/// Phase-label literals are the `en` base strings from ``PhaseDisplayName``
/// (tests run under the `en` base locale).
@Suite("GalleryScenarioDetailFormat", .timeLimit(.minutes(1)))
@MainActor
struct GalleryScenarioDetailFormatTests {

  // MARK: - phaseSteps

  @Test func phaseStepsProducesGlyphAndLabelInOrder() {
    let steps = GalleryScenarioDetailFormat.phaseSteps(phases: ["speak_each", "summarize"])
    #expect(steps.map(\.symbol) == ["bubble.left", "list.bullet.rectangle"])
    #expect(steps.map(\.label) == ["Speak Each", "Summarize"])
  }

  @Test func phaseStepsSkipsUnknownKinds() {
    let steps = GalleryScenarioDetailFormat.phaseSteps(phases: ["vote", "bogus_kind", "assign"])
    #expect(steps.map(\.symbol) == ["checkmark.square", "tag"])
    #expect(steps.map(\.label) == ["Vote", "Assign"])
  }

  @Test func phaseStepsEmptyWhenAbsent() {
    #expect(GalleryScenarioDetailFormat.phaseSteps(phases: nil).isEmpty)
  }

  @Test func phaseStepsEmptyWhenEmpty() {
    #expect(GalleryScenarioDetailFormat.phaseSteps(phases: []).isEmpty)
  }

  @Test func phaseStepsEmptyWhenAllUnknown() {
    #expect(GalleryScenarioDetailFormat.phaseSteps(phases: ["nope", "nada"]).isEmpty)
  }

  // MARK: - languageLabel

  @Test func languageLabelMapsLaunchLanguages() {
    #expect(GalleryScenarioDetailFormat.languageLabel(code: "ja") != nil)
    #expect(GalleryScenarioDetailFormat.languageLabel(code: "en") != nil)
    // Distinct names — not the same fallback string.
    #expect(
      GalleryScenarioDetailFormat.languageLabel(code: "ja")
        != GalleryScenarioDetailFormat.languageLabel(code: "en"))
  }

  @Test func languageLabelNilWhenAbsentOrUnknown() {
    #expect(GalleryScenarioDetailFormat.languageLabel(code: nil) == nil)
    #expect(GalleryScenarioDetailFormat.languageLabel(code: "fr") == nil)
  }

  // MARK: - yamlFragmentForDisplay (ADR-029)

  @Test func yamlFragmentTrimsTrailingNewline() {
    #expect(
      GalleryScenarioDetailFormat.yamlFragmentForDisplay("personas:\n  - name: A\n")
        == "personas:\n  - name: A")
  }

  @Test func yamlFragmentTrimsRepeatedTrailingWhitespace() {
    #expect(
      GalleryScenarioDetailFormat.yamlFragmentForDisplay("a: 1\nb: 2\n\n  \n")
        == "a: 1\nb: 2")
  }

  @Test func yamlFragmentPreservesLeadingIndentation() {
    // Leading offset is load-bearing YAML structure — only the tail is trimmed.
    #expect(
      GalleryScenarioDetailFormat.yamlFragmentForDisplay("  description: |\n    hi\n")
        == "  description: |\n    hi")
  }

  @Test func yamlFragmentLeavesAlreadyTrimmedFragmentUnchanged() {
    #expect(GalleryScenarioDetailFormat.yamlFragmentForDisplay("a: 1") == "a: 1")
  }

  @Test func yamlFragmentHandlesAllWhitespaceInput() {
    #expect(GalleryScenarioDetailFormat.yamlFragmentForDisplay("\n \n").isEmpty)
  }

  // MARK: - installAlert (ADR-020 D5)

  @Test func installAlertNilForNavigatingOutcomes() {
    // .installed / .updated push to the local copy — no alert.
    #expect(GalleryScenarioDetailFormat.installAlert(for: .installed(scenarioId: "x")) == nil)
    #expect(GalleryScenarioDetailFormat.installAlert(for: .updated(scenarioId: "x")) == nil)
  }

  @Test func installAlertUpdateRequiredGivesForwardGuidance() {
    let alert = GalleryScenarioDetailFormat.installAlert(for: .updateRequired)
    #expect(alert?.title == "Update required")
    // Forward-guidance, not a "download"/"parse" dead-end.
    #expect(alert?.message.contains("newer version of Pastura") == true)
  }

  @Test func installAlertNetworkErrorPassesDescriptionThrough() {
    let alert = GalleryScenarioDetailFormat.installAlert(for: .networkError("boom"))
    #expect(alert?.message == "boom")
  }

  // MARK: - Highlight excerpt rows

  private func entry(
    agent: String, round: Int = 1, phase: String = "speak_each"
  ) -> GalleryHighlightExcerptEntry {
    GalleryHighlightExcerptEntry(
      agent: agent, round: round, phase: phase, phaseIndex: 0,
      sourceField: "statement", text: "…")
  }

  @Test func avatarSlotsFollowOrderOfFirstAppearance() {
    let rows = GalleryScenarioDetailFormat.excerptRows(
      [entry(agent: "A"), entry(agent: "B"), entry(agent: "A"), entry(agent: "C")],
      totalRounds: 3)

    // A keeps slot 0 on its second line — the map is keyed by name, not by row.
    #expect(rows.map(\.agentPosition) == [0, 1, 0, 2])
  }

  @Test func fifthSpeakerCollidesWithTheFirstJustAsTheAppDoes() {
    let rows = GalleryScenarioDetailFormat.excerptRows(
      ["A", "B", "C", "D", "E"].map { entry(agent: $0) }, totalRounds: 3)

    // Four colour slots, so `allCases[position % 4]` puts the fifth speaker on
    // the first one's colour. `SheepAvatar` collides identically for a 5-agent
    // scenario, so this is fidelity — asserted so a future "fix" has to be a
    // deliberate divergence from the app.
    #expect(rows.map(\.agentPosition) == [0, 1, 2, 3, 4])
    #expect(rows.map { $0.agentPosition % 4 } == [0, 1, 2, 3, 0])
  }

  @Test func aDividerOpensOnlyWhereTheRoundChanges() {
    let rows = GalleryScenarioDetailFormat.excerptRows(
      [
        entry(agent: "A", round: 1), entry(agent: "B", round: 1),
        entry(agent: "A", round: 2), entry(agent: "B", round: 2)
      ], totalRounds: 3)

    // Never above the first row — the head already names that round.
    #expect(rows.map { $0.dividerLabel != nil } == [false, false, true, false])
    #expect(rows[2].dividerLabel == "Round 2 / 3")
  }

  @Test func aDividerDropsTheTotalWhenTheFeedOmitsRounds() {
    let rows = GalleryScenarioDetailFormat.excerptRows(
      [entry(agent: "A", round: 1), entry(agent: "A", round: 2)], totalRounds: nil)

    // Degrades to the total-less key rather than vanishing: both rounds are
    // present in the passage, so the boundary is still real.
    #expect(rows[1].dividerLabel == "Round 2")
  }

  @Test func anUnmappablePhaseYieldsNoRowsAtAll() {
    let rows = GalleryScenarioDetailFormat.excerptRows(
      [entry(agent: "A"), entry(agent: "B", phase: "interpretive_dance")],
      totalRounds: 3)

    // Defence in depth behind `GalleryHighlightLoader`'s own gate — the whole
    // passage goes, never just the offending line (ADR-029 § Amendment
    // 2026-08-07).
    #expect(rows.isEmpty)
  }

  @Test func mappablePhasesYieldOneRowEach() {
    // Positive control for the case above: same call shape, mappable phases.
    let rows = GalleryScenarioDetailFormat.excerptRows(
      [entry(agent: "A"), entry(agent: "B", phase: "speak_all")], totalRounds: 3)

    #expect(rows.count == 2)
    #expect(rows.map(\.phaseType) == [.speakEach, .speakAll])
    #expect(rows.map(\.id) == [0, 1])
  }

  // MARK: - Highlight head round label

  @Test func theHeadNamesTheFirstExcerptedRoundNotRoundOne() {
    let label = GalleryScenarioDetailFormat.excerptHeadRoundLabel(
      [entry(agent: "A", round: 2), entry(agent: "B", round: 3)], totalRounds: 4)

    // A highlight is usually quoted from partway in; the head describes the
    // passage below it, not the scenario.
    #expect(label == "Round 2 / 4")
  }

  @Test func theHeadCollapsesWithoutATotal() {
    let label = GalleryScenarioDetailFormat.excerptHeadRoundLabel(
      [entry(agent: "A", round: 2)], totalRounds: nil)

    // Pair-or-nothing: "Round 2" alone states a position with no whole.
    #expect(label == nil)
  }

  @Test func theHeadCollapsesOnAnEmptyExcerpt() {
    #expect(GalleryScenarioDetailFormat.excerptHeadRoundLabel([], totalRounds: 4) == nil)
  }
}
