import SwiftUI

// Event-inject phase UI for `PhaseEditorSheet`: source / probability /
// variable-name fields. Split out from `PhaseEditorSheet.swift` to keep
// that file under SwiftLint's `file_length` limit. Accesses `phase` from
// the parent struct.

extension PhaseEditorSheet {
  var eventInjectSection: some View {
    Group {
      Section {
        TextField(String(localized: "Top-level YAML key"), text: $phase.source)
          .textInputAutocapitalization(.never)
          .accessibilityLabel("Source")
      } header: {
        Text(String(localized: "Source"))
      } footer: {
        Text(
          String(
            localized:
              "References a top-level field in the scenario YAML — must be a list of strings (e.g., random_events: [...])"
          )
        )
      }

      Section {
        Stepper(
          "Chance: \(String(format: "%g", probabilityBinding.wrappedValue))",
          value: probabilityBinding,
          in: 0.0...1.0,
          step: 0.1
        )
      } footer: {
        Text(
          String(
            localized: "Roll < probability fires. 1 = always fires; 0 = never fires."
          )
        )
      }

      Section {
        // Placeholder "current_event" is the literal default value the
        // phase falls back to when this field is empty (see footer);
        // localizing it would diverge from the model-layer default.
        TextField("current_event", text: $phase.eventVariable)
          .textInputAutocapitalization(.never)
          .accessibilityLabel("Variable name")
      } header: {
        Text(String(localized: "Variable name"))
      } footer: {
        Text(
          String(
            localized:
              "Variable written by this phase. Reference in subsequent prompts as {<name>}. Defaults to current_event when empty."
          )
        )
      }
    }
  }

  // `probabilityBinding` is `fileprivate` so it must stay co-located with
  // its sole caller (`eventInjectSection`). If either is moved back to
  // the main file, both must move together.
  fileprivate var probabilityBinding: Binding<Double> {
    Binding(
      get: { phase.probability ?? 1.0 },
      // Snap to one decimal so Stepper's `step: 0.1` increments don't
      // accumulate IEEE-754 drift (0.1+0.1+0.1=0.30000000000000004) into
      // serialized YAML. Setter only fires on user interaction, so a
      // phase the curator never touched stays nil-on-read / nil-on-save.
      set: { phase.probability = ($0 * 10).rounded() / 10 }
    )
  }
}
