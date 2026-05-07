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

  /// Defends against drift if a new `PhaseType` case lands with a non-canonical
  /// value (e.g. someone returns `"speech"` for a new speak-shape phase). Pins
  /// the partition: every case maps to one of `{statement, action, vote}` or
  /// `nil` (code phases). Compiler exhaustiveness already catches a *missing*
  /// case in `primaryField(for:)`; this test catches a *wrong* classification.
  @Test func everyPhaseTypeMapsToCanonicalSetOrNil() {
    let canonical: Set<String> = ["statement", "action", "vote"]
    for phaseType in PhaseType.allCases {
      let field = ScenarioConventions.primaryField(for: phaseType)
      if let field {
        #expect(
          canonical.contains(field),
          "phase \(phaseType.rawValue) returned non-canonical primary field '\(field)'")
      }
    }
  }
}
