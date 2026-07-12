import Testing

@testable import Pastura

@Suite(.timeLimit(.minutes(1)))
struct WordwolfJudgeLogicTests {
  let logic = WordwolfJudgeLogic()

  @Test func majorityWinsWhenWolfMostVoted() {
    var state = SimulationState()
    state.voteResults = ["Wolf": 3, "Other": 1]
    state.variables["wolf_name"] = "Wolf"
    let collector = EventCollector()
    logic.calculate(state: &state, language: "ja", emitter: collector.emit)
    let summaries = collector.events.compactMap { event -> String? in
      if case .summary(let text) = event { return text }
      return nil
    }
    #expect(summaries.count == 1)
    #expect(summaries[0].contains("多数派の勝ち"))
  }

  @Test func wolfWinsWhenNotDetected() {
    var state = SimulationState()
    state.voteResults = ["Innocent": 3, "Wolf": 1]
    state.variables["wolf_name"] = "Wolf"
    let collector = EventCollector()
    logic.calculate(state: &state, language: "ja", emitter: collector.emit)
    let summaries = collector.events.compactMap { event -> String? in
      if case .summary(let text) = event { return text }
      return nil
    }
    #expect(summaries[0].contains("ウルフの勝ち"))
  }

  /// A vote tie must resolve to a **stable** winner. Before #1057 the winner
  /// came from `Dictionary.max(by:)` with no secondary key, so it flipped with
  /// hash-seed randomization across launches. Canonical tie-break is
  /// (count desc, name desc) → Bob wins the tie; with the wolf being Alice,
  /// the wolf escapes deterministically on every call.
  @Test func tieResolvesToStableWinner() {
    func run() -> String {
      var state = SimulationState()
      state.voteResults = ["Alice": 2, "Bob": 2]
      state.variables["wolf_name"] = "Alice"
      let collector = EventCollector()
      logic.calculate(state: &state, language: "ja", emitter: collector.emit)
      let summaries = collector.events.compactMap { event -> String? in
        if case .summary(let text) = event { return text }
        return nil
      }
      return summaries.first ?? ""
    }

    let first = run()
    // Load-bearing: the deterministic winner is Bob (name desc); Bob != wolf
    // (Alice) → wolf wins. The old `max(by:)` could not pin this — it returned
    // whichever tied key dictionary order surfaced first.
    #expect(first.contains("Bob"))
    #expect(first.contains("ウルフの勝ち"))
    #expect(!first.contains("Alice"))
    // Independently-constructed states yield the identical outcome. Pre-fix
    // these could diverge within a single run (observed Alice, then Bob);
    // the sort makes the winner a pure function of the vote counts + names.
    #expect(run() == first)
    #expect(run() == first)
  }

  @Test func handlesEmptyVoteResults() {
    var state = SimulationState()
    let collector = EventCollector()
    logic.calculate(state: &state, language: "ja", emitter: collector.emit)
    let summaries = collector.events.compactMap { event -> String? in
      if case .summary(let text) = event { return text }
      return nil
    }
    #expect(summaries[0].contains("投票結果がありません"))
  }

  // MARK: - English language path (ADR-010 Step E)

  @Test func majorityWinsInEnglish() {
    var state = SimulationState()
    state.voteResults = ["Wolf": 3, "Other": 1]
    state.variables["wolf_name"] = "Wolf"
    let collector = EventCollector()
    logic.calculate(state: &state, language: "en", emitter: collector.emit)
    let summaries = collector.events.compactMap { event -> String? in
      if case .summary(let text) = event { return text }
      return nil
    }
    #expect(summaries.count == 1)
    #expect(summaries[0].contains("Majority wins"))
    #expect(!summaries[0].contains("多数派の勝ち"))
  }

  @Test func wolfWinsInEnglish() {
    var state = SimulationState()
    state.voteResults = ["Innocent": 3, "Wolf": 1]
    state.variables["wolf_name"] = "Wolf"
    let collector = EventCollector()
    logic.calculate(state: &state, language: "en", emitter: collector.emit)
    let summaries = collector.events.compactMap { event -> String? in
      if case .summary(let text) = event { return text }
      return nil
    }
    #expect(summaries.count == 1)
    #expect(summaries[0].contains("The wolf wins"))
    #expect(!summaries[0].contains("ウルフの勝ち"))
  }
}
