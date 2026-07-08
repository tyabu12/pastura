// Handler-anchored tests for the linter-owned placeholder availability map
// (ADR-024 D4). Each per-row test names the handler it mirrors so a handler
// change that drifts the map fails here with a legible pointer. The union test
// is the ADR's phantom/missing-token maintenance guard.
import Testing

@testable import Pastura

@Suite(.timeLimit(.minutes(1)))
struct PlaceholderAvailabilityTests {

  // MARK: - Union guard (ADR-024 maintenance point)

  @Test func unionOfSuppliedEqualsEngineSuppliedPlusDocumentedDelta() {
    var union: Set<String> = []
    for phaseType in PhaseType.allCases {
      union.formUnion(PlaceholderAvailability.supplied(for: phaseType, chooseRoundRobin: true))
      union.formUnion(PlaceholderAvailability.supplied(for: phaseType, chooseRoundRobin: false))
    }
    let expected = PromptPlaceholders.engineSupplied.union(
      PlaceholderAvailability.tokensBeyondEngineSupplied)
    #expect(union == expected)
  }

  @Test func everyEngineSuppliedTokenIsSuppliedBySomePhase() {
    var union: Set<String> = []
    for phaseType in PhaseType.allCases {
      union.formUnion(PlaceholderAvailability.supplied(for: phaseType, chooseRoundRobin: true))
    }
    // No engine-supplied token is orphaned (the "missing token" half of the guard).
    #expect(PromptPlaceholders.engineSupplied.isSubset(of: union))
  }

  @Test func deltaTokensAreDisjointFromEngineSupplied() {
    // The delta names tokens engineSupplied does NOT carry — if one were added
    // there, this catches the stale duplication.
    #expect(
      PlaceholderAvailability.tokensBeyondEngineSupplied
        .isDisjoint(with: PromptPlaceholders.engineSupplied))
  }

  // MARK: - Cross-phase readable set (#920 B editor-hint source)

  /// `crossPhaseStateReadable` is the producer-gated tokens minus the
  /// per-persona / whisper injected forms — the state-variable tokens any LLM
  /// phase's prompt can read. Pins the derived value so a `producerMap` /
  /// `perPersonaInjected` change that shifts it fails here.
  @Test func crossPhaseStateReadableIsProducerTokensMinusPerPersona() {
    #expect(
      PlaceholderAvailability.crossPhaseStateReadable
        == ["assigned_topic", "wolf_name", "vote_results", "current_event"])
  }

  // MARK: - Vote (VoteHandler)

  @Test func candidatesSuppliedByVoteOnly() {
    for phaseType in PhaseType.allCases {
      let hasCandidates =
        PlaceholderAvailability
        .supplied(for: phaseType, chooseRoundRobin: true)
        .contains("candidates")
      #expect(hasCandidates == (phaseType == .vote))
    }
  }

  @Test func voteResultsSuppliedByVote() {
    #expect(
      PlaceholderAvailability.supplied(for: .vote, chooseRoundRobin: false)
        .contains("vote_results"))
  }

  // MARK: - Choose (ChooseHandler round-robin qualifier)

  @Test func opponentNameSuppliedByChooseRoundRobinOnly() {
    #expect(
      PlaceholderAvailability.supplied(for: .choose, chooseRoundRobin: true)
        .contains("opponent_name"))
    #expect(
      !PlaceholderAvailability.supplied(for: .choose, chooseRoundRobin: false)
        .contains("opponent_name"))
    // Absent from every non-choose phase, under either qualifier value.
    for phaseType in PhaseType.allCases where phaseType != .choose {
      #expect(
        !PlaceholderAvailability.supplied(for: phaseType, chooseRoundRobin: true)
          .contains("opponent_name"))
    }
  }

  @Test func chooseIndividualOmitsWhisperChannel() {
    // executeIndividual does not call injectWhispers.
    #expect(
      PlaceholderAvailability.supplied(for: .choose, chooseRoundRobin: true)
        .contains("my_whispers"))
    #expect(
      !PlaceholderAvailability.supplied(for: .choose, chooseRoundRobin: false)
        .contains("my_whispers"))
  }

  // MARK: - Whisper (WhisperHandler in-phase tokens)

  @Test func whisperInPhaseTokensSuppliedByWhisperOnly() {
    for token in ["whisper_partner", "whisper_exchange"] {
      for phaseType in PhaseType.allCases {
        let supplied =
          PlaceholderAvailability
          .supplied(for: phaseType, chooseRoundRobin: true)
          .contains(token)
        #expect(supplied == (phaseType == .whisper))
      }
    }
  }

  // MARK: - Per-persona tokens absent from summarize / code phases (rule R12)

  @Test func perPersonaTokensAbsentFromSummarizeAndCodePhases() {
    let perPersona = ["assigned", "my_notes", "my_whispers", "relationships"]
    // summarize + every non-LLM phase except the producers that write these vars
    // downstream (assign → assigned, relationship_update → relationships).
    let codeLike: [PhaseType] = [.summarize, .scoreCalc, .eliminate, .conditional, .eventInject]
    for phaseType in codeLike {
      let supplied = PlaceholderAvailability.supplied(for: phaseType, chooseRoundRobin: true)
      for token in perPersona {
        #expect(
          !supplied.contains(token),
          "\(token) must not be injected in \(phaseType)")
      }
    }
  }

  @Test func summarizeSuppliesPairingTokensNotPerPersona() {
    let supplied = PlaceholderAvailability.supplied(for: .summarize, chooseRoundRobin: true)
    #expect(supplied.contains("agent1"))
    #expect(supplied.contains("action1"))
    #expect(supplied.contains("scoreboard"))
    #expect(!supplied.contains("assigned"))
    #expect(!supplied.contains("relationships"))
  }

  @Test func perPersonaTokensPresentInLLMPhases() {
    // The four inject{Assigned,Notes,Relationships}-always phases plus vote.
    for phaseType in [PhaseType.speakAll, .speakEach, .vote, .reflect, .whisper] {
      let supplied = PlaceholderAvailability.supplied(for: phaseType, chooseRoundRobin: true)
      for token in ["assigned", "my_notes", "relationships"] {
        #expect(supplied.contains(token), "\(token) missing from \(phaseType)")
      }
    }
  }

  // MARK: - Producer relation

  @Test func assignProducesAssignedFamily() {
    for token in ["assigned", "assigned_word", "assigned_topic", "wolf_name"] {
      #expect(PlaceholderAvailability.producers(of: token) == [.assign], "producer of \(token)")
    }
  }

  @Test func reflectProducesMyNotes() {
    #expect(PlaceholderAvailability.producers(of: "my_notes") == [.reflect])
  }

  @Test func whisperProducesMyWhispers() {
    #expect(PlaceholderAvailability.producers(of: "my_whispers") == [.whisper])
  }

  @Test func relationshipUpdateProducesRelationships() {
    #expect(PlaceholderAvailability.producers(of: "relationships") == [.relationshipUpdate])
  }

  @Test func voteProducesVoteResults() {
    #expect(PlaceholderAvailability.producers(of: "vote_results") == [.vote])
  }

  @Test func eventInjectProducesCurrentEvent() {
    #expect(PlaceholderAvailability.producers(of: "current_event") == [.eventInject])
  }

  @Test func nonProducerGatedTokensReturnNil() {
    // Always-resolvable-in-supplying-phase tokens are not producer-gated.
    for token in ["scoreboard", "conversation_log", "current_round", "candidates", "opponent_name"] {
      #expect(PlaceholderAvailability.producers(of: token) == nil, "\(token) should be ungated")
    }
  }

  @Test func everyProducedTokenIsInItsProducersSuppliedSet() {
    // Cross-check: a producer's output token appears in that producer's supplied set.
    for (token, phaseTypes) in PlaceholderAvailability.producerMap {
      for phaseType in phaseTypes {
        #expect(
          PlaceholderAvailability.supplied(for: phaseType, chooseRoundRobin: true).contains(token),
          "\(phaseType) produces \(token) but does not supply it")
      }
    }
  }
}
