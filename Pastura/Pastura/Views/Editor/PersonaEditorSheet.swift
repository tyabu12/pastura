import SwiftUI

/// A modal sheet for creating or editing a single persona's name and description.
///
/// On Save tap, runs `ScenarioContentValidator` against the current `name`
/// and `description`. If either field contains a blocked pattern, the
/// sheet sets per-field error state and stays presented; otherwise the
/// existing `onSave` callback fires and the sheet dismisses (#261).
/// Per ADR-005 §4.7, error messages do not echo the matched term.
struct PersonaEditorSheet: View {
  @Environment(\.dismiss) private var dismiss
  @State var name: String
  @State var description: String
  @State private var nameError: String?
  @State private var descriptionError: String?
  let onSave: (String, String) -> Void
  let validator: ScenarioContentValidator

  init(
    name: String,
    description: String,
    validator: ScenarioContentValidator = ScenarioContentValidator(),
    onSave: @escaping (String, String) -> Void
  ) {
    self._name = State(initialValue: name)
    self._description = State(initialValue: description)
    self.validator = validator
    self.onSave = onSave
  }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          TextField("Persona name", text: $name)
        } header: {
          Text("Name")
        } footer: {
          if let nameError {
            Text(nameError)
              .font(.caption)
              .foregroundStyle(Color.danger)
          }
        }

        Section {
          TextEditor(text: $description)
            .frame(minHeight: 88)
        } header: {
          Text("Description")
        } footer: {
          if let descriptionError {
            Text(descriptionError)
              .font(.caption)
              .foregroundStyle(Color.danger)
          }
        }
      }
      .navigationTitle(name.isEmpty ? "New Persona" : "Edit Persona")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") {
            dismiss()
          }
        }

        ToolbarItem(placement: .confirmationAction) {
          Button("Save") {
            let findings = validator.validate(
              personaName: name,
              description: description
            )
            if findings.hasIssue {
              nameError = findings.name
              descriptionError = findings.description
              return
            }
            onSave(name, description)
            dismiss()
          }
          .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
      }
    }
  }
}
