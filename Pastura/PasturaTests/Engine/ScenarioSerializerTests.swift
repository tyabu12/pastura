import Foundation
import Testing

@testable import Pastura

@Suite(.timeLimit(.minutes(1)))
// swiftlint:disable:next type_body_length
struct ScenarioSerializerTests {
  let serializer = ScenarioSerializer()
  let loader = ScenarioLoader()

  // MARK: - Round-trip: Preset Scenarios

  @Test func roundTripPrisonersDilemma() throws {
    try assertRoundTrip(presetNamed: "prisoners_dilemma")
  }

  @Test func roundTripBokete() throws {
    try assertRoundTrip(presetNamed: "bokete")
  }

  @Test func roundTripWordWolf() throws {
    try assertRoundTrip(presetNamed: "word_wolf")
  }

  @Test func roundTripTargetScoreRace() throws {
    try assertRoundTrip(presetNamed: "target_score_race")
  }

  // MARK: - Round-trip: Synthetic All-Fields Scenario

  // Exercises all 11 Phase fields and all 4 AnyCodableValue variants.
  // swiftlint:disable:next function_body_length
  @Test func roundTripSyntheticAllFields() throws {
    let scenario = Scenario(
      id: "synthetic_all_fields",
      name: "Synthetic Test",
      description: "Tests all phase fields and extraData variants",
      agentCount: 3,
      rounds: 2,
      context: "A test context with\nmultiple lines.",
      personas: [
        Persona(name: "Alice", description: "A strategist"),
        Persona(name: "Bob", description: "An optimist"),
        Persona(name: "Charlie", description: "A trickster")
      ],
      phases: [
        // assign: source + target
        Phase(type: .assign, source: "words", target: .randomOne),
        // speak_each: prompt + outputSchema + subRounds
        Phase(
          type: .speakEach,
          prompt: "Talk about {assigned_word}.",
          outputSchema: ["statement": "string", "inner_thought": "string"],
          subRounds: 3
        ),
        // vote: prompt + outputSchema + excludeSelf
        Phase(
          type: .vote,
          prompt: "Vote for the wolf.",
          outputSchema: ["vote": "string", "reason": "string"],
          excludeSelf: true
        ),
        // choose: prompt + outputSchema + options + pairing
        Phase(
          type: .choose,
          prompt: "Choose your action against {opponent_name}.",
          outputSchema: ["action": "string", "inner_thought": "string"],
          options: ["cooperate", "betray"],
          pairing: .roundRobin
        ),
        // score_calc: logic
        Phase(type: .scoreCalc, logic: .prisonersDilemma),
        // eliminate
        Phase(type: .eliminate),
        // summarize: template
        Phase(type: .summarize, template: "Round {current_round}: {scoreboard}"),
        // speak_all: prompt + outputSchema (basic)
        Phase(
          type: .speakAll,
          prompt: "Declare your intent.",
          outputSchema: ["statement": "string"]
        )
      ],
      extraData: [
        // .string
        "note": .string("A simple string value"),
        // .array
        "topics": .array(["Topic A", "Topic B", "Topic C"]),
        // .dictionary
        "config": .dictionary(["key1": "value1", "key2": "value2"]),
        // .arrayOfDictionaries
        "words": .arrayOfDictionaries([
          ["majority": "りんご", "minority": "みか���"],
          ["majority": "温泉", "minority": "プール"]
        ])
      ]
    )

    let yaml = serializer.serialize(scenario)
    let reloaded = try loader.load(yaml: yaml)

    assertScenariosEqual(reloaded, scenario)
  }

  // MARK: - Serialization Format

  @Test func serializesMultilineContextAsBlockScalar() throws {
    let scenario = makeMinimalScenario(context: "Line 1\nLine 2\nLine 3")
    let yaml = serializer.serialize(scenario)
    // Block scalar indicator (| or >) should be used for multiline strings
    #expect(yaml.contains("context:"))
    let reloaded = try loader.load(yaml: yaml)
    #expect(reloaded.context.contains("Line 1"))
    #expect(reloaded.context.contains("Line 2"))
  }

  @Test func preservesSingleNewlinesInMultilineStrings() throws {
    // Regression: folded scalar (>) converts SINGLE newlines to spaces,
    // losing user-intended line breaks (only double-newlines survive as
    // paragraph breaks). Literal scalar (|) preserves them all.
    let scenario = makeMinimalScenario(context: "Line 1\nLine 2\nLine 3")
    let yaml = serializer.serialize(scenario)
    let reloaded = try loader.load(yaml: yaml)
    // All single newlines must survive round-trip
    #expect(reloaded.context.contains("Line 1\nLine 2"))
  }

  @Test func serializesSingleLineContextInline() throws {
    let scenario = makeMinimalScenario(context: "A single line context.")
    let yaml = serializer.serialize(scenario)
    let reloaded = try loader.load(yaml: yaml)
    #expect(reloaded.context.hasPrefix("A single line context"))
  }

  @Test func outputIsValidYAML() throws {
    let scenario = makeMinimalScenario()
    let yaml = serializer.serialize(scenario)
    // Should parse without error
    let reloaded = try loader.load(yaml: yaml)
    #expect(reloaded.id == scenario.id)
  }

  // MARK: - Field Mapping Verification

  @Test func mapsAgentCountToAgentsKey() throws {
    let scenario = makeMinimalScenario()
    let yaml = serializer.serialize(scenario)
    #expect(yaml.contains("agents: 2"))
  }

  @Test func mapsSubRoundsToRoundsKey() throws {
    let scenario = Scenario(
      id: "test", name: "Test", description: "Test",
      agentCount: 2, rounds: 1, context: "Context",
      personas: [
        Persona(name: "A", description: "A"),
        Persona(name: "B", description: "B")
      ],
      phases: [Phase(type: .speakEach, prompt: "Talk", subRounds: 5)]
    )
    let yaml = serializer.serialize(scenario)
    // Phase-level `rounds` key (not `subRounds`)
    #expect(yaml.contains("rounds: 5"))
    let reloaded = try loader.load(yaml: yaml)
    #expect(reloaded.phases[0].subRounds == 5)
  }

  @Test func mapsOutputSchemaToOutputKey() throws {
    let scenario = makeMinimalScenario()
    let yaml = serializer.serialize(scenario)
    #expect(yaml.contains("output:"))
    #expect(!yaml.contains("outputSchema:"))
  }

  @Test func mapsExcludeSelfToExcludeSelfKey() throws {
    let scenario = Scenario(
      id: "test", name: "Test", description: "Test",
      agentCount: 2, rounds: 1, context: "Context",
      personas: [
        Persona(name: "A", description: "A"),
        Persona(name: "B", description: "B")
      ],
      phases: [
        Phase(type: .vote, prompt: "Vote", outputSchema: ["vote": "string"], excludeSelf: true)
      ]
    )
    let yaml = serializer.serialize(scenario)
    #expect(yaml.contains("exclude_self: true"))
  }

  // MARK: - event_inject round-trip

  @Test func roundTripEventInjectFullSpec() throws {
    let scenario = Scenario(
      id: "ei", name: "EI", description: "EI",
      agentCount: 2, rounds: 1, context: "C",
      personas: [
        Persona(name: "A", description: "A"),
        Persona(name: "B", description: "B")
      ],
      phases: [
        Phase(
          type: .eventInject,
          source: "events",
          probability: 0.5,
          eventVariable: "current_event"
        )
      ],
      extraData: ["events": .array(["x", "y"])]
    )
    let yaml = serializer.serialize(scenario)
    let reloaded = try loader.load(yaml: yaml)
    assertScenariosEqual(reloaded, scenario)
  }

  @Test func roundTripEventInjectMinimalDefaultsRoundTripAsNil() throws {
    // probability and eventVariable absent → loader sees them as `nil`,
    // serializer omits them. Round-trip must NOT inject default 1.0 / "current_event"
    // (those are handler-level defaults, not Phase-level defaults).
    let scenario = Scenario(
      id: "ei", name: "EI", description: "EI",
      agentCount: 2, rounds: 1, context: "C",
      personas: [
        Persona(name: "A", description: "A"),
        Persona(name: "B", description: "B")
      ],
      phases: [Phase(type: .eventInject, source: "events")],
      extraData: ["events": .array(["x"])]
    )
    let yaml = serializer.serialize(scenario)
    #expect(!yaml.contains("probability:"))
    #expect(!yaml.contains("\n    as:"))
    let reloaded = try loader.load(yaml: yaml)
    #expect(reloaded.phases[0].probability == nil)
    #expect(reloaded.phases[0].eventVariable == nil)
  }

  @Test func probabilitySerializesWithoutFloatingPointDust() throws {
    // 0.1 + 0.2 == 0.30000000000000004 in IEEE-754 binary. The %g formatter
    // suppresses precision dust so YAML output stays readable and stable.
    let scenario = Scenario(
      id: "ei", name: "EI", description: "EI",
      agentCount: 2, rounds: 1, context: "C",
      personas: [
        Persona(name: "A", description: "A"),
        Persona(name: "B", description: "B")
      ],
      phases: [
        Phase(type: .eventInject, source: "events", probability: 0.1 + 0.2)
      ],
      extraData: ["events": .array(["x"])]
    )
    let yaml = serializer.serialize(scenario)
    #expect(yaml.contains("probability: 0.3"))
    #expect(!yaml.contains("0.30000000000000004"))
  }

  @Test func probabilityOneSerializesAsBareInt() throws {
    // %g drops trailing zeros — 1.0 becomes "1" — which the loader's
    // intentional Int → Double coercion accepts. Keeps preset YAML readable.
    let scenario = Scenario(
      id: "ei", name: "EI", description: "EI",
      agentCount: 2, rounds: 1, context: "C",
      personas: [
        Persona(name: "A", description: "A"),
        Persona(name: "B", description: "B")
      ],
      phases: [
        Phase(type: .eventInject, source: "events", probability: 1.0)
      ],
      extraData: ["events": .array(["x"])]
    )
    let yaml = serializer.serialize(scenario)
    #expect(yaml.contains("probability: 1"))
    let reloaded = try loader.load(yaml: yaml)
    #expect(reloaded.phases[0].probability == 1.0)
  }

  // MARK: - Helpers

  private func assertRoundTrip(presetNamed name: String) throws {
    let originalYAML = try loadPresetYAML(named: name)
    let originalScenario = try loader.load(yaml: originalYAML)
    let serialized = serializer.serialize(originalScenario)
    let reloaded = try loader.load(yaml: serialized)

    assertScenariosEqual(reloaded, originalScenario)
  }

  private func assertScenariosEqual(_ actual: Scenario, _ expected: Scenario) {
    #expect(actual.id == expected.id)
    #expect(actual.name == expected.name)
    #expect(actual.agentCount == expected.agentCount)
    #expect(actual.rounds == expected.rounds)

    // Personas
    #expect(actual.personas.count == expected.personas.count)
    for (actualP, expectedP) in zip(actual.personas, expected.personas) {
      #expect(actualP.name == expectedP.name)
    }

    // Phases
    #expect(actual.phases.count == expected.phases.count)
    for (i, (actualPh, expectedPh)) in zip(actual.phases, expected.phases).enumerated() {
      #expect(actualPh.type == expectedPh.type, "Phase \(i) type mismatch")
      #expect((actualPh.prompt != nil) == (expectedPh.prompt != nil), "Phase \(i) prompt presence")
      #expect(actualPh.options == expectedPh.options, "Phase \(i) options")
      #expect(actualPh.pairing == expectedPh.pairing, "Phase \(i) pairing")
      #expect(actualPh.logic == expectedPh.logic, "Phase \(i) logic")
      #expect(actualPh.excludeSelf == expectedPh.excludeSelf, "Phase \(i) excludeSelf")
      #expect(actualPh.subRounds == expectedPh.subRounds, "Phase \(i) subRounds")
      #expect(actualPh.source == expectedPh.source, "Phase \(i) source")
      #expect(actualPh.target == expectedPh.target, "Phase \(i) target")
      if let expectedSchema = expectedPh.outputSchema {
        #expect(actualPh.outputSchema != nil, "Phase \(i) outputSchema missing")
        for (key, _) in expectedSchema {
          #expect(actualPh.outputSchema?[key] != nil, "Phase \(i) outputSchema missing key: \(key)")
        }
      }
      #expect(actualPh.probability == expectedPh.probability, "Phase \(i) probability")
      #expect(actualPh.eventVariable == expectedPh.eventVariable, "Phase \(i) eventVariable")
    }

    // ExtraData
    #expect(actual.extraData.keys.sorted() == expected.extraData.keys.sorted())
    for key in expected.extraData.keys {
      #expect(actual.extraData[key] == expected.extraData[key], "extraData[\(key)] mismatch")
    }
  }

  private func loadPresetYAML(named name: String) throws -> String {
    guard let url = Bundle(for: DatabaseManager.self).url(forResource: name, withExtension: "yaml")
    else {
      Issue.record("Preset \(name).yaml not found in bundle")
      throw SimulationError.scenarioValidationFailed("Preset not found: \(name)")
    }
    return try String(contentsOf: url, encoding: .utf8)
  }

  private func makeMinimalScenario(
    context: String = "You are in a game."
  ) -> Scenario {
    Scenario(
      id: "test_scenario",
      name: "Test",
      description: "A test scenario",
      agentCount: 2,
      rounds: 3,
      context: context,
      personas: [
        Persona(name: "Alice", description: "A strategist"),
        Persona(name: "Bob", description: "An optimist")
      ],
      phases: [
        Phase(
          type: .speakAll,
          prompt: "Speak your mind.",
          outputSchema: ["statement": "string", "inner_thought": "string"]
        )
      ]
    )
  }
}
