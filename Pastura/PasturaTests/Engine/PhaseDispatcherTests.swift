import Testing

@testable import Pastura

@Suite(.timeLimit(.minutes(1)))
struct PhaseDispatcherTests {
  let dispatcher = PhaseDispatcher()

  @Test func dispatchesAllRegisteredPhaseTypes() throws {
    for phaseType in PhaseType.allCases {
      switch phaseType {
      case .conditional:
        // ConditionalHandler is registered in a later commit. Until then,
        // the dispatcher legitimately throws for this case — assert that so
        // a future handler-registration regression breaks a specific test
        // instead of an assertion further downstream.
        #expect(throws: SimulationError.self) {
          _ = try dispatcher.handler(for: phaseType)
        }
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
      }
    }
  }
}
