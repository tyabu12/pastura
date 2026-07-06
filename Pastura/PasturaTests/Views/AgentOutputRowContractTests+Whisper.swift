import Testing

@testable import Pastura

// Sibling extension of `AgentOutputRowContractTests` per
// `.claude/rules/testing.md` § "Splitting a Suite Across Files" — keeps the
// original file under swiftlint's 400-line `file_length` cap. Inherits the
// parent suite's `@MainActor` + `@Suite(.timeLimit(.minutes(1)))` traits (DO
// NOT add a new `@Suite` here — sibling suites race on shared state).
//
// ## Whisper pair-attribution (#908 PR2)
//
// The whisper (密談) UI variant differentiates a whisper row two ways: the
// hushed `whisperBubble` fill (gated on the phase alone, so it applies while
// streaming) and an iconless `"speaker → partner"` header (gated on a
// non-blank reserved `whisper_to` field, so it only appears once the partner
// name arrives at commit). Both derive from pure inputs — the reveal state
// machine is untouched — so they are exercised here without a SwiftUI host.
extension AgentOutputRowContractTests {

  // MARK: - Static resolver

  @Test func whisperAttributionFormatsSpeakerToPartner() {
    let result = AgentOutputRow.whisperAttribution(
      phaseType: .whisper, speaker: "Alice", fields: ["whisper_to": "Bob"])
    #expect(result == "Alice → Bob")
  }

  @Test func whisperAttributionIsNilForNonWhisperPhase() {
    // A speak_all row that happens to carry a stray whisper_to must NOT
    // render the pair header — the phase gate comes first.
    let result = AgentOutputRow.whisperAttribution(
      phaseType: .speakAll, speaker: "Alice", fields: ["whisper_to": "Bob"])
    #expect(result == nil)
  }

  @Test func whisperAttributionIsNilWhenPartnerAbsent() {
    // Streaming whisper rows carry no whisper_to yet → no header (tint only).
    let result = AgentOutputRow.whisperAttribution(
      phaseType: .whisper, speaker: "Alice", fields: ["statement": "psst"])
    #expect(result == nil)
  }

  @Test func whisperAttributionIsNilWhenPartnerBlank() {
    // A blocklist-redacted / whitespace-only whisper_to must fall back to the
    // plain row rather than render a dangling "Alice → ".
    let result = AgentOutputRow.whisperAttribution(
      phaseType: .whisper, speaker: "Alice", fields: ["whisper_to": "   "])
    #expect(result == nil)
  }

  // MARK: - Row-derived properties

  @Test func isWhisperPhaseTracksPhaseNotPartner() {
    // Tint gate is the phase alone — true even before whisper_to arrives.
    let streaming = AgentOutputRow(
      agent: "Alice",
      output: TurnOutput(fields: [:]),
      phaseType: .whisper,
      showAllThoughts: false,
      isLatest: true,
      charsPerSecond: 60)
    #expect(streaming.isWhisperPhase)
    #expect(streaming.whisperAttribution == nil)

    let publicRow = AgentOutputRow(
      agent: "Alice",
      output: TurnOutput(fields: ["statement": "hi", "whisper_to": "Bob"]),
      phaseType: .speakAll,
      showAllThoughts: false,
      isLatest: true,
      charsPerSecond: 60)
    #expect(!publicRow.isWhisperPhase)
    #expect(publicRow.whisperAttribution == nil)
  }

  @Test func whisperAttributionReadsCommittedPartnerField() {
    let committed = AgentOutputRow(
      agent: "Alice",
      output: TurnOutput(fields: ["statement": "psst", "whisper_to": "Bob"]),
      phaseType: .whisper,
      showAllThoughts: false,
      isLatest: false,
      charsPerSecond: 60)
    #expect(committed.isWhisperPhase)
    #expect(committed.whisperAttribution == "Alice → Bob")
  }
}
