import Testing

@testable import Pastura

@Suite(.timeLimit(.minutes(1)))
struct PhaseDispatcherTests {
  let dispatcher = PhaseDispatcher()

  @Test func dispatchesAllEightPhaseTypes() throws {
    for phaseType in PhaseType.allCases {
      let handler = try dispatcher.handler(for: phaseType)
      switch phaseType {
      case .speakAll:
        #expect(handler is SpeakAllHandler)
      case .speakEach:
        #expect(handler is SpeakEachHandler)
      case .vote:
        #expect(handler is VoteHandler)
      case .choose:
        #expect(handler is ChooseHandler)
      case .scoreCalc:
        #expect(handler is ScoreCalcHandler)
      case .assign:
        #expect(handler is AssignHandler)
      case .eliminate:
        #expect(handler is EliminateHandler)
      case .summarize:
        #expect(handler is SummarizeHandler)
      }
    }
  }
}
