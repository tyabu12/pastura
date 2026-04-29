import Foundation
import Testing

@testable import Pastura

@Suite(.timeLimit(.minutes(1)))
struct ScenarioConventionsTests {
  @Test func primaryFieldForSpeakAllReturnsStatement() {
    #expect(ScenarioConventions.primaryField(for: .speakAll) == "statement")
  }

  @Test func primaryFieldForSpeakEachReturnsStatement() {
    #expect(ScenarioConventions.primaryField(for: .speakEach) == "statement")
  }

  @Test func primaryFieldForChooseReturnsAction() {
    #expect(ScenarioConventions.primaryField(for: .choose) == "action")
  }

  @Test func primaryFieldForVoteReturnsVote() {
    #expect(ScenarioConventions.primaryField(for: .vote) == "vote")
  }

  /// Code phases emit no LLM output — `nil` is the contract for callers that
  /// need to distinguish "no primary field expected" from "primary field
  /// missing".
  @Test func primaryFieldForCodePhasesReturnsNil() {
    let codePhases: [PhaseType] = [
      .scoreCalc, .assign, .eliminate, .summarize, .conditional, .eventInject
    ]
    for phase in codePhases {
      #expect(
        ScenarioConventions.primaryField(for: phase) == nil,
        "expected nil for code phase \(phase.rawValue)")
    }
  }

  /// Defends against accidental drift if a new `PhaseType` case is added —
  /// the new case should be classified explicitly in `primaryField(for:)`'s
  /// switch, and this test enumerates every case to surface the omission.
  @Test func everyPhaseTypeIsClassified() {
    for phaseType in PhaseType.allCases {
      _ = ScenarioConventions.primaryField(for: phaseType)
    }
    // No assertion — switch-exhaustiveness in `primaryField(for:)` guarantees
    // every case is handled. The point of this test is to fail compilation
    // (in `primaryField`) when a new case lands without a classification.
  }
}
