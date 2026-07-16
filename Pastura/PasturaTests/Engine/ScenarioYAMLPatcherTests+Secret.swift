import Foundation
import Testing

@testable import Pastura

// MARK: - Persona secret patch scope (#914)
//
// Sibling-file split of `ScenarioYAMLPatcherTests` (file_length cap). Per
// `.claude/rules/testing.md`, extend the suite struct rather than declaring a
// new `@Suite` (which would run in parallel and race shared state). The `base`
// / `mutated` helpers stay at internal access in the parent file.
extension ScenarioYAMLPatcherTests {

  /// A base whose first persona already carries a single-line `secret` — the
  /// in-scope shape for a format-preserving scalar patch.
  private static let secretBase = """
    # A scenario with secrets
    id: secret_demo
    language: en
    name: Secret Demo
    description: A test scenario
    agents: 2
    rounds: 3
    context: Shared context.

    personas:
      - name: Alice  # the optimist
        description: An optimistic agent
        secret: She sold the house  # the twist
      - name: Bob
        description: A skeptical agent

    phases:
      - type: speak_all
        prompt: |
          Speak your mind.
        output:
          statement: string
    """

  @Test func existingSecretEditIsFormatPreserving() throws {
    let baseScenario = try loader.load(yaml: Self.secretBase)
    var personas = baseScenario.personas
    personas[0] = Persona(
      name: personas[0].name, description: personas[0].description, secret: "She burned the deed")
    let visual = mutated(baseScenario, personas: personas)
    let out = patcher.patch(visual: visual, base: Self.secretBase)

    #expect(out.contains("# A scenario with secrets"))  // head comment survives
    #expect(out.contains("# the twist"))  // inline comment on the edited line survives
    #expect(out.contains("She burned the deed"))
    #expect(!out.contains("She sold the house"))
    #expect(try loader.load(yaml: out) == visual)
  }

  /// First-time add has no `secret` node to splice onto, so `tryEdit` fails and
  /// the patcher drops to the full-serialize fallback — same contract as any
  /// other structural change (ADR-018). The value must still land.
  @Test func firstTimeSecretAddFallsBackToFullSerialize() throws {
    let baseScenario = try loader.load(yaml: base)
    var personas = baseScenario.personas
    personas[0] = Persona(
      name: personas[0].name, description: personas[0].description, secret: "A brand new secret")
    let visual = mutated(baseScenario, personas: personas)
    let out = patcher.patch(visual: visual, base: base)

    #expect(out.contains("A brand new secret"))
    #expect(!out.contains("# the optimist"))  // fallback: comments are not preserved
    #expect(try loader.load(yaml: out) == visual)
  }

  /// The third fallback arm: a multi-line secret is a `|-` literal-style
  /// scalar, which `tryEdit` refuses to splice (a scalar patch can't rewrite a
  /// block). Reachable because the serializer emits `secret: |-` for multi-line
  /// values.
  @Test func multilineSecretEditFallsBackToFullSerialize() throws {
    let blockBase = """
      # A scenario with a multi-line secret
      id: block_secret_demo
      language: en
      name: Block Secret Demo
      description: A test scenario
      agents: 2
      rounds: 3
      context: Shared context.

      personas:
        - name: Alice  # the optimist
          description: An optimistic agent
          secret: |-
            She sold the house.
            The deed is gone.
        - name: Bob
          description: A skeptical agent

      phases:
        - type: speak_all
          prompt: |
            Speak your mind.
          output:
            statement: string
      """
    let baseScenario = try loader.load(yaml: blockBase)
    #expect(baseScenario.personas[0].secret == "She sold the house.\nThe deed is gone.")

    var personas = baseScenario.personas
    personas[0] = Persona(
      name: personas[0].name, description: personas[0].description,
      secret: "She burned the deed.\nNobody saw.")
    let visual = mutated(baseScenario, personas: personas)
    let out = patcher.patch(visual: visual, base: blockBase)

    #expect(out == serializer.serialize(visual))
    #expect(!out.contains("# the optimist"))  // fallback: formatting not preserved
    #expect(try loader.load(yaml: out) == visual)
  }

  /// Removal renders `nil`, which `tryEdit` also refuses — full-serialize
  /// fallback, and the key must be gone from the output.
  @Test func secretRemovalFallsBackToFullSerialize() throws {
    let baseScenario = try loader.load(yaml: Self.secretBase)
    var personas = baseScenario.personas
    personas[0] = Persona(name: personas[0].name, description: personas[0].description)
    let visual = mutated(baseScenario, personas: personas)
    let out = patcher.patch(visual: visual, base: Self.secretBase)

    #expect(!out.contains("She sold the house"))
    #expect(!out.contains("secret:"))
    #expect(try loader.load(yaml: out) == visual)
  }
}
