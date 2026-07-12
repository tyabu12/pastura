import Foundation
import Testing

@testable import Pastura

/// Covers `EditablePhase.reconcileCanonicalOutputFields(from:)` — the editor
/// authoring default that seeds / swaps canonical output fields per phase
/// type (#802). `inner_thought` stays OPTIONAL by design (#760); these tests
/// pin the editor default behavior, not a validation requirement.
@Suite(.timeLimit(.minutes(1)))
@MainActor
struct EditablePhaseTests {

  // MARK: - Seeding a brand-new phase (oldType == nil)

  @Test func seedSpeakAllAddsStatementAndInnerThought() {
    var sut = EditablePhase(type: .speakAll)
    sut.reconcileCanonicalOutputFields(from: nil)
    #expect(sut.outputFields == ["statement": "string", "inner_thought": "string"])
  }

  @Test func seedSpeakEachAddsStatementAndInnerThought() {
    var sut = EditablePhase(type: .speakEach)
    sut.reconcileCanonicalOutputFields(from: nil)
    #expect(sut.outputFields == ["statement": "string", "inner_thought": "string"])
  }

  @Test func seedVoteAddsVoteAndReason() {
    var sut = EditablePhase(type: .vote)
    sut.reconcileCanonicalOutputFields(from: nil)
    #expect(sut.outputFields == ["vote": "string", "reason": "string"])
  }

  @Test func seedChooseAddsActionAndInnerThought() {
    var sut = EditablePhase(type: .choose)
    sut.reconcileCanonicalOutputFields(from: nil)
    #expect(sut.outputFields == ["action": "string", "inner_thought": "string"])
  }

  @Test func seedReflectAddsNoteOnly() {
    // reflect's canonical primary is `note` and it has no secondary thought
    // field, so seeding adds exactly `{ note }`.
    var sut = EditablePhase(type: .reflect)
    sut.reconcileCanonicalOutputFields(from: nil)
    #expect(sut.outputFields == ["note": "string"])
  }

  @Test func seedCodePhaseAddsNothing() {
    for type in [PhaseType.scoreCalc, .assign, .eliminate, .summarize, .conditional, .eventInject] {
      var sut = EditablePhase(type: type)
      sut.reconcileCanonicalOutputFields(from: nil)
      #expect(sut.outputFields.isEmpty, "code phase \(type.rawValue) should seed no output fields")
    }
  }

  // MARK: - Type swap

  @Test func swapSpeakToVoteSwapsCanonicalFields() {
    var sut = EditablePhase(
      type: .vote, outputFields: ["statement": "string", "inner_thought": "string"])
    sut.reconcileCanonicalOutputFields(from: .speakAll)
    #expect(sut.outputFields == ["vote": "string", "reason": "string"])
  }

  @Test func swapSpeakToChooseKeepsSharedInnerThought() {
    // inner_thought is canonical for both speak and choose, so it survives;
    // statement (speak primary) is dropped, action (choose primary) added.
    var sut = EditablePhase(
      type: .choose, outputFields: ["statement": "string", "inner_thought": "string"])
    sut.reconcileCanonicalOutputFields(from: .speakAll)
    #expect(sut.outputFields == ["action": "string", "inner_thought": "string"])
  }

  @Test func swapIntoCodePhaseRemovesCanonicalFields() {
    var sut = EditablePhase(
      type: .scoreCalc, outputFields: ["statement": "string", "inner_thought": "string"])
    sut.reconcileCanonicalOutputFields(from: .speakAll)
    #expect(sut.outputFields.isEmpty)
  }

  // MARK: - Custom-field preservation

  @Test func swapPreservesCustomFields() {
    var sut = EditablePhase(
      type: .vote,
      outputFields: ["statement": "string", "inner_thought": "string", "mood": "string"])
    sut.reconcileCanonicalOutputFields(from: .speakAll)
    #expect(sut.outputFields == ["vote": "string", "reason": "string", "mood": "string"])
  }

  @Test func customValueOnCanonicalKeyIsDiscardedOnSwap() {
    // outputFields values are type-hints, never author content, so dropping a
    // stale canonical key on type-swap discards nothing meaningful (documented
    // intended behavior — Step 1b critic).
    var sut = EditablePhase(
      type: .vote, outputFields: ["statement": "customtype", "inner_thought": "string"])
    sut.reconcileCanonicalOutputFields(from: .speakAll)
    #expect(sut.outputFields["statement"] == nil)
    #expect(sut.outputFields == ["vote": "string", "reason": "string"])
  }

  // MARK: - Idempotency

  @Test func reapplyingSameTypeIsNoOp() {
    var sut = EditablePhase(
      type: .speakAll, outputFields: ["statement": "string", "inner_thought": "string"])
    sut.reconcileCanonicalOutputFields(from: .speakAll)
    #expect(sut.outputFields == ["statement": "string", "inner_thought": "string"])
  }

  @Test func seedThenImmediateSwapHasNoOrphanedFields() {
    // Mirrors the editor flow: onAppear seeds a fresh speak phase, then the
    // user immediately picks vote — onChange fires with the seeded type as old.
    var sut = EditablePhase(type: .speakAll)
    sut.reconcileCanonicalOutputFields(from: nil)
    sut.type = .vote
    sut.reconcileCanonicalOutputFields(from: .speakAll)
    #expect(sut.outputFields == ["vote": "string", "reason": "string"])
  }

  // MARK: - Nested sub-phase parity (the recursive seed path is per-instance)

  @Test func seedWorksOnPhaseUsedAsSubPhase() {
    // A nested sub-phase is just another EditablePhase; the editor seeds it via
    // the same per-instance call, so reconcile must behave identically.
    var subPhase = EditablePhase(type: .speakAll)
    subPhase.reconcileCanonicalOutputFields(from: nil)
    let parent = EditablePhase(type: .conditional, thenPhases: [subPhase])
    #expect(
      parent.thenPhases.first?.outputFields == ["statement": "string", "inner_thought": "string"])
  }

  // MARK: - relationship_update config round-trip (#910)

  /// The editor has no visual UI for `vote_against` / `action_deltas`, so the
  /// only thing keeping them alive across a visual→YAML materialization is
  /// EditablePhase modelling + `toPhase()`. Without this round-trip a user who
  /// merely opens a relationship_update scenario in visual mode would drop its
  /// affinity rules on re-serialization.
  @Test func relationshipUpdateConfigSurvivesRoundTrip() {
    let phase = Phase(
      type: .relationshipUpdate,
      voteAgainst: -1,
      actionDeltas: ["cooperate": 1, "betray": -2]
    )
    let restored = EditablePhase(from: phase).toPhase()
    #expect(restored.type == .relationshipUpdate)
    #expect(restored.voteAgainst == -1)
    #expect(restored.actionDeltas == ["cooperate": 1, "betray": -2])
  }

  @Test func relationshipUpdateEmptyRulesRoundTripAsNil() {
    // Absent rules → EditablePhase holds `nil` / `[:]` → toPhase() emits `nil`
    // (empty map is not serialized), matching the loader's absent-field shape.
    let restored = EditablePhase(from: Phase(type: .relationshipUpdate)).toPhase()
    #expect(restored.voteAgainst == nil)
    #expect(restored.actionDeltas == nil)
  }

  // MARK: - reconcileMaxSentences (#881 Stage 2 PR-B — switch-away no-op guard)

  /// Switching an LLM phase with a `max_sentences` override to a code phase must
  /// clear the override — otherwise the value stays hidden (the editor gates the
  /// control to LLM phases) yet round-trips into the code phase and trips R18.
  @Test func reconcileMaxSentencesClearsOverrideOnSwitchToCodePhase() {
    var sut = EditablePhase(type: .speakAll, maxSentences: 4)
    sut.type = .scoreCalc
    sut.reconcileMaxSentences()
    #expect(sut.maxSentences == nil)
  }

  @Test func reconcileMaxSentencesPreservesOverrideOnLLMToLLMSwitch() {
    var sut = EditablePhase(type: .speakAll, maxSentences: 4)
    sut.type = .vote
    sut.reconcileMaxSentences()
    #expect(sut.maxSentences == 4)
  }

  @Test func reconcileMaxSentencesIsNoOpWhenAlreadyNil() {
    var sut = EditablePhase(type: .eliminate)
    sut.reconcileMaxSentences()
    #expect(sut.maxSentences == nil)
  }
}
