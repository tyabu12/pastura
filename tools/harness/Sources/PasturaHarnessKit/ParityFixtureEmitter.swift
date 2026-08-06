import Foundation
import PasturaCore

/// Emits the ADR-023 Stage-4 cross-language parity fixtures: for one scenario
/// and one scripted-response plan, the scenario, the exact model answers, and
/// the Swift Engine's resulting event transcript, frozen as Kotlin constants.
///
/// **Why the transcript is `EventLine`, not `SimulationEvent`.** Swift's
/// `SimulationEvent` is `Sendable, Equatable` — it has no `Codable`
/// conformance, and adding one for a harness would put a wire contract on a
/// callback-boundary type that nothing in production serializes (ADR-023 §12
/// PR0-b, and the condition-1 tag-form ruling). ``EventLineMapper`` already
/// defines this repo's transcript surface, is already reviewed, and already
/// carries a compile-time canary — so the parity harness reuses it rather than
/// authoring a second projection.
///
/// **Why it is deterministic.** `EventLineMapper.map` takes `t` and `attempt`
/// as parameters rather than reading a clock, so pinning both to zero removes
/// every timestamp and identity source from the transcript. The two events the
/// mapper drops are dropped for cause, not convenience: both engines emit
/// `agentOutputStream` with payloads that differ by construction (Swift runs a
/// partial-output extractor over each chunk, Kotlin forwards the raw text), and
/// both emit `roundCheckpoint` carrying a full `SimulationState` whose parity
/// the Models rung already covers.
///
/// **Why the scenario crosses as JSON.** `ScenarioLoader` has no Kotlin port
/// yet (ADR-023 Stage 3), so re-parsing the YAML on the Kotlin side would
/// measure a loader that does not exist. Encoding the loaded `Scenario`
/// isolates Stage 4 from that gap; loader parity becomes its own obligation
/// when the port lands.
package enum ParityFixtureEmitter {

  /// One scenario plus the response plan that drives it.
  package struct FixtureSpec: Sendable {
    /// Kotlin constant prefix and test label.
    package let name: String
    /// Repo-relative scenario path, resolved against the current directory.
    package let scenarioPath: String
    /// What this fixture is for, carried into the generated file.
    package let purpose: String
    /// Answers replacing the derived one at a given 0-based call index — see
    /// ``RecordingResponder``. Empty for a nominal run.
    package let overrides: [Int: String]

    package init(
      name: String, scenarioPath: String, purpose: String, overrides: [Int: String] = [:]
    ) {
      self.name = name
      self.scenarioPath = scenarioPath
      self.purpose = purpose
      self.overrides = overrides
    }
  }

  /// A completed Swift-side run, ready to freeze.
  package struct Fixture: Sendable, Equatable {
    package let name: String
    package let purpose: String
    /// The loaded `Scenario`, JSON-encoded with sorted keys.
    package let scenarioJSON: String
    /// Model answers in call order — what Kotlin's `ScriptedLLMBackend` replays.
    package let responses: [String]
    /// One JSON object per surviving event, in emission order.
    package let transcript: [String]
    /// Backend calls the Swift Engine issued. A first-class field because the
    /// schema-guard divergence is a retry-count divergence the transcript alone
    /// cannot show.
    package let callCount: Int

    /// Explicit because the implicit memberwise init is `internal`, and the
    /// raw-string safety guard is tested from the sibling test module.
    package init(
      name: String, purpose: String, scenarioJSON: String,
      responses: [String], transcript: [String], callCount: Int
    ) {
      self.name = name
      self.purpose = purpose
      self.scenarioJSON = scenarioJSON
      self.responses = responses
      self.transcript = transcript
      self.callCount = callCount
    }
  }

  /// The fixtures this repo freezes, in emission order.
  ///
  /// `target_score_race` is one of three bundled presets that are fully
  /// deterministic — neither engine injects RNG, and both rely on degenerate
  /// inputs rather than seeding — and it is the only one of those three that
  /// exercises `conditional`.
  package static let specs: [FixtureSpec] = [
    FixtureSpec(
      name: "targetScoreRaceNominal",
      scenarioPath: "Pastura/Pastura/Resources/Presets/target_score_race.yaml",
      purpose: """
        Happy path. Every answer is well-formed and non-empty, so a green \
        comparison here means the two engines agree with an empty divergence \
        ledger — which is Stage 4's actual goal, not merely that the harness runs.
        """
    )
  ]

  /// Runs one spec through the Swift Engine.
  package static func run(_ spec: FixtureSpec) async throws -> Fixture {
    let yaml = try String(contentsOfFile: spec.scenarioPath, encoding: .utf8)
    let scenario = try ScenarioLoader().load(yaml: yaml)
    let responder = RecordingResponder(
      personas: scenario.personas.map(\.name), overrides: spec.overrides)

    var transcript: [String] = []
    let stream = SimulationRunner().run(
      scenario: scenario, llm: responder, suspendController: SuspendController())
    for await event in stream {
      guard let line = EventLineMapper.map(normalize(event), t: 0, attempt: 0) else { continue }
      transcript.append(try JSONL.encode(line))
    }

    return Fixture(
      name: spec.name,
      purpose: spec.purpose,
      scenarioJSON: try encodeScenario(scenario),
      responses: responder.recordedResponses,
      transcript: transcript,
      callCount: responder.callCount)
  }

  /// Zeroes the one measured quantity a `SimulationEvent` payload carries.
  ///
  /// Pinning `EventLineMapper`'s `t` and `attempt` removes the harness's own
  /// clock reads, but `inferenceCompleted` carries `durationSeconds` **inside
  /// the event**, measured per call. Left alone it changes on every run, so
  /// `--check` would report drift against itself and the two engines could
  /// never agree. `tokenCount` needs no arm: this responder reports none, and
  /// the Kotlin fixtures script none either — if that ever changes, the
  /// mismatch surfaces as a parity diff rather than as flakiness.
  ///
  /// Deliberately an `if case` rather than an exhaustive `switch`: this is a
  /// narrow denylist of measured fields, and a new case is normalization-free
  /// until someone shows otherwise. The exhaustiveness obligation belongs to
  /// `EventLineMapper`, which already carries it.
  private static func normalize(_ event: SimulationEvent) -> SimulationEvent {
    if case .inferenceCompleted(let agent, _, let tokenCount) = event {
      return .inferenceCompleted(agent: agent, durationSeconds: 0, tokenCount: tokenCount)
    }
    return event
  }

  /// Repo-relative path of the generated Kotlin file, named once so the CLI,
  /// the drift gate, and the docs cannot disagree.
  package static let generatedPath =
    "shared/engine/src/commonTest/kotlin/com/pastura/engine/ParityGolden.kt"

  /// The command that regenerates it, quoted in the file header and in the
  /// drift-gate failure message.
  package static let regenerateCommand = "swift run pastura-harness parity-emit --write"

  /// Renders every fixture as a Kotlin source file of raw-string constants.
  ///
  /// **Why generated Kotlin rather than a resource file.** No test anywhere
  /// under `shared/` reads from disk outside `jvmTest` — the two that do use
  /// `getResourceAsStream` / `java.io.File`, both JVM-only. ADR-023 Decision 5
  /// requires the Kotlin/Native `macosArm64` rung as well, and an embedded
  /// source constant is the only form that reaches it. The trade-off bought is
  /// a generated file, hence the `--check` gate.
  package static func kotlinSource(from fixtures: [Fixture]) throws -> String {
    var lines: [String] = [
      "// Generated by `\(regenerateCommand)` — DO NOT edit by hand.",
      "//",
      "// ADR-023 Stage-4 cross-language parity fixtures. Each entry carries the",
      "// scenario, the exact model answers the Swift Engine consumed, the event",
      "// transcript it produced, and the backend call count. `EngineParityTests`",
      "// replays the answers through the Kotlin Engine and compares.",
      "//",
      "// The transcript is `EventLineMapper`'s projection with `t` and `attempt`",
      "// pinned to 0 — see `ParityFixtureEmitter` for why that projection and not",
      "// a `SimulationEvent` encoding.",
      "",
      "package com.pastura.engine",
      "",
      "internal object ParityGolden {",
      "",
      "    /** One frozen Swift-side run. */",
      "    internal data class Fixture(",
      "        val name: String,",
      "        val scenarioJson: String,",
      "        val responses: List<String>,",
      "        val transcript: List<String>,",
      "        val callCount: Int,",
      "    )"
    ]

    for fixture in fixtures {
      try assertRawStringSafe(fixture)
      lines.append("")
      lines.append(contentsOf: kdoc(fixture.purpose))
      lines.append("    internal val \(fixture.name): Fixture = Fixture(")
      lines.append("        name = \"\(fixture.name)\",")
      lines.append("        scenarioJson = \"\"\"")
      lines.append(fixture.scenarioJSON)
      lines.append("\"\"\",")
      lines.append(contentsOf: stringList("responses", fixture.responses))
      lines.append(contentsOf: stringList("transcript", fixture.transcript))
      lines.append("        callCount = \(fixture.callCount),")
      lines.append("    )")
    }

    lines.append("}")
    lines.append("")
    return lines.joined(separator: "\n")
  }

  /// Renders a `listOf(...)` of raw strings, one entry per line.
  private static func stringList(_ label: String, _ values: [String]) -> [String] {
    guard !values.isEmpty else { return ["        \(label) = emptyList(),"] }
    var lines = ["        \(label) = listOf("]
    for value in values {
      lines.append("            \"\"\"\(value)\"\"\",")
    }
    lines.append("        ),")
    return lines
  }

  /// Wraps a purpose string as a KDoc block.
  private static func kdoc(_ purpose: String) -> [String] {
    var lines = ["    /**"]
    for line in purpose.split(separator: "\n", omittingEmptySubsequences: false) {
      lines.append(line.isEmpty ? "     *" : "     * \(line)")
    }
    lines.append("     */")
    return lines
  }

  /// Rejects bytes a Kotlin raw string would mangle.
  ///
  /// `"""` closes the literal early and `$` is read as template interpolation.
  /// Scenario prose is author-controlled, so this exists to fail loudly at
  /// generation time rather than emit a file that does not compile — or worse,
  /// one that compiles carrying silently different bytes.
  private static func assertRawStringSafe(_ fixture: Fixture) throws {
    let payloads = [fixture.scenarioJSON] + fixture.responses + fixture.transcript
    for payload in payloads {
      if payload.contains("\"\"\"") {
        throw ParityFixtureError.rawStringUnsafe(fixture.name, #"a """ sequence"#)
      }
      if payload.contains("$") {
        throw ParityFixtureError.rawStringUnsafe(fixture.name, "a $ (Kotlin interpolates it)")
      }
    }
  }

  /// Encodes the scenario with sorted keys so `--check` reports real drift
  /// rather than dictionary-order churn.
  private static func encodeScenario(_ scenario: Scenario) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let data = try encoder.encode(scenario)
    guard let json = String(data: data, encoding: .utf8) else {
      throw ParityFixtureError.notUTF8(scenario.id)
    }
    return json
  }
}

/// Why a parity fixture could not be produced.
package enum ParityFixtureError: Error, CustomStringConvertible {
  /// A scenario encoded to bytes that are not valid UTF-8.
  case notUTF8(String)
  /// A fixture contains bytes a Kotlin raw string cannot carry verbatim.
  case rawStringUnsafe(String, String)

  package var description: String {
    switch self {
    case .notUTF8(let name):
      return "parity fixture '\(name)' encoded to non-UTF-8 bytes"
    case .rawStringUnsafe(let name, let reason):
      return
        "parity fixture '\(name)' cannot be embedded in a Kotlin raw string: it contains \(reason)"
    }
  }
}
