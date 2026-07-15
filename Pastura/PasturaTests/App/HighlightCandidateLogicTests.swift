import Foundation
import Testing

@testable import Pastura

/// Unit coverage for the pure share-highlight candidate selection logic
/// (#1070 Stage 2).
///
/// The two zero-inference signals (contradiction badges #916, prediction
/// reveal #915) and their de-dup / cap / ordering interaction are pinned
/// here; the ViewModel owns only the transcript→descriptor projection and
/// card construction, which this suite deliberately does not exercise
/// (ADR-009 / `.claude/rules/view-testing.md`).
///
/// `@MainActor` on the suite is the swift-isolation Pattern-5 fix: the
/// `Selection`/`Entry` auto-synth `Equatable` *lookup* is released for the
/// nonisolated logic, and a MainActor suite can still call it.
@Suite(.timeLimit(.minutes(1)))
@MainActor
struct HighlightCandidateLogicTests {

  // MARK: Helpers

  private func entry(
    _ agent: String,
    _ phaseType: PhaseType = .speakAll,
    contradiction: Bool = false,
    id: UUID = UUID()
  ) -> HighlightCandidateLogic.Entry {
    HighlightCandidateLogic.Entry(
      id: id, agent: agent, phaseType: phaseType, isContradiction: contradiction)
  }

  // MARK: Contradiction signal

  @Test func contradictionEntriesBecomeCandidatesInOrder() {
    let aliceCon = entry("Alice", contradiction: true)
    let bobCon = entry("Bob", .speakEach, contradiction: true)
    let carolPlain = entry("Carol")
    let result = HighlightCandidateLogic.candidates(
      entries: [aliceCon, carolPlain, bobCon], actualAgent: nil)
    #expect(
      result == [
        .init(id: aliceCon.id, reason: .contradiction),
        .init(id: bobCon.id, reason: .contradiction)
      ])
  }

  @Test func noSignalsYieldsEmpty() {
    let result = HighlightCandidateLogic.candidates(
      entries: [entry("Alice"), entry("Bob")], actualAgent: nil)
    #expect(result.isEmpty)
  }

  // MARK: Reveal signal

  @Test func revealPicksActualAgentLastSpeakEntry() {
    let first = entry("Wolf")
    let vote = entry("Wolf", .vote)
    let last = entry("Wolf")
    let result = HighlightCandidateLogic.candidates(
      entries: [first, vote, last], actualAgent: "Wolf")
    // The reveal is the *last* speak-phase entry, not the vote and not the first.
    #expect(result == [.init(id: last.id, reason: .revealed)])
  }

  @Test func revealSkippedWhenActualAgentNeverSpoke() {
    // The actual agent only ever voted — no speak-phase utterance to quote.
    let result = HighlightCandidateLogic.candidates(
      entries: [entry("Wolf", .vote), entry("Alice")], actualAgent: "Wolf")
    #expect(result.isEmpty)
  }

  @Test func revealSkippedWhenNoPredictionScored() {
    let result = HighlightCandidateLogic.candidates(
      entries: [entry("Alice"), entry("Bob")], actualAgent: nil)
    #expect(result.isEmpty)
  }

  // MARK: De-dup (contradiction wins)

  @Test func revealEntryThatIsAlsoContradictionAppearsOnceAsContradiction() {
    let wolf = entry("Wolf", contradiction: true)
    let result = HighlightCandidateLogic.candidates(
      entries: [wolf], actualAgent: "Wolf")
    #expect(result == [.init(id: wolf.id, reason: .contradiction)])
  }

  @Test func contradictionAndRevealOnDistinctEntriesBothSurface() {
    let liar = entry("Bob", contradiction: true)
    let wolfSpeak = entry("Wolf")
    let result = HighlightCandidateLogic.candidates(
      entries: [liar, wolfSpeak], actualAgent: "Wolf")
    #expect(
      result == [
        .init(id: liar.id, reason: .contradiction),
        .init(id: wolfSpeak.id, reason: .revealed)
      ])
  }

  // MARK: Cap + ordering

  @Test func capLimitsCountAndEvictsRevealWhenFull() {
    let conA = entry("A", contradiction: true)
    let conB = entry("B", contradiction: true)
    let conC = entry("C", contradiction: true)
    let wolfSpeak = entry("Wolf")  // chronologically last → evicted at cap 3
    let result = HighlightCandidateLogic.candidates(
      entries: [conA, conB, conC, wolfSpeak], actualAgent: "Wolf", limit: 3)
    #expect(
      result == [
        .init(id: conA.id, reason: .contradiction),
        .init(id: conB.id, reason: .contradiction),
        .init(id: conC.id, reason: .contradiction)
      ])
  }

  @Test func candidatesStayInTranscriptOrder() {
    let earlyCon = entry("A", contradiction: true)
    let wolfSpeak = entry("Wolf")  // appears before the later contradiction
    let lateCon = entry("B", contradiction: true)
    let result = HighlightCandidateLogic.candidates(
      entries: [earlyCon, wolfSpeak, lateCon], actualAgent: "Wolf")
    #expect(result.map(\.id) == [earlyCon.id, wolfSpeak.id, lateCon.id])
    #expect(result.map(\.reason) == [.contradiction, .revealed, .contradiction])
  }
}
