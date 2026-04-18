import Foundation
import Testing

@testable import Pastura

@Suite(.timeLimit(.minutes(1)))
struct ResultDetailExportAssemblerTests {

  // MARK: - Fixtures

  private let validYAML = """
    id: test
    name: Test Scenario
    description: A scenario fixture
    agents: 2
    rounds: 1
    context: "test context"
    personas:
      - name: Alice
        description: first
      - name: Bob
        description: second
    phases:
      - type: speak_all
        prompt: "say something"
    """

  private let brokenYAML = "{not valid yaml: ["

  private func makeScenario(yaml: String) -> ScenarioRecord {
    ScenarioRecord(
      id: "s1", name: "Test", yamlDefinition: yaml,
      isPreset: false,
      createdAt: Date(timeIntervalSince1970: 1_700_000_000),
      updatedAt: Date(timeIntervalSince1970: 1_700_000_000))
  }

  private func makeSimulation() -> SimulationRecord {
    SimulationRecord(
      id: "sim1", scenarioId: "s1",
      status: SimulationStatus.completed.rawValue,
      currentRound: 1, currentPhaseIndex: 0,
      stateJSON: "{}", configJSON: nil,
      createdAt: Date(timeIntervalSince1970: 1_700_000_000),
      updatedAt: Date(timeIntervalSince1970: 1_700_000_300),
      modelIdentifier: "test", llmBackend: "mock")
  }

  private func makeState() -> SimulationState {
    SimulationState(
      scores: [:], eliminated: [:], conversationLog: [],
      lastOutputs: [:], voteResults: [:], pairings: [],
      variables: [:], currentRound: 1)
  }

  private func makeTurn() -> TurnRecord {
    TurnRecord(
      id: "t1", simulationId: "sim1",
      roundNumber: 1, phaseType: "speak_all",
      agentName: "Alice", rawOutput: "{}",
      parsedOutputJSON: "{}", sequenceNumber: 1,
      createdAt: Date())
  }

  private func makeEvent() -> CodePhaseEventRecord {
    let payload = CodePhaseEventPayload.summary(text: "round summary")
    let json =
      (try? JSONEncoder().encode(payload))
      .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    return CodePhaseEventRecord(
      id: "e1", simulationId: "sim1",
      roundNumber: 1, phaseType: "summarize",
      sequenceNumber: 2, payloadJSON: json,
      createdAt: Date())
  }

  // MARK: - Tests

  @Test
  func assembleForwardsTurnsAndEvents() {
    let input = ResultDetailExportAssembler.assemble(
      simulation: makeSimulation(),
      scenario: makeScenario(yaml: validYAML),
      turns: [makeTurn()],
      events: [makeEvent()],
      state: makeState())

    #expect(input.turns.count == 1)
    #expect(input.codePhaseEvents.count == 1)
    #expect(input.turns.first?.id == "t1")
    #expect(input.codePhaseEvents.first?.id == "e1")
  }

  @Test
  func assembleExtractsPersonasFromValidYAML() {
    let input = ResultDetailExportAssembler.assemble(
      simulation: makeSimulation(),
      scenario: makeScenario(yaml: validYAML),
      turns: [],
      events: [],
      state: makeState())

    #expect(input.personas == ["Alice", "Bob"])
  }

  @Test
  func assembleFallsBackToEmptyPersonasOnBrokenYAML() {
    // Bug-resistance check: a stored scenario with broken YAML must not
    // crash export — personas degrade to [], the rest still flows through.
    let input = ResultDetailExportAssembler.assemble(
      simulation: makeSimulation(),
      scenario: makeScenario(yaml: brokenYAML),
      turns: [makeTurn()],
      events: [makeEvent()],
      state: makeState())

    #expect(input.personas.isEmpty)
    #expect(input.turns.count == 1)
    #expect(input.codePhaseEvents.count == 1)
  }

  @Test
  func assembleForwardsSimulationAndScenarioAndState() {
    let sim = makeSimulation()
    let scenario = makeScenario(yaml: validYAML)
    let state = makeState()
    let input = ResultDetailExportAssembler.assemble(
      simulation: sim, scenario: scenario,
      turns: [], events: [], state: state)

    #expect(input.simulation.id == sim.id)
    #expect(input.scenario.id == scenario.id)
    #expect(input.state == state)
  }
}
