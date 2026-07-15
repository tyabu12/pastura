import Foundation

/// Localized descriptions for the canonical LLM output-field names an author
/// configures on a phase's `output:` schema.
///
/// Views-layer **display** single source of truth — the canonical
/// field-per-phase mapping stays in Models' ``ScenarioConventions``. Shown as an
/// inline caption under each row in the editor's Output Fields section so an
/// author understands `inner_thought` / `reason` / `mood` without leaving the
/// editor.
///
/// Returns `nil` for a non-canonical / custom key, so the caption is simply
/// omitted (an author's own field names carry no engine-defined meaning).
///
/// ## Coverage
///
/// `FieldDisplayTests` asserts every canonical field
/// (``ScenarioConventions/primaryField(for:)`` / ``ScenarioConventions/thoughtField(for:)``
/// over all phase types) plus the opt-in `mood` field (#913) has a description.
enum FieldDisplay {

  /// A short localized description of the output field named `field`, or `nil`
  /// when `field` is not a canonical engine-recognized field.
  static func description(for field: String) -> String? {
    switch field {
    // Phase-agnostic: speak statements enter the public conversation log,
    // whisper statements stay private but are still shown in the UI — so the
    // caption claims only the UI, not the log (which would be wrong for
    // whisper). The public/private distinction is carried by the phase-type
    // description under the picker.
    case "statement":
      return String(localized: "The main spoken text, shown in the UI.")
    case "action":
      return String(localized: "The chosen value. Restricted to the phase's options.")
    case "vote":
      return String(localized: "The name of the agent being voted for.")
    case "note":
      return String(localized: "The agent's private memo (reflect only). Never shown to others.")
    case "inner_thought":
      return String(
        localized:
          "The agent's private thought. Shown as a thought bubble, never in the public log."
      )
    case "reason":
      return String(localized: "The private reason behind the vote.")
    case "mood":
      return String(localized: "The agent's mood, carried into their next prompt (opt-in inertia).")
    default:
      return nil
    }
  }
}
