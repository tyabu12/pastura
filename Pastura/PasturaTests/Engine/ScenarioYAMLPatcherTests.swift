import Foundation
import Testing

@testable import Pastura

/// Tests for ADR-018's format-preserving visual→YAML boundary patcher.
///
/// The DoD (ADR-018 §4): preservation of comments/key order on in-scope scalar
/// updates, fallback parity for out-of-scope edits, semantic equivalence of the
/// patched output, and corruption resistance on the documented edge cases.
@Suite(.timeLimit(.minutes(1)))
// swiftlint:disable:next type_body_length
struct ScenarioYAMLPatcherTests {

  let patcher = ScenarioYAMLPatcher()
  let loader = ScenarioLoader()
  let serializer = ScenarioSerializer()

  /// A base YAML with head/inline comments, non-canonical key order, and a
  /// block-scalar context — the formatting a full re-serialize would destroy.
  let base = """
    # A friendly scenario
    id: demo_scenario
    language: en
    name: Original Name  # display name
    description: A test scenario
    agents: 2
    rounds: 3
    context: |
      Shared context line one.
      Line two.

    personas:
      - name: Alice  # the optimist
        description: An optimistic agent
      - name: Bob
        description: A skeptical agent

    phases:
      - type: speak_all
        prompt: |
          Speak your mind.
        output:
          statement: string
    """

  // MARK: - Helpers

  // Internal (not private) so the sibling-file extensions can reach it — same
  // convention as `PromptBuilderTests`' shared helpers.
  func mutated(
    _ scenario: Scenario, name: String? = nil, description: String? = nil, rounds: Int? = nil,
    personas: [Persona]? = nil, phases: [Phase]? = nil
  ) -> Scenario {
    Scenario(
      id: scenario.id, name: name ?? scenario.name,
      description: description ?? scenario.description, language: scenario.language,
      simulationLanguage: scenario.simulationLanguage,
      agentCount: (personas ?? scenario.personas).count,
      rounds: rounds ?? scenario.rounds, context: scenario.context,
      personas: personas ?? scenario.personas, phases: phases ?? scenario.phases,
      extraData: scenario.extraData)
  }

  // MARK: - Preservation

  @Test func scalarUpdatePreservesCommentsAndKeyOrder() throws {
    let baseScenario = try loader.load(yaml: base)
    let visual = mutated(baseScenario, name: "New Name")
    let out = patcher.patch(visual: visual, base: base)

    #expect(out.contains("# A friendly scenario"))  // head comment
    #expect(out.contains("name: New Name  # display name"))  // value changed, comment + spacing kept
    #expect(out.contains("# the optimist"))  // persona inline comment
    #expect(out.contains("language: en\n"))  // non-canonical key order (language before name) kept
    #expect(!out.contains("Original Name"))
    #expect(try loader.load(yaml: out) == visual)
  }

  @Test func unchangedScenarioReturnsBaseVerbatim() throws {
    let baseScenario = try loader.load(yaml: base)
    #expect(patcher.patch(visual: baseScenario, base: base) == base)
  }

  @Test func personaScalarUpdatePreservesFormatting() throws {
    let baseScenario = try loader.load(yaml: base)
    var personas = baseScenario.personas
    personas[0] = Persona(name: "Alicia", description: personas[0].description)
    let visual = mutated(baseScenario, personas: personas)
    let out = patcher.patch(visual: visual, base: base)

    #expect(out.contains("- name: Alicia  # the optimist"))
    #expect(out.contains("- name: Bob"))  // untouched persona unchanged
    #expect(try loader.load(yaml: out) == visual)
  }

  @Test func intFieldUpdatePreservesFormatting() throws {
    let baseScenario = try loader.load(yaml: base)
    let visual = mutated(baseScenario, rounds: 7)
    let out = patcher.patch(visual: visual, base: base)

    #expect(out.contains("rounds: 7"))
    #expect(out.contains("# A friendly scenario"))
    #expect(try loader.load(yaml: out) == visual)
  }

  @Test func logWindowScalarUpdateCarriesNewValue() throws {
    let lwBase = """
      # scenario with a log window
      id: lw_demo
      language: en
      name: LW Demo
      description: A test scenario
      agents: 2
      rounds: 3
      log_window: 5  # keep last five
      context: Shared context.
      personas:
        - name: Alice
          description: An agent
        - name: Bob
          description: Another agent
      phases:
        - type: speak_all
          prompt: Speak.
          output:
            statement: string
      """
    let baseScenario = try loader.load(yaml: lwBase)
    let visual = Scenario(
      id: baseScenario.id, name: baseScenario.name, description: baseScenario.description,
      language: baseScenario.language, simulationLanguage: baseScenario.simulationLanguage,
      agentCount: baseScenario.agentCount, rounds: baseScenario.rounds,
      context: baseScenario.context, personas: baseScenario.personas,
      phases: baseScenario.phases, logWindow: 3, extraData: baseScenario.extraData)
    let out = patcher.patch(visual: visual, base: lwBase)

    // Semantics: the reparse carries the new value (surgical or fallback).
    #expect(try loader.load(yaml: out).logWindow == 3)
    // This is an in-scope inline-scalar edit, so the comment is preserved too.
    #expect(out.contains("# keep last five"))
  }

  // MARK: - Fallback parity

  @Test func structuralChangeFallsBackToFullSerialize() throws {
    let baseScenario = try loader.load(yaml: base)
    var personas = baseScenario.personas
    personas.append(Persona(name: "Carol", description: "A third agent"))
    let visual = mutated(baseScenario, personas: personas)
    let out = patcher.patch(visual: visual, base: base)

    #expect(out == serializer.serialize(visual))
    #expect(!out.contains("# A friendly scenario"))  // formatting not preserved on fallback
  }

  @Test func blockScalarContextChangeFallsBack() throws {
    let baseScenario = try loader.load(yaml: base)
    let visual = Scenario(
      id: baseScenario.id, name: baseScenario.name, description: baseScenario.description,
      language: baseScenario.language, simulationLanguage: baseScenario.simulationLanguage,
      agentCount: baseScenario.agentCount, rounds: baseScenario.rounds,
      context: "A completely different context.", personas: baseScenario.personas,
      phases: baseScenario.phases, extraData: baseScenario.extraData)
    let out = patcher.patch(visual: visual, base: base)

    #expect(out == serializer.serialize(visual))
  }

  @Test func blankBaseFallsBack() throws {
    let baseScenario = try loader.load(yaml: base)
    #expect(
      patcher.patch(visual: baseScenario, base: "   \n  ") == serializer.serialize(baseScenario))
  }

  @Test func unparseableBaseFallsBack() throws {
    let baseScenario = try loader.load(yaml: base)
    let out = patcher.patch(visual: baseScenario, base: "this: : : not valid yaml: [")
    #expect(out == serializer.serialize(baseScenario))
  }

  // MARK: - Corruption resistance (edge cases)

  @Test func quotedValueContainingHashIsNotTreatedAsComment() throws {
    let yaml = """
      id: demo
      language: en
      name: "a # b"  # real comment
      description: d
      agents: 2
      rounds: 1
      context: c
      personas:
        - name: Alice
          description: x
        - name: Bob
          description: y
      phases:
        - type: speak_all
          prompt: go
          output:
            statement: string
      """
    let baseScenario = try loader.load(yaml: yaml)
    #expect(baseScenario.name == "a # b")
    let visual = mutated(baseScenario, name: "z")
    let out = patcher.patch(visual: visual, base: yaml)

    #expect(out.contains("# real comment"))  // trailing comment on a quoted value preserved
    #expect(try loader.load(yaml: out) == visual)
  }

  @Test func plainToQuotedTransitionOnSpecialValue() throws {
    let baseScenario = try loader.load(yaml: base)
    // "true" must be quoted by the serializer's rules — the splice must too.
    let visual = mutated(baseScenario, name: "true")
    let out = patcher.patch(visual: visual, base: base)

    #expect(out.contains("name: \"true\"  # display name"))
    #expect(try loader.load(yaml: out) == visual)
    #expect(try loader.load(yaml: out).name == "true")
  }

  @Test func quotedToPlainTransition() throws {
    let yaml = """
      id: demo
      language: en
      name: "42"
      description: d
      agents: 2
      rounds: 1
      context: c
      personas:
        - name: Alice
          description: x
        - name: Bob
          description: y
      phases:
        - type: speak_all
          prompt: go
          output:
            statement: string
      """
    let baseScenario = try loader.load(yaml: yaml)
    #expect(baseScenario.name == "42")
    let visual = mutated(baseScenario, name: "Plain Name")
    let out = patcher.patch(visual: visual, base: yaml)

    #expect(out.contains("name: Plain Name\n"))  // old quotes dropped, new value plain
    #expect(try loader.load(yaml: out) == visual)
  }

  @Test func crlfLineEndingsAreHandled() throws {
    let crlf = base.replacingOccurrences(of: "\n", with: "\r\n")
    let baseScenario = try loader.load(yaml: crlf)
    let visual = mutated(baseScenario, name: "New Name")
    let out = patcher.patch(visual: visual, base: crlf)

    #expect(out.contains("name: New Name  # display name\r\n"))
    #expect(try loader.load(yaml: out) == visual)
  }

  /// An interior `#` (not preceded by whitespace) is part of a plain scalar, not
  /// a comment — `plainValueEnd` must only treat a ` #` as the comment boundary.
  /// Plants the input the guard catches: a naive `firstIndex(of: "#")` would
  /// split inside `ff#00` and corrupt the line.
  @Test func plainValueWithInteriorHashSplicesCorrectly() throws {
    let yaml = """
      id: demo
      language: en
      name: ff#00  # color code
      description: d
      agents: 2
      rounds: 1
      context: c
      personas:
        - name: Alice
          description: x
        - name: Bob
          description: y
      phases:
        - type: speak_all
          prompt: go
          output:
            statement: string
      """
    let baseScenario = try loader.load(yaml: yaml)
    #expect(baseScenario.name == "ff#00")  // interior # is part of the plain value
    let visual = mutated(baseScenario, name: "Renamed")
    let out = patcher.patch(visual: visual, base: yaml)

    #expect(out.contains("name: Renamed  # color code"))  // old value replaced, comment kept
    #expect(!out.contains("#00"))  // the interior-# fragment is gone, not stranded
    #expect(try loader.load(yaml: out) == visual)
  }

  // ADR-018 compatibility for #752: a base whose `description` is authored as a
  // literal `|` block has Yams style `.literal`, so editing it is out-of-scope
  // for the in-place splice (`tryEdit` rejects `.literal`/`.folded`) and forces
  // the full-serialize fallback — where the serializer's new `|-` block output
  // for a multi-line `description` appears and must round-trip.
  @Test func blockScalarDescriptionEditFallsBackToBlockScalar() throws {
    let blockBase = """
      id: demo_scenario
      language: en
      name: Original Name
      description: |
        First brief line.
        Second brief line.
      agents: 2
      rounds: 3
      context: Shared context.
      personas:
        - name: Alice
          description: An optimistic agent
        - name: Bob
          description: A skeptical agent
      phases:
        - type: speak_all
          prompt: Speak your mind.
          output:
            statement: string
      """
    let baseScenario = try loader.load(yaml: blockBase)
    let visual = mutated(
      baseScenario, description: "Rewritten first line.\nRewritten second line.")
    let out = patcher.patch(visual: visual, base: blockBase)

    // Out-of-scope (block-scalar) edit → full-serialize fallback.
    #expect(out == serializer.serialize(visual))
    // The fallback emits a strip-chomped `|-` literal block for the multi-line
    // description...
    #expect(out.contains("description: |-\n  Rewritten first line.\n  Rewritten second line."))
    // ...which round-trips back to the edited scenario.
    #expect(try loader.load(yaml: out).description == visual.description)
  }
}
