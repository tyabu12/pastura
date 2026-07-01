import Testing

@testable import Pastura

/// Unit coverage of the pure ``GalleryScenarioDetailFormat`` helpers backing
/// the shared-scenario detail screen's enriched metadata rows and the
/// "What happens" phase flow (view-testing.md rule 1 — logic extracted from
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

  // MARK: - phaseFlow

  @Test func phaseFlowJoinsLabelsInOrder() {
    #expect(
      GalleryScenarioDetailFormat.phaseFlow(phases: ["speak_each", "summarize"])
        == "Speak Each → Summarize")
  }

  @Test func phaseFlowPreservesGivenOrder() {
    #expect(
      GalleryScenarioDetailFormat.phaseFlow(phases: ["summarize", "vote", "assign"])
        == "Summarize → Vote → Assign")
  }

  @Test func phaseFlowNilWhenAbsent() {
    #expect(GalleryScenarioDetailFormat.phaseFlow(phases: nil) == nil)
  }

  @Test func phaseFlowNilWhenEmpty() {
    #expect(GalleryScenarioDetailFormat.phaseFlow(phases: []) == nil)
  }

  @Test func phaseFlowSkipsUnknownKinds() {
    // A feed newer than this build carries a phase kind we don't know — it is
    // skipped, and the known ones still render.
    #expect(
      GalleryScenarioDetailFormat.phaseFlow(phases: ["future_kind", "vote"]) == "Vote")
  }

  @Test func phaseFlowNilWhenAllUnknown() {
    // Non-empty but every entry maps away → section hidden, not an empty box.
    #expect(GalleryScenarioDetailFormat.phaseFlow(phases: ["future_kind", "another"]) == nil)
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
