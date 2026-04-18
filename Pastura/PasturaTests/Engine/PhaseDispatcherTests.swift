import Testing

@testable import Pastura

@Suite(.timeLimit(.minutes(1)))
struct PhaseDispatcherTests {
  let dispatcher = PhaseDispatcher()

  @Test func dispatchesAllRegisteredPhaseTypes() throws {
    for phaseType in PhaseType.allCases {
      switch phaseType {
      case .speakAll:
        #expect(try dispatcher.handler(for: phaseType) is SpeakAllHandler)
      case .speakEach:
        #expect(try dispatcher.handler(for: phaseType) is SpeakEachHandler)
      case .vote:
        #expect(try dispatcher.handler(for: phaseType) is VoteHandler)
      case .choose:
        #expect(try dispatcher.handler(for: phaseType) is ChooseHandler)
      case .scoreCalc:
        #expect(try dispatcher.handler(for: phaseType) is ScoreCalcHandler)
      case .assign:
        #expect(try dispatcher.handler(for: phaseType) is AssignHandler)
      case .eliminate:
        #expect(try dispatcher.handler(for: phaseType) is EliminateHandler)
      case .summarize:
        #expect(try dispatcher.handler(for: phaseType) is SummarizeHandler)
      case .conditional:
        #expect(try dispatcher.handler(for: phaseType) is ConditionalHandler)
      }
    }
  }
}
