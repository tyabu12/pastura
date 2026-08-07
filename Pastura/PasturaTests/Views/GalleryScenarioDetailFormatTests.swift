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

    #expect(rows.map(\.agentPosition) == [0, 1, 2, 3, 4])
    // Four colour slots, so the fifth speaker lands on the first one's colour.
    // Pinned against the real resolver rather than by restating `4 % 4 == 0`:
    // the claim is that `SheepAvatar` collides identically for a 5-agent
    // scenario (`asch_conformity_v1` really has five), so a future "fix" here
    // has to be a deliberate divergence from the app.
    #expect(
      SheepAvatar.Character.forAgent("E", position: 4)
        == SheepAvatar.Character.forAgent("A", position: 0))
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

  @Test func aFieldlessPhaseYieldsNoRowsEither() {
    let rows = GalleryScenarioDetailFormat.excerptRows(
      [entry(agent: "A"), entry(agent: "B", phase: "summarize")], totalRounds: 3)

    // `summarize` maps to a `PhaseType` but declares no primary output field,
    // so there is no key to hang the line on — same outcome, second half of
    // the renderability predicate. Keeps this in step with the loader.
    #expect(rows.isEmpty)
  }

  @Test func mappablePhasesYieldOneRowEachKeyedByTheirOwnField() {
    // Positive control for the two cases above: same call shape, renderable
    // phases. `vote` is included because it is the case a hardcoded
    // `"statement"` key would have rendered as a speaker with no line.
    let rows = GalleryScenarioDetailFormat.excerptRows(
      [entry(agent: "A"), entry(agent: "B", phase: "vote")], totalRounds: 3)

    #expect(rows.count == 2)
    #expect(rows.map(\.phaseType) == [.speakEach, .vote])
    #expect(rows.map(\.primaryField) == ["statement", "vote"])
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

  @Test func theHeadDropsTheTotalWhenTheFeedOmitsRounds() {
    let label = GalleryScenarioDetailFormat.excerptHeadRoundLabel(
      [entry(agent: "A", round: 2), entry(agent: "B", round: 3)], totalRounds: nil)

    // Degrades like a divider rather than collapsing. Collapsing here while the
    // round-3 divider still printed would leave the opening round unnamed.
    #expect(label == "Round 2")
  }

  @Test func theHeadCollapsesOnAnEmptyExcerpt() {
    #expect(GalleryScenarioDetailFormat.excerptHeadRoundLabel([], totalRounds: 4) == nil)
  }
}
