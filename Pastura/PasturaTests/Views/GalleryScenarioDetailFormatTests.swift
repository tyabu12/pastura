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
}
