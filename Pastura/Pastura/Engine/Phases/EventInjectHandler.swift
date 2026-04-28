import Foundation

/// Handles `event_inject` phases — probabilistically injects a random
/// string from `Scenario.extraData` into `state.variables`.
///
/// Behavior:
/// - Resolves `Phase.source` against `Scenario.extraData`. The expected
///   shape is `.array(_)` of `String`. Other shapes are surfaced as a
///   `.summary` warning so curators can fix the YAML; the variable is
///   still written as the empty string so subsequent prompt expansion
///   never hits a missing key.
/// - Rolls `Double.random(in: 0..<1) < probability`. Strict `<` against
///   the half-open range gives the boundary semantics curators expect:
///   `probability = 0.0` never fires, `probability = 1.0` always fires
///   (since `random(in: 0..<1)` can return 0.0 but never 1.0).
/// - On miss (roll failed, source missing, or source empty), writes the
///   empty string to `state.variables[as]` and emits
///   `.eventInjected(nil)`. The empty-string write — rather than leaving
///   the key absent — prevents a previous round's value from "ghosting"
///   into the next prompt and keeps `PromptBuilder.expandTemplate`'s
///   substitution well-defined.
/// - On hit, picks a random element via `randomElement()` and writes it
///   to `state.variables[as]`, emitting `.eventInjected(event)`.
///
/// RNG is not injected. The probability boundaries (0.0 / 1.0) make the
/// fire/miss decision deterministically testable, and a single-element
/// `source` makes the `randomElement()` pick deterministic too —
/// matching the project's pattern in `AssignHandler` (which also uses
/// `randomElement()` and `Int.random(in:)` directly without injection).
nonisolated struct EventInjectHandler: PhaseHandler {

  /// Default variable name written when `Phase.eventVariable` is `nil`.
  ///
  /// Public so the editor's prompt-variables footer and tests can
  /// reference the same canonical name.
  static let defaultVariableName = "current_event"

  func execute(
    context: PhaseContext,
    state: inout SimulationState
  ) async throws {
    let variableName = context.phase.eventVariable ?? Self.defaultVariableName
    let probability = context.phase.probability ?? 1.0
    let sourceKey = context.phase.source ?? ""

    // Resolve source; missing-key is curator-fixable so we surface a
    // .summary warning rather than throwing — the simulation continues
    // with the variable set to "" so downstream prompts don't break.
    guard case .array(let events)? = context.scenario.extraData[sourceKey] else {
      if !sourceKey.isEmpty {
        context.emitter(
          .summary(
            text: "⚠️ event_inject: source '\(sourceKey)' "
              + "not found or not a list of strings — no event injected this round."
          ))
      }
      state.variables[variableName] = ""
      context.emitter(.eventInjected(event: nil))
      return
    }

    // Empty array: same observable shape as a probability miss — empty
    // string into the variable and `.eventInjected(nil)`. Curator may
    // intend to disable injection by clearing the list mid-development.
    guard !events.isEmpty else {
      state.variables[variableName] = ""
      context.emitter(.eventInjected(event: nil))
      return
    }

    // Strict `<` with `[0..<1)` gives the documented boundary semantics:
    //   probability = 0.0 → roll < 0.0 is always false → never fires
    //   probability = 1.0 → roll < 1.0 is always true  → always fires
    // (`<=` would allow `probability = 0.0` to occasionally fire when
    // RNG returns exactly 0.0.)
    let roll = Double.random(in: 0..<1)
    guard roll < probability else {
      state.variables[variableName] = ""
      context.emitter(.eventInjected(event: nil))
      return
    }

    // randomElement() on a non-empty array always returns Some — the
    // guard above guarantees `events.isEmpty == false`. The `??` is a
    // no-op safety net rather than a real fallback path.
    let chosen = events.randomElement() ?? ""
    state.variables[variableName] = chosen
    context.emitter(.eventInjected(event: chosen))
  }
}
