import Foundation
import PasturaCore
import Synchronization

/// A deterministic ``LLMService`` that answers from the requested
/// ``OutputSchema`` alone and records what it answered.
///
/// This is the Swift half of the ADR-023 Stage-4 scripted-response seam: the
/// recorded list is what the Kotlin `ScriptedLLMBackend` replays, so both
/// engines see byte-identical model output and any transcript difference is
/// attributable to the engines rather than to the inputs.
///
/// **It must never read the prompt.** `PromptBuilder.formatScoreboard` is a
/// documented cross-language divergence (Swift orders `String` by Unicode
/// scalar and collapses canonically-equivalent `[String: Int]` keys; Kotlin
/// orders by UTF-16 code unit and keeps them), so a responder keyed on prompt
/// text would hand the two engines different scripts for the same run and
/// report the difference as an engine divergence. Keying on the schema — which
/// both engines derive from the same `Phase` — keeps the script an input rather
/// than a measurement.
///
/// Unlike ``MockLLMService``, which replays a flat list supplied up front, this
/// type *derives* each answer, so a scenario's call count does not have to be
/// predicted by hand before the run.
///
/// Plain `Sendable`, not `@unchecked` — but be exact about what that buys.
/// `Mutex` is declared `@unchecked Sendable` unconditionally, **not**
/// conditionally on its value, so the checked conformance here polices this
/// class's own stored properties only: a later unguarded `var` on the class
/// fails the build, while a non-`Sendable` mutable member added inside `State`
/// still compiles. Keep `State`'s members `Sendable` by hand.
/// (`.claude/rules/swift-isolation.md` Pattern 7's pairing advice, narrowed to
/// what it actually covers here.)
package final class RecordingResponder: LLMService, Sendable {

  /// Answers recorded so far, in call order.
  private struct State {
    var responses: [String] = []
  }

  private let state = Mutex(State())
  private let personas: [String]
  private let overrides: [Int: String]

  /// - Parameters:
  ///   - personas: Persona names in scenario order. Used to answer canonical
  ///     `vote` fields with a name the tally can actually resolve; a
  ///     lexically-invented name would be dropped by both engines and hide the
  ///     phase behind a no-op.
  ///   - overrides: Answers that replace the derived one at a given 0-based
  ///     call index. This is how a negative-control fixture drives a known
  ///     divergence — an empty canonical field, or a float-valued key — without
  ///     the derivation itself having to model the divergence.
  package init(personas: [String], overrides: [Int: String] = [:]) {
    self.personas = personas
    self.overrides = overrides
  }

  /// Every answer this responder produced, in call order.
  package var recordedResponses: [String] {
    state.withLock { $0.responses }
  }

  /// How many generate calls the engine issued.
  ///
  /// Recorded as a first-class fixture field rather than inferred from the
  /// transcript: the schema-guard divergence (`.claude/rules/kmp-interop.md`
  /// Pattern 4) is a *retry-count* divergence, and the transcript alone cannot
  /// distinguish "one call that succeeded" from "three that exhausted".
  package var callCount: Int {
    state.withLock { $0.responses.count }
  }

  package func loadModel() async throws {}
  package func unloadModel() async throws {}
  package var isModelLoaded: Bool { true }
  package let modelIdentifier = "parity-recorder"
  package let backendIdentifier = "parity-recorder"

  package func generate(
    system: String, user: String, schema: OutputSchema?,
    antiRepetitionSeeds: [String]
  ) async throws -> String {
    state.withLock { state in
      let index = state.responses.count
      let response =
        overrides[index] ?? Self.derive(schema: schema, callIndex: index, personas: personas)
      state.responses.append(response)
      return response
    }
  }

  /// Builds one answer from the schema's declared fields.
  ///
  /// A schema-less call (no `output:` on the phase) still gets a JSON object:
  /// both engines run the same parser, and a non-JSON answer would exercise the
  /// repair pipeline rather than the phase under test.
  private static func derive(
    schema: OutputSchema?, callIndex: Int, personas: [String]
  ) -> String {
    let fields = schema?.fields ?? []
    guard !fields.isEmpty else {
      return #"{"statement": "turn \#(callIndex)"}"#
    }
    let pairs = fields.map { field in
      "\"\(field.name)\": \"\(value(for: field, callIndex: callIndex, personas: personas))\""
    }
    return "{\(pairs.joined(separator: ", "))}"
  }

  /// The value for one field.
  ///
  /// `vote` resolves to a persona so the tally can count it. Every other field
  /// gets a call-indexed string, which makes the transcript discriminating: two
  /// turns that should differ cannot compare equal by accident.
  ///
  /// **The `+ 1` offset is not a guarantee, and the guarantee lives elsewhere.**
  /// This responder deliberately cannot see *which* agent is calling — it reads
  /// the schema only — so it cannot exclude a self-vote by construction. The
  /// offset merely avoids the alignment that a bare `callIndex % count` happens
  /// to produce for a scenario whose per-round call count is a multiple of the
  /// persona count: every vote lands on the voter, `exclude_self` drops all of
  /// them, and the tally, the scoreboard and the conditional's taken branch are
  /// all frozen in their degenerate state while the fixture still looks like a
  /// full run. Whether the offset actually works for a given scenario is
  /// asserted in `nominalRunExercisesVotingNotJustItsShape`, which reddens if it
  /// stops — the arithmetic here is a heuristic, that test is the contract.
  private static func value(
    for field: OutputSchema.Field, callIndex: Int, personas: [String]
  ) -> String {
    guard field.name == "vote", !personas.isEmpty else {
      return "\(field.name) \(callIndex)"
    }
    return personas[(callIndex + 1) % personas.count]
  }
}
