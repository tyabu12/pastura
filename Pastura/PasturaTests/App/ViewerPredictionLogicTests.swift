import Foundation
import Testing

@testable import Pastura

/// Unit coverage for the pure viewer-prediction decision logic (#915).
///
/// Marked `@MainActor` per `.claude/rules/swift-isolation.md` Pattern 5: the
/// `Question` enum's auto-synthesized `Equatable` conformance lookup is
/// MainActor-isolated even though its witnesses are nonisolated, so a bare
/// nonisolated `#expect(x == .wolf)` would not compile.
@Suite(.timeLimit(.minutes(1)))
@MainActor
struct ViewerPredictionLogicTests {

  // MARK: question(for:)

  @Test func questionIsWolfWhenRandomOneAssignPresent() {
    let phases = [
      Phase(type: .assign, target: .randomOne),
      Phase(type: .vote)
    ]
    #expect(ViewerPredictionLogic.question(for: phases) == .wolf)
  }

  @Test func questionIsTopVoteWhenVoteButNoRandomOneAssign() {
    let phases = [
      Phase(type: .assign, target: .all),
      Phase(type: .vote)
    ]
    #expect(ViewerPredictionLogic.question(for: phases) == .topVote)
  }

  @Test func questionIsNilWhenNoVoteAndNoRandomOneAssign() {
    let phases = [
      Phase(type: .speakAll),
      Phase(type: .choose),
      Phase(type: .scoreCalc)
    ]
    #expect(ViewerPredictionLogic.question(for: phases) == nil)
  }

  @Test func questionSeesVoteNestedInConditional() {
    let phases = [
      Phase(type: .speakAll),
      Phase(type: .conditional, thenPhases: [Phase(type: .vote)])
    ]
    #expect(ViewerPredictionLogic.question(for: phases) == .topVote)
  }

  @Test func bundledPresetsClassifyAsExpected() throws {
    let expected: [String: ViewerPredictionLogic.Question?] = [
      "word_wolf": .wolf,
      "bokete": .topVote,
      "prisoners_dilemma": .none
    ]
    let bundle = Bundle(for: ViewerPredictionLogicTestsAnchor.self)
    let loader = ScenarioLoader()

    for (fileName, want) in expected {
      let url = try #require(
        bundle.url(forResource: fileName, withExtension: "yaml")
          ?? Bundle.main.url(forResource: fileName, withExtension: "yaml"),
        "preset \(fileName).yaml not found in test or app bundle")
      let scenario = try loader.load(yaml: try String(contentsOf: url, encoding: .utf8))
      #expect(
        ViewerPredictionLogic.question(for: scenario.phases) == want,
        "\(fileName) classified unexpectedly")
    }
  }

  // MARK: wolf(from:)

  @Test func wolfIsTheSoleMinorityHolder() {
    let assignments = [
      "Alice": "apple", "Bob": "apple", "Carol": "apple",
      "Dave": "apple", "Eve": "orange"
    ]
    #expect(ViewerPredictionLogic.wolf(from: assignments) == "Eve")
  }

  @Test func wolfIsNilForTwoAgentEvenSplit() {
    let assignments = ["Alice": "apple", "Bob": "orange"]
    #expect(ViewerPredictionLogic.wolf(from: assignments) == nil)
  }

  @Test func wolfIsNilWhenTwoValuesTieForRarest() {
    // apple×2, orange×1, banana×1 — two values share the min frequency.
    let assignments = [
      "Alice": "apple", "Bob": "apple", "Carol": "orange", "Dave": "banana"
    ]
    #expect(ViewerPredictionLogic.wolf(from: assignments) == nil)
  }

  @Test func wolfIsNilWhenRarestValueSharedByMultipleAgents() {
    // orange×2 is the minority, but two agents hold it — no single wolf.
    let assignments = [
      "Alice": "apple", "Bob": "apple", "Carol": "apple",
      "Dave": "orange", "Eve": "orange"
    ]
    #expect(ViewerPredictionLogic.wolf(from: assignments) == nil)
  }

  @Test func wolfIsNilForEmptyAssignments() {
    #expect(ViewerPredictionLogic.wolf(from: [:]) == nil)
  }

  // MARK: topVote(tallies:roster:)

  @Test func topVoteIsTheHighestTally() {
    let tallies = ["Alice": 1, "Bob": 3, "Carol": 2]
    let roster = ["Alice", "Bob", "Carol"]
    #expect(ViewerPredictionLogic.topVote(tallies: tallies, roster: roster) == "Bob")
  }

  @Test func topVoteBreaksTiesByNameAscending() {
    // Bob and Carol tie at 3 → name-ascending picks Bob, matching the card.
    let tallies = ["Alice": 1, "Bob": 3, "Carol": 3]
    let roster = ["Alice", "Bob", "Carol"]
    #expect(ViewerPredictionLogic.topVote(tallies: tallies, roster: roster) == "Bob")
  }

  @Test func topVoteTreatsMissingTallyAsZero() {
    let tallies = ["Bob": 2]
    let roster = ["Alice", "Bob", "Carol"]
    #expect(ViewerPredictionLogic.topVote(tallies: tallies, roster: roster) == "Bob")
  }

  @Test func topVoteIsNilForEmptyRoster() {
    #expect(ViewerPredictionLogic.topVote(tallies: ["Bob": 2], roster: []) == nil)
  }

  // MARK: isHit

  @Test func isHitComparesPredictedAndActual() {
    #expect(ViewerPredictionLogic.isHit(predicted: "Eve", actual: "Eve"))
    #expect(!ViewerPredictionLogic.isHit(predicted: "Eve", actual: "Bob"))
  }
}

/// Class anchor for `Bundle(for:)` lookup against the test target — preset
/// YAMLs live in the app bundle, not the simulator UI runner's `Bundle.main`.
private final class ViewerPredictionLogicTestsAnchor {}
