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
    reaction: Bool = false,
    id: UUID = UUID()
  ) -> HighlightCandidateLogic.Entry {
    HighlightCandidateLogic.Entry(
      id: id, agent: agent, phaseType: phaseType,
      isContradiction: contradiction, isReaction: reaction)
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

  /// Characterization guard (#1109 critic): tier-1 stays transcript-ordered,
  /// NOT priority-first. A reveal positioned before later contradictions must
  /// survive the cap — a priority-first refactor (all contradictions, then
  /// reveal) would evict it, and no other test catches that regression.
  @Test func revealSurvivesMidStreamWhenLaterContradictionsWouldFillCap() {
    let conEarly = entry("A", contradiction: true)
    let wolfSpeak = entry("Wolf")  // reveal, positionally before later cons
    let conMid = entry("B", contradiction: true)
    let conLate = entry("C", contradiction: true)
    let result = HighlightCandidateLogic.candidates(
      entries: [conEarly, wolfSpeak, conMid, conLate], actualAgent: "Wolf", limit: 3)
    #expect(
      result == [
        .init(id: conEarly.id, reason: .contradiction),
        .init(id: wolfSpeak.id, reason: .revealed),
        .init(id: conMid.id, reason: .contradiction)
      ])
  }

  // MARK: Reaction correlation (reactionEntryIDs)

  @Test func reactionIsFirstSpeakOutputAfterEventBoundary() {
    let speak = UUID()
    let ids = HighlightCandidateLogic.reactionEntryIDs([
      .eventBoundary,
      .output(id: speak, phaseType: .speakAll)
    ])
    #expect(ids == [speak])
  }

  @Test func onlyTheFirstSpeakAfterABoundaryReacts() {
    let first = UUID()
    let second = UUID()
    let ids = HighlightCandidateLogic.reactionEntryIDs([
      .eventBoundary,
      .output(id: first, phaseType: .speakEach),
      .output(id: second, phaseType: .speakEach)
    ])
    #expect(ids == [first])
  }

  @Test func nonSpeakOutputIsSkippedWithoutDisarming() {
    let voteOut = UUID()
    let speak = UUID()
    let ids = HighlightCandidateLogic.reactionEntryIDs([
      .eventBoundary,
      .output(id: voteOut, phaseType: .vote),  // non-speak: skipped, stays armed
      .output(id: speak, phaseType: .speakAll)
    ])
    #expect(ids == [speak])
  }

  @Test func roundBoundaryClosesWindowSoTailEventDoesNotReachNextRound() {
    // A vote reveal at a round's tail, followed by the next round's opening
    // speak: the round boundary must close the window so it does not react.
    let nextRoundSpeak = UUID()
    let ids = HighlightCandidateLogic.reactionEntryIDs([
      .eventBoundary,
      .roundBoundary,
      .output(id: nextRoundSpeak, phaseType: .speakAll)
    ])
    #expect(ids.isEmpty)
  }

  @Test func noEventBoundaryYieldsNoReactions() {
    let ids = HighlightCandidateLogic.reactionEntryIDs([
      .output(id: UUID(), phaseType: .speakAll),
      .roundBoundary,
      .output(id: UUID(), phaseType: .speakEach)
    ])
    #expect(ids.isEmpty)
  }

  @Test func eachEventBoundaryGetsItsOwnFirstReaction() {
    let firstReact = UUID()
    let secondReact = UUID()
    let ids = HighlightCandidateLogic.reactionEntryIDs([
      .eventBoundary,
      .output(id: firstReact, phaseType: .speakEach),
      .roundBoundary,
      .eventBoundary,
      .output(id: secondReact, phaseType: .speakAll)
    ])
    #expect(ids == [firstReact, secondReact])
  }

  @Test func skippedFirstSpeakerShiftsReactionToNextActualSpeaker() {
    // The agent who would speak first after the event was skipped (ADR-021):
    // a skipped turn emits no `.output`, so the first output present is the
    // next agent who actually spoke, and that becomes the reaction.
    let bobSpeak = UUID()
    let ids = HighlightCandidateLogic.reactionEntryIDs([
      .eventBoundary,
      .output(id: bobSpeak, phaseType: .speakEach)  // Alice skipped ⇒ absent
    ])
    #expect(ids == [bobSpeak])
  }

  // MARK: Reaction tier (fills only remaining slots)

  @Test func reactionFillsSlotLeftFreeByStrongerSignals() {
    let con = entry("Alice", contradiction: true)
    let react = entry("Bob", reaction: true)
    let result = HighlightCandidateLogic.candidates(
      entries: [con, react], actualAgent: nil)
    #expect(
      result == [
        .init(id: con.id, reason: .contradiction),
        .init(id: react.id, reason: .reaction)
      ])
  }

  @Test func reactionEntryThatIsAlsoContradictionKeepsContradiction() {
    let both = entry("Alice", contradiction: true, reaction: true)
    let result = HighlightCandidateLogic.candidates(
      entries: [both], actualAgent: nil)
    #expect(result == [.init(id: both.id, reason: .contradiction)])
  }

  @Test func reactionDoesNotEvictStrongerSignalsWhenCapFilledByTier1() {
    let conA = entry("A", contradiction: true)
    let conB = entry("B", contradiction: true)
    let conC = entry("C", contradiction: true)
    let react = entry("D", reaction: true)  // no free slot left → dropped
    let result = HighlightCandidateLogic.candidates(
      entries: [conA, conB, conC, react], actualAgent: nil, limit: 3)
    #expect(result.map(\.id) == [conA.id, conB.id, conC.id])
    #expect(result.allSatisfy { $0.reason == .contradiction })
  }

  @Test func reactionSelectedInTier2IsSortedBackIntoTranscriptOrder() {
    let react = entry("Alice", reaction: true)  // position 0
    let con = entry("Bob", contradiction: true)  // position 1
    let result = HighlightCandidateLogic.candidates(
      entries: [react, con], actualAgent: nil)
    // con is chosen first (tier 1), react second (tier 2), but the final
    // output restores transcript order: react (pos 0) precedes con (pos 1).
    #expect(
      result == [
        .init(id: react.id, reason: .reaction),
        .init(id: con.id, reason: .contradiction)
      ])
  }
}
