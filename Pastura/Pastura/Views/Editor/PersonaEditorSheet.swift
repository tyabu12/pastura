import SwiftUI

/// A modal sheet for creating or editing a single persona's name, description,
/// and optional hidden agenda (`secret`, #914).
///
/// On Save tap, runs `ScenarioContentValidator` against the current `name`,
/// `description`, and `secret`. If any field contains a blocked pattern, the
/// sheet sets per-field error state and stays presented; otherwise the
/// existing `onSave` callback fires and the sheet dismisses (#261).
/// Per ADR-005 §4.7, error messages do not echo the matched term.
struct PersonaEditorSheet: View {
  @Environment(\.dismiss) private var dismiss
  @State var name: String
  @State var description: String
  @State var secret: String
  @State private var nameError: String?
  @State private var descriptionError: String?
  @State private var secretError: String?
  let onSave: (String, String, String) -> Void
  let validator: ScenarioContentValidator

  init(
    name: String,
    description: String,
    secret: String = "",
    validator: ScenarioContentValidator = ScenarioContentValidator(),
    onSave: @escaping (String, String, String) -> Void
  ) {
    self._name = State(initialValue: name)
    self._description = State(initialValue: description)
    self._secret = State(initialValue: secret)
    self.validator = validator
    self.onSave = onSave
  }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          TextField(String(localized: "Persona name"), text: $name)
        } header: {
          Text(String(localized: "Name"))
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
          Text(String(localized: "Description"))
        } footer: {
          if let descriptionError {
            Text(descriptionError)
              .font(.caption)
              .foregroundStyle(Color.danger)
          }
        }

        Section {
          TextEditor(text: $secret)
            .frame(minHeight: 88)
        } header: {
          Text(String(localized: "Secret (optional)"))
        } footer: {
          if let secretError {
            Text(secretError)
              .font(.caption)
              .foregroundStyle(Color.danger)
          } else {
            Text(
              String(
                localized:
                  "Other agents never see this. Viewers can peek at it from the persona sheet."))
          }
        }
      }
      .navigationTitle(
        name.isEmpty
          ? String(localized: "New Persona")
          : String(localized: "Edit Persona")
      )
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(String(localized: "Cancel")) {
            dismiss()
          }
        }

        ToolbarItem(placement: .confirmationAction) {
          Button(String(localized: "Save")) {
            let findings = validator.validate(
              personaName: name,
              description: description,
              secret: secret
            )
            if findings.hasIssue {
              nameError = findings.name
              descriptionError = findings.description
              secretError = findings.secret
              return
            }
            onSave(name, description, secret)
            dismiss()
          }
          .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
      }
    }
  }
}
