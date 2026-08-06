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
    /// How many `vote`-schema calls have been answered.
    ///
    /// Tracked separately from `responses.count` because the vote rotation must
    /// be immune to retries in *other* phases: keying it on the global call
    /// index made the divergent fixture's three-call retry window shift the
    /// whole stream by two, which put every vote back on its own voter.
    var voteCallCount: Int = 0
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
        overrides[index]
        ?? Self.derive(
          schema: schema, callIndex: index, voteIndex: state.voteCallCount, personas: personas)
      // Counted on every vote-schema call, including one an override answered:
      // the rotation must track the phase's own position, and an override that
      // did not advance it would desynchronize every vote after it.
      if Self.declaresVote(schema) { state.voteCallCount += 1 }
      state.responses.append(response)
      return response
    }
  }

  /// Whether a call's schema is a `vote` turn.
  private static func declaresVote(_ schema: OutputSchema?) -> Bool {
    schema?.fields.contains { $0.name == "vote" } ?? false
  }

  /// Builds one answer from the schema's declared fields.
  ///
  /// A schema-less call (no `output:` on the phase) still gets a JSON object:
  /// both engines run the same parser, and a non-JSON answer would exercise the
  /// repair pipeline rather than the phase under test.
  private static func derive(
    schema: OutputSchema?, callIndex: Int, voteIndex: Int, personas: [String]
  ) -> String {
    let fields = schema?.fields ?? []
    guard !fields.isEmpty else {
      return #"{"statement": "turn \#(callIndex)"}"#
    }
    let pairs = fields.map { field in
      let rendered = value(
        for: field, callIndex: callIndex, voteIndex: voteIndex, personas: personas)
      return "\"\(field.name)\": \"\(rendered)\""
    }
    return "{\(pairs.joined(separator: ", "))}"
  }

  /// The value for one field.
  ///
  /// `vote` resolves to a persona so the tally can count it. Every other field
  /// gets a call-indexed string, which makes the transcript discriminating: two
  /// turns that should differ cannot compare equal by accident.
  ///
  /// **The rotation is a heuristic; the guarantee is the test.** This responder
  /// deliberately cannot see *which* agent is calling — it reads the schema only
  /// — so it cannot exclude a self-vote by construction. What it can do is
  /// rotate off the diagonal, and key that rotation on the **vote-call index**
  /// rather than the global one.
  ///
  /// Both parts were learned the expensive way. Keying on the global index made
  /// every vote land on its own voter for a scenario whose per-round call count
  /// is a multiple of the persona count, so `exclude_self` dropped all of them
  /// and the tally, the scoreboard and the conditional's taken branch were all
  /// frozen while the fixture still looked like a full run. Adding `+ 1` fixed
  /// the nominal fixture and left the divergent one broken, because its
  /// three-call retry window shifts the global stream by two and lands back on
  /// the diagonal — a phase-local counter is immune to that, a global one is
  /// not.
  ///
  /// `everyFixtureExercisesVotingNotJustItsShape` asserts the non-degenerate
  /// outcome for **every** spec. Scoping that check to one spec is exactly how
  /// the second instance survived a review round.
  private static func value(
    for field: OutputSchema.Field, callIndex: Int, voteIndex: Int, personas: [String]
  ) -> String {
    guard field.name == "vote", !personas.isEmpty else {
      return "\(field.name) \(callIndex)"
    }
    return personas[(voteIndex + 1) % personas.count]
  }
}
