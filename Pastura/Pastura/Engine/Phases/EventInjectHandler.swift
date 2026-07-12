import Foundation

/// Handles `event_inject` phases — probabilistically injects a random
/// string from `Scenario.extraData` into `state.variables`.
///
/// Behavior:
/// - Resolves `Phase.source` against `Scenario.extraData`. The expected
///   shape is `.array(_)` of `String`, or `.arrayOfDictionaries(_)` of
///   `{ text, favors }` mappings (#931) — dict entries additionally write a
///   companion "favored action" variable (`<as>__favors`) read by
///   `EventReactivePayoffLogic`. Other shapes are surfaced as a `.summary`
///   warning so curators can fix the YAML; the variable is still written as
///   the empty string so subsequent prompt expansion never hits a missing key.
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
/// - `no_repeat: true` (#1006) draws **without replacement** across the run:
///   already-drawn events are tracked per variable in `state.drawnEvents` and
///   the pick is taken from the remainder, resetting to the full pool once
///   every entry has been drawn. Default is with-replacement. A miss never
///   consumes the pool. Identical-text entries collapse in the drawn `Set`, so
///   a curator relying on strict no-repeat should keep event texts distinct.
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

  /// Suffix convention for the companion "favored action" variable written
  /// alongside a dict-shaped event (`{ text, favors }`).
  /// `EventReactivePayoffLogic` reads it back via the same convention so the
  /// producer and consumer never drift. See #931.
  static func favoredVariableName(for eventVariable: String) -> String {
    "\(eventVariable)__favors"
  }

  func execute(
    context: PhaseContext,
    state: inout SimulationState
  ) async throws {
    let variableName = context.phase.eventVariable ?? Self.defaultVariableName
    let favoredName = Self.favoredVariableName(for: variableName)
    let probability = context.phase.probability ?? 1.0
    let sourceKey = context.phase.source ?? ""

    // Normalize the source into (text, favors?) entries. A plain [String]
    // source yields nil favors (unchanged #256 behavior, no companion var);
    // a [[String: String]] source carries the optional `favors` tag (#931).
    // `carriesFavors` gates every companion-var write so a plain-string
    // scenario never grows a new variable — existing scenarios unaffected.
    let events: [(text: String, favors: String?)]
    let carriesFavors: Bool
    switch context.scenario.extraData[sourceKey] {
    case .array(let strings):
      events = strings.map { (text: $0, favors: nil) }
      carriesFavors = false
    case .arrayOfDictionaries(let dicts):
      events = dicts.map { (text: $0["text"] ?? "", favors: $0["favors"]) }
      carriesFavors = true
    default:
      // Missing-key / wrong-shape is curator-fixable so we surface a
      // .summary warning rather than throwing — the simulation continues
      // with the variable set to "" so downstream prompts don't break.
      if !sourceKey.isEmpty {
        context.emitter(
          .summary(
            text: "⚠️ event_inject: source '\(sourceKey)' "
              + "not found or not a list of events — no event injected this round."
          ))
      }
      state.variables[variableName] = ""
      context.emitter(.eventInjected(event: nil))
      return
    }

    // A miss writes "" to BOTH the event var and (for dict sources) the
    // favored var, so neither a prior round's event nor its favored action
    // ghosts into this round's prompt or `event_reactive` scoring.
    func miss() {
      state.variables[variableName] = ""
      if carriesFavors { state.variables[favoredName] = "" }
      context.emitter(.eventInjected(event: nil))
    }

    // Empty list: same observable shape as a probability miss. Curator may
    // intend to disable injection by clearing the list mid-development.
    guard !events.isEmpty else {
      miss()
      return
    }

    // Strict `<` with `[0..<1)` gives the documented boundary semantics:
    //   probability = 0.0 → roll < 0.0 is always false → never fires
    //   probability = 1.0 → roll < 1.0 is always true  → always fires
    // (`<=` would allow `probability = 0.0` to occasionally fire when
    // RNG returns exactly 0.0.)
    let roll = Double.random(in: 0..<1)
    guard roll < probability else {
      miss()
      return
    }

    // `no_repeat` (#1006) draws from the not-yet-drawn remainder and records
    // the pick; the default path keeps plain with-replacement selection.
    // randomElement() on a non-empty array always returns Some — the guard
    // above guarantees `events.isEmpty == false` — so the `??` is a no-op
    // safety net. Both branches funnel the chosen tuple through the SAME
    // variable / favored-var writes below, so dict-shaped `{text,favors}`
    // scoring (#931) is preserved regardless of draw mode.
    let chosen: (text: String, favors: String?) =
      context.phase.noRepeat == true
      ? pickWithoutRepeat(events, variableName: variableName, state: &state)
      : (events.randomElement() ?? (text: "", favors: nil))

    state.variables[variableName] = chosen.text
    // Write "" (not absent) for a dict entry with no `favors` tag, so an
    // earlier round's favored action never ghosts into `event_reactive`.
    if carriesFavors { state.variables[favoredName] = chosen.favors ?? "" }
    context.emitter(.eventInjected(event: chosen.text))
  }

  /// Draws an event not yet chosen this run (`no_repeat`), recording the pick
  /// in `state.drawnEvents[variableName]`. When every entry has already been
  /// drawn the pool is reset and a fresh full draw is taken — a late repeat is
  /// preferable to blanking the variable mid-scenario (#1006). `events` is
  /// guaranteed non-empty by the caller, so the `??` is an unreachable safety
  /// net mirroring the default path.
  private func pickWithoutRepeat(
    _ events: [(text: String, favors: String?)],
    variableName: String,
    state: inout SimulationState
  ) -> (text: String, favors: String?) {
    let drawn = state.drawnEvents[variableName] ?? []
    var remaining = events.filter { !drawn.contains($0.text) }
    if remaining.isEmpty {
      // Pool exhausted — reset so the next draw sees the full list again.
      state.drawnEvents[variableName] = []
      remaining = events
    }
    let chosen = remaining.randomElement() ?? (text: "", favors: nil)
    state.drawnEvents[variableName, default: []].insert(chosen.text)
    return chosen
  }
}
