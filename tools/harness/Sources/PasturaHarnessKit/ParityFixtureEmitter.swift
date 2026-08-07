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
    ///
    /// **Positional, with no per-call alignment tag.** If the two engines ever
    /// issue different call counts mid-run, every later answer shifts and the
    /// downstream transcript diff becomes noise attributed to the engines.
    /// [callCount] catches the total mismatch, but only after a whole diverged
    /// transcript has been produced. Slice 1b should add a parallel tag list
    /// (`<agent>/<phase>/<attempt>`) so the Kotlin side can fail at the first
    /// drift with a locatable message rather than at the end with a wall of
    /// diffs.
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
  ///
  /// "Exercises `conditional`" means the **branch**, not merely the node: an
  /// earlier draft of the responder made every vote a self-vote, so every tally
  /// was empty, every score stayed 0, and `max_score >= 3` was false in all four
  /// evaluations — the phase ran and decided nothing. A fixture can look like a
  /// full run while its whole scoring half is frozen, so
  /// `nominalRunExercisesVotingNotJustItsShape` asserts the non-degenerate
  /// outcome rather than leaving it to the responder's arithmetic.
  package static let specs: [FixtureSpec] = [
    FixtureSpec(
      name: "targetScoreRaceNominal",
      scenarioPath: "Pastura/Pastura/Resources/Presets/target_score_race.yaml",
      purpose: """
        Happy path. Every answer is well-formed and non-empty, so a green \
        comparison here means the two engines agree with an empty divergence \
        ledger — which is Stage 4's actual goal, not merely that the harness runs.
        """
    ),
    FixtureSpec(
      name: "targetScoreRaceDivergent",
      scenarioPath: "Pastura/Pastura/Resources/Presets/target_score_race.yaml",
      purpose: """
        Negative control. A ledger whose entries never fire ships unexercised, \
        so this fixture drives documented divergences on purpose and the parity \
        suite fails if one stops firing.

        **It currently drives a VALUE divergence only.** It used to drive one of \
        each entry kind: calls 0-2 answer the first agent's schema-declaring \
        `speak_all` turn with present-but-empty canonical fields across the \
        whole retry window, which Swift returned as an `agentOutput` while \
        Kotlin's parser guard exhausted retries into a `turnSkipped` — a \
        STRUCTURAL divergence. ADR-021 § Amendment 2026-08-06 resolved it: both \
        engines now skip that turn, so the arm no longer fires and \
        `SCHEMA_GUARD_POSITION` was retired from the ledger. The empty-field \
        overrides are kept because they still exercise the retry window \
        identically on both sides.

        No **currently-ledgered** structural class is reachable from a scripted \
        fixture: `CANCELLATION_EVENT_TAIL` needs a mid-run cancellation this \
        emitter never performs, `DETECTOR_UNWIRED` is deliberately guarded off \
        (a real detector would make the golden vary by host — see \
        `parityRunEmitsNoLanguageMismatch`), and `VALIDATOR_UNPORTED` needs a \
        scenario Swift rejects, which would produce no transcript.

        That is an enumeration over today's `DivergenceClass` cases, so it \
        cannot see a structural divergence that is not yet ledgered — and one \
        is: Swift's schema-guarded multi-object salvage (#907) accepts \
        `{"statement": "hello", "inner_thought": "thinking"}{"stray": 1}` on a \
        schema-declaring turn, while Kotlin's `extractFirstJsonObject` returns object-like \
        residue unchanged and fails the parse into a `turnSkipped`. Scripting \
        that response here re-arms a structural arm. It is deferred, not \
        impossible: the arm needs a new `DivergenceClass` case, and a case with \
        no entry is exactly the pre-approved licence `DivergenceLedger` warns \
        about — while nothing consumes `ParityGolden` yet to verify the arm \
        end-to-end. The asymmetry is instead pinned by paired \
        `JSONResponseParser` tests in both languages. Tracked on #501.

        Do not read a clean structural comparison here as evidence the \
        structural path is exercised.

        The float-valued key below is the surviving arm. Swift normalizes `1.0` \
        to "1" because `NSNumber.stringValue` drops the `.0`; Kotlin preserves \
        the literal as "1.0". That is a VALUE divergence, and the one \
        `JSONResponseParser.kt` routes to Stage 4 to rule on.
        """,
      overrides: [
        0: #"{"statement": "", "inner_thought": ""}"#,
        1: #"{"statement": "", "inner_thought": ""}"#,
        2: #"{"statement": "", "inner_thought": ""}"#,
        3: #"{"statement": "s", "inner_thought": "t", "confidence": 1.0}"#
      ]
    )
  ]

  /// Runs one spec through the Swift Engine.
  package static func run(_ spec: FixtureSpec) async throws -> Fixture {
    let yaml = try String(contentsOfFile: spec.scenarioPath, encoding: .utf8)
    let scenario = try ScenarioLoader().load(yaml: yaml)
    let responder = RecordingResponder(
      personas: scenario.personas.map(\.name), overrides: spec.overrides)

    var transcript: [String] = []
    // No `detector:` — deliberate, and the inverse of what `HarnessRunner` does
    // eleven files away (it injects one precisely so `language_mismatch` is not
    // 0 by construction, #1234). Two reasons it must stay omitted here:
    // `HarnessLanguageDetector` wraps `NLLanguageRecognizer`, an OS-version-
    // dependent classifier that would make the golden vary by host; and it has
    // no Kotlin counterpart yet, so any event it produced would be a divergence
    // about the harness rather than about the engines. `parityRunEmitsNoLanguageMismatch`
    // guards the omission.
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
  /// a generated file, which is what `parity-emit --check` exists to guard.
  ///
  /// **That gate runs in CI** — `harness-build`, next to `emit-golden --check`.
  /// It was deferred to slice 1b on the grounds that it would gate a fixture
  /// nothing reads; that weighed the wrong thing — staleness in the *generated*
  /// file needs no consumer, and #1397 changed it while nothing was watching.
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
      // `.trimIndent()` because Kotlin — unlike a Java text block — keeps the
      // newline after the opening `"""` and the one before the closing one.
      // Without it this one field's bytes would be `"\n" + <what Swift emitted>
      // + "\n"` while `responses` and `transcript` are exact, and slice 1b's
      // consumer would have to know which fields to trim. `trimIndent` strips
      // the blank first/last lines and finds no common indentation to remove,
      // since the JSON sits at column 0.
      lines.append("        scenarioJson = \"\"\"")
      lines.append(fixture.scenarioJSON)
      lines.append("\"\"\".trimIndent(),")
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
      // A payload ending in `"` abuts the closing delimiter and yields `""""`,
      // which Kotlin cannot parse. Unreachable today — every payload is a JSON
      // object ending in `}` — so this keeps the guard as wide as its own claim
      // rather than as wide as today's inputs.
      if payload.hasSuffix("\"") {
        throw ParityFixtureError.rawStringUnsafe(fixture.name, "a trailing quote")
      }
      // Symmetry, not an asserted parse failure. Kotlin's documented raw-string
      // limitation is the *trailing* quote — the opener is exactly three quotes,
      // so a fourth at the start is content. A leading quote is rejected here as
      // conservatism rather than because it is known to break the parse; the
      // claim is deliberately weaker than the trailing arm's, which is verified.
      if payload.hasPrefix("\"") {
        throw ParityFixtureError.rawStringUnsafe(fixture.name, "a leading quote")
      }
    }
    // The name is interpolated as a Kotlin *identifier* (`internal val <name>`),
    // not into a string, so it has its own way to produce a file that does not
    // compile.
    if !fixture.name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) {
      throw ParityFixtureError.rawStringUnsafe(
        fixture.name, "a non-identifier character in its name")
    }
    // `purpose` is not a raw-string payload but IS emitted into a KDoc block, so
    // it has its own way to break the build.
    if fixture.purpose.contains("*/") {
      throw ParityFixtureError.rawStringUnsafe(
        fixture.name, "a */ in its purpose (closes the KDoc)")
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
