import Foundation
import Testing

@testable import Pastura

/// ADR-022 §D4 (P11) — `PhaseType.allCases`-driven visual→YAML round-trip guard.
///
/// `EditablePhase` models every `Phase` field, so the visual editor's
/// `init(from:)` → `toPhase()` bridge and `ScenarioSerializer` must both
/// preserve every field of every phase kind. Neither is a `switch`, so a field
/// a new phase type introduces silently drops on the visual→YAML round-trip
/// (#961) unless caught here. This converts that class into test-caught two ways:
///
///  1. `canonicalPhase(for:)` is a **no-default `switch`** over `PhaseType`, so
///     a new case breaks the TEST-TARGET compile until it gets a fixture (the
///     D5 no-default-fixture-builder pattern).
///  2. The tests iterate `PhaseType.allCases`, so the fixture set cannot
///     silently lag the enum even if the switch were ever loosened.
@Suite(.timeLimit(.minutes(1)))
@MainActor
struct EditablePhaseRoundTripTests {
  let serializer = ScenarioSerializer()
  let loader = ScenarioLoader()

  /// The visual-editor bridge (`EditablePhase.init(from:)` → `toPhase()`) is
  /// lossless for every phase kind — the #961 field-drop class.
  @Test func everyPhaseTypeRoundTripsThroughEditablePhase() {
    for type in PhaseType.allCases {
      let phase = canonicalPhase(for: type)
      let roundTripped = EditablePhase(from: phase).toPhase()
      #expect(
        roundTripped == phase,
        "EditablePhase visual round-trip dropped a field for \(type.rawValue)")
    }
  }

  /// `ScenarioSerializer` → `ScenarioLoader` preserves every phase kind's
  /// fields — the second, YAML half of the same round-trip.
  @Test func everyPhaseTypeRoundTripsThroughSerializer() throws {
    for type in PhaseType.allCases {
      let scenario = wrap(canonicalPhase(for: type))
      let reloaded = try loader.load(yaml: serializer.serialize(scenario))
      #expect(
        reloaded.phases == scenario.phases,
        "serializer round-trip dropped a field for \(type.rawValue)")
    }
  }

  /// `max_sentences` (#881) survives BOTH round-trip bridges at the top level
  /// AND nested inside a conditional branch — the two silent-drop surfaces the
  /// field could leak through (`EditablePhase.init(from:)`/`toPhase()` and
  /// `ScenarioSerializer`/`ScenarioLoader`).
  @Test func maxSentencesRoundTripsTopLevelAndNested() throws {
    let phase = Phase(
      type: .conditional, condition: "max_score >= 10",
      thenPhases: [
        Phase(
          type: .speakEach, prompt: "Final defense.",
          outputSchema: ["statement": "string"], maxSentences: 6)
      ],
      elsePhases: [
        Phase(type: .speakAll, prompt: "Continue.", outputSchema: ["statement": "string"])
      ],
      maxSentences: 1)

    // Visual bridge.
    let viaEditable = EditablePhase(from: phase).toPhase()
    #expect(viaEditable.maxSentences == 1)
    #expect(viaEditable.thenPhases?.first?.maxSentences == 6)

    // YAML bridge.
    let reloaded = try loader.load(yaml: serializer.serialize(wrap(phase)))
    #expect(reloaded.phases.first?.maxSentences == 1)
    #expect(reloaded.phases.first?.thenPhases?.first?.maxSentences == 6)
  }

  // One arm per PhaseType, no nested logic. Block disable rather than
  // `disable:next` (which would orphan the doc comment below it); the disable
  // command line must hold only the rule name, so this rationale is separate.
  // swiftlint:disable cyclomatic_complexity
  /// A canonical `Phase` populating every field the given phase type uses.
  /// **No `default:`** — a new `PhaseType` fails to compile until it gets a
  /// fixture here. Booleans use only the non-default value (`excludeSelf: true`)
  /// because `false` round-trips to `nil` by design (`EditablePhase.toPhase`).
  private func canonicalPhase(for type: PhaseType) -> Phase {
    switch type {
    case .speakAll:
      return Phase(
        type: .speakAll, prompt: "Speak.",
        outputSchema: ["statement": "string", "inner_thought": "string"])
    case .speakEach:
      return Phase(
        type: .speakEach, prompt: "Speak in turn.",
        outputSchema: ["statement": "string"], subRounds: 2)
    case .vote:
      return Phase(
        type: .vote, prompt: "Vote.",
        outputSchema: ["vote": "string", "reason": "string"], excludeSelf: true)
    case .choose:
      return Phase(
        type: .choose, prompt: "Choose.", outputSchema: ["action": "string"],
        options: ["cooperate", "betray"], pairing: .roundRobin)
    case .reflect:
      return Phase(type: .reflect, prompt: "Reflect.", outputSchema: ["note": "string"])
    case .whisper:
      return Phase(
        type: .whisper, prompt: "Whisper.",
        outputSchema: ["statement": "string"], subRounds: 2)
    case .scoreCalc:
      return Phase(type: .scoreCalc, logic: .prisonersDilemma)
    case .assign:
      return Phase(type: .assign, source: "topics", target: .randomOne)
    case .eliminate:
      return Phase(type: .eliminate)
    case .summarize:
      return Phase(type: .summarize, template: "Round summary: {scoreboard}")
    case .conditional:
      return Phase(
        type: .conditional, condition: "max_score >= 10",
        thenPhases: [Phase(type: .summarize, template: "Done.")],
        elsePhases: [
          Phase(type: .speakAll, prompt: "Continue.", outputSchema: ["statement": "string"])
        ])
    case .eventInject:
      return Phase(
        type: .eventInject, source: "trials", probability: 0.5,
        eventVariable: "current_event")
    case .relationshipUpdate:
      return Phase(
        type: .relationshipUpdate, voteAgainst: -1,
        actionDeltas: ["cooperate": 1, "betray": -2])
    }
  }
  // swiftlint:enable cyclomatic_complexity

  /// Minimal loadable scenario wrapping a single phase for the serializer half.
  private func wrap(_ phase: Phase) -> Scenario {
    Scenario(
      id: "roundtrip", name: "Round Trip", description: "d", language: "en",
      agentCount: 2, rounds: 1, context: "c",
      personas: [
        Persona(name: "Alice", description: "a"),
        Persona(name: "Bob", description: "b")
      ],
      phases: [phase])
  }
}
