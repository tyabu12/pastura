import Foundation
import Testing

@testable import Pastura

@Suite(.timeLimit(.minutes(1)))
struct PhaseTypeTests {
  @Test func rawValues() {
    #expect(PhaseType.speakAll.rawValue == "speak_all")
    #expect(PhaseType.speakEach.rawValue == "speak_each")
    #expect(PhaseType.vote.rawValue == "vote")
    #expect(PhaseType.choose.rawValue == "choose")
    #expect(PhaseType.scoreCalc.rawValue == "score_calc")
    #expect(PhaseType.assign.rawValue == "assign")
    #expect(PhaseType.eliminate.rawValue == "eliminate")
    #expect(PhaseType.summarize.rawValue == "summarize")
    #expect(PhaseType.conditional.rawValue == "conditional")
    #expect(PhaseType.eventInject.rawValue == "event_inject")
  }

  @Test func allCasesCount() {
    #expect(PhaseType.allCases.count == 10)
  }

  @Test func llmPhasesRequireLLM() {
    #expect(PhaseType.speakAll.requiresLLM)
    #expect(PhaseType.speakEach.requiresLLM)
    #expect(PhaseType.vote.requiresLLM)
    #expect(PhaseType.choose.requiresLLM)
  }

  @Test func codePhasesDoNotRequireLLM() {
    #expect(!PhaseType.scoreCalc.requiresLLM)
    #expect(!PhaseType.assign.requiresLLM)
    #expect(!PhaseType.eliminate.requiresLLM)
    #expect(!PhaseType.summarize.requiresLLM)
    // conditional is control-flow; the handler itself does no inference.
    #expect(!PhaseType.conditional.requiresLLM)
    // eventInject is a code phase; picks a random string from extraData.
    #expect(!PhaseType.eventInject.requiresLLM)
  }

  @Test func decodableFromJSON() throws {
    let json = Data(#""speak_all""#.utf8)
    let decoded = try JSONDecoder().decode(PhaseType.self, from: json)
    #expect(decoded == .speakAll)
  }
}
