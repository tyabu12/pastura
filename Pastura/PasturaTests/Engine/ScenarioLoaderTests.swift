import Testing

@testable import Pastura

// swiftlint:disable file_length
@Suite(.timeLimit(.minutes(1)))
// swiftlint:disable:next type_body_length
struct ScenarioLoaderTests {
  let loader = ScenarioLoader()

  // MARK: - Valid Scenario Loading

  @Test func loadsMinimalValidScenario() throws {
    let yaml = """
      id: test_scenario
      name: Test
      description: A test scenario
      agents: 2
      rounds: 3
      context: You are in a game.
      personas:
        - name: Alice
          description: A strategist
        - name: Bob
          description: An optimist
      phases:
        - type: speak_all
          prompt: "Speak your mind."
          output:
            statement: string
            inner_thought: string
      """
    let scenario = try loader.load(yaml: yaml)
    #expect(scenario.id == "test_scenario")
    #expect(scenario.name == "Test")
    #expect(scenario.description == "A test scenario")
    #expect(scenario.agentCount == 2)
    #expect(scenario.rounds == 3)
    #expect(scenario.context == "You are in a game.")
    #expect(scenario.personas.count == 2)
    #expect(scenario.phases.count == 1)
  }

  @Test func parsesPersonasCorrectly() throws {
    let scenario = try loader.load(yaml: makeMinimalYAML())
    #expect(scenario.personas[0].name == "Alice")
    #expect(scenario.personas[0].description == "A strategist")
    #expect(scenario.personas[1].name == "Bob")
  }

  @Test func parsesPhaseSpeakAll() throws {
    let scenario = try loader.load(yaml: makeMinimalYAML())
    let phase = scenario.phases[0]
    #expect(phase.type == .speakAll)
    #expect(phase.prompt == "Speak your mind.")
    #expect(phase.outputSchema?["statement"] == "string")
  }

  // swiftlint:disable:next function_body_length
  @Test func parsesPhaseWithAllFields() throws {
    let yaml = """
      id: test
      name: Test
      description: Test
      agents: 2
      rounds: 1
      context: Context
      personas:
        - name: A
          description: A
        - name: B
          description: B
      phases:
        - type: choose
          prompt: "Choose!"
          output:
            action: string
          options:
            - cooperate
            - betray
          pairing: round_robin
        - type: score_calc
          logic: prisoners_dilemma
        - type: summarize
          template: "{agent1}({action1}) vs {agent2}({action2})"
        - type: vote
          prompt: "Vote!"
          output:
            vote: string
          exclude_self: true
        - type: speak_each
          prompt: "Talk"
          output:
            statement: string
          rounds: 3
        - type: assign
          source: words
          target: random_one
        - type: eliminate
      """
    let scenario = try loader.load(yaml: yaml)

    // choose phase
    let choose = scenario.phases[0]
    #expect(choose.type == .choose)
    #expect(choose.options == ["cooperate", "betray"])
    #expect(choose.pairing == .roundRobin)

    // score_calc phase
    let scoreCalc = scenario.phases[1]
    #expect(scoreCalc.type == .scoreCalc)
    #expect(scoreCalc.logic == .prisonersDilemma)

    // summarize phase
    let summarize = scenario.phases[2]
    #expect(summarize.type == .summarize)
    #expect(summarize.template == "{agent1}({action1}) vs {agent2}({action2})")

    // vote phase
    let vote = scenario.phases[3]
    #expect(vote.type == .vote)
    #expect(vote.excludeSelf == true)

    // speak_each phase
    let speakEach = scenario.phases[4]
    #expect(speakEach.type == .speakEach)
    #expect(speakEach.subRounds == 3)

    // assign phase
    let assign = scenario.phases[5]
    #expect(assign.type == .assign)
    #expect(assign.source == "words")
    #expect(assign.target == .randomOne)

    // eliminate phase
    let eliminate = scenario.phases[6]
    #expect(eliminate.type == .eliminate)
  }

  // MARK: - Extra Data

  @Test func parsesExtraDataStringArray() throws {
    let yaml = """
      id: test
      name: Test
      description: Test
      agents: 2
      rounds: 1
      context: Context
      personas:
        - name: A
          description: A
        - name: B
          description: B
      phases:
        - type: speak_all
          prompt: "Go"
          output:
            boke: string
      topics:
        - "A cat in a suit"
        - "A dog driving"
      """
    let scenario = try loader.load(yaml: yaml)
    if case .array(let topics) = scenario.extraData["topics"] {
      #expect(topics.count == 2)
      #expect(topics[0] == "A cat in a suit")
    } else {
      Issue.record("Expected .array for topics")
    }
  }

  @Test func parsesExtraDataArrayOfDictionaries() throws {
    let yaml = """
      id: test
      name: Test
      description: Test
      agents: 2
      rounds: 1
      context: Context
      personas:
        - name: A
          description: A
        - name: B
          description: B
      phases:
        - type: assign
          source: words
          target: random_one
      words:
        - majority: りんご
          minority: みかん
        - majority: 温泉
          minority: プール
      """
    let scenario = try loader.load(yaml: yaml)
    if case .arrayOfDictionaries(let words) = scenario.extraData["words"] {
      #expect(words.count == 2)
      #expect(words[0]["majority"] == "りんご")
      #expect(words[0]["minority"] == "みかん")
    } else {
      Issue.record("Expected .arrayOfDictionaries for words")
    }
  }

  // MARK: - Code Fence Stripping

  @Test func stripsCodeFencesBeforeParsing() throws {
    let yaml = """
      ```yaml
      id: test
      name: Test
      description: Test
      agents: 2
      rounds: 1
      context: Context
      personas:
        - name: A
          description: A
        - name: B
          description: B
      phases:
        - type: speak_all
          prompt: "Go"
          output:
            statement: string
      ```
      """
    let scenario = try loader.load(yaml: yaml)
    #expect(scenario.id == "test")
  }

  // MARK: - Validation Errors

  @Test func throwsOnMissingRequiredField() {
    let yaml = """
      name: Test
      description: Test
      agents: 2
      rounds: 1
      context: Context
      personas:
        - name: A
          description: A
        - name: B
          description: B
      phases:
        - type: speak_all
      """
    #expect(throws: SimulationError.self) {
      try loader.load(yaml: yaml)
    }
  }

  @Test func throwsOnInvalidPhaseType() {
    let yaml = """
      id: test
      name: Test
      description: Test
      agents: 2
      rounds: 1
      context: Context
      personas:
        - name: A
          description: A
        - name: B
          description: B
      phases:
        - type: invalid_type
          prompt: "Go"
      """
    #expect(throws: SimulationError.self) {
      try loader.load(yaml: yaml)
    }
  }

  @Test func throwsOnAgentCountMismatch() {
    let yaml = """
      id: test
      name: Test
      description: Test
      agents: 5
      rounds: 1
      context: Context
      personas:
        - name: A
          description: A
        - name: B
          description: B
      phases:
        - type: speak_all
          prompt: "Go"
      """
    #expect(throws: SimulationError.self) {
      try loader.load(yaml: yaml)
    }
  }

  @Test func throwsOnInvalidYAML() {
    let yaml = "{{invalid yaml: [["
    #expect(throws: SimulationError.self) {
      try loader.load(yaml: yaml)
    }
  }

  // MARK: - Inference Count Estimation

  @Test func estimatesSpeakAllInferences() {
    let scenario = Scenario(
      id: "t", name: "T", description: "T", agentCount: 5, rounds: 3, context: "C",
      personas: (0..<5).map { Persona(name: "A\($0)", description: "D") },
      phases: [Phase(type: .speakAll)]
    )
    // 5 agents × 3 rounds = 15
    #expect(ScenarioLoader.estimateInferenceCount(scenario) == 15)
  }

  @Test func estimatesSpeakEachWithSubRounds() {
    let scenario = Scenario(
      id: "t", name: "T", description: "T", agentCount: 3, rounds: 2, context: "C",
      personas: (0..<3).map { Persona(name: "A\($0)", description: "D") },
      phases: [Phase(type: .speakEach, subRounds: 3)]
    )
    // 3 agents × 3 subRounds × 2 rounds = 18
    #expect(ScenarioLoader.estimateInferenceCount(scenario) == 18)
  }

  @Test func estimatesVoteInferences() {
    let scenario = Scenario(
      id: "t", name: "T", description: "T", agentCount: 5, rounds: 2, context: "C",
      personas: (0..<5).map { Persona(name: "A\($0)", description: "D") },
      phases: [Phase(type: .vote)]
    )
    // 5 agents × 2 rounds = 10
    #expect(ScenarioLoader.estimateInferenceCount(scenario) == 10)
  }

  @Test func estimatesChooseRoundRobinInferences() {
    let scenario = Scenario(
      id: "t", name: "T", description: "T", agentCount: 5, rounds: 2, context: "C",
      personas: (0..<5).map { Persona(name: "A\($0)", description: "D") },
      phases: [Phase(type: .choose, pairing: .roundRobin)]
    )
    // 5 agents × 2 (per pair) × 2 rounds = 20
    #expect(ScenarioLoader.estimateInferenceCount(scenario) == 20)
  }

  @Test func estimatesChooseIndividualInferences() {
    let scenario = Scenario(
      id: "t", name: "T", description: "T", agentCount: 5, rounds: 2, context: "C",
      personas: (0..<5).map { Persona(name: "A\($0)", description: "D") },
      phases: [Phase(type: .choose)]
    )
    // 5 agents × 2 rounds = 10
    #expect(ScenarioLoader.estimateInferenceCount(scenario) == 10)
  }

  @Test func estimatesZeroForCodePhases() {
    let scenario = Scenario(
      id: "t", name: "T", description: "T", agentCount: 5, rounds: 3, context: "C",
      personas: (0..<5).map { Persona(name: "A\($0)", description: "D") },
      phases: [
        Phase(type: .scoreCalc, logic: .voteTally),
        Phase(type: .assign, source: "words"),
        Phase(type: .eliminate),
        Phase(type: .summarize, template: "Done")
      ]
    )
    #expect(ScenarioLoader.estimateInferenceCount(scenario) == 0)
  }

  // MARK: - Test Helpers

  func makeYAMLWithAssignTarget(_ target: String) -> String {
    """
    id: t
    name: T
    description: T
    agents: 2
    rounds: 1
    context: C
    personas:
      - name: A
        description: D
      - name: B
        description: D
    phases:
      - type: assign
        source: topics
        target: \(target)
    topics:
      - x
    """
  }

  func makeMinimalYAML(phasesBlock: String) -> String {
    """
    id: t
    name: T
    description: T
    agents: 2
    rounds: 1
    context: C
    personas:
      - name: A
        description: D
      - name: B
        description: D
    \(phasesBlock)
    """
  }

  private func makeMinimalYAML() -> String {
    """
    id: test_scenario
    name: Test
    description: A test scenario
    agents: 2
    rounds: 3
    context: You are in a game.
    personas:
      - name: Alice
        description: A strategist
      - name: Bob
        description: An optimist
    phases:
      - type: speak_all
        prompt: "Speak your mind."
        output:
          statement: string
          inner_thought: string
    """
  }
}
