import SwiftUI

/// A modal sheet for creating or editing a single persona's name and description.
struct PersonaEditorSheet: View {
  @Environment(\.dismiss) private var dismiss
  @State var name: String
  @State var description: String
  let onSave: (String, String) -> Void

  var body: some View {
    NavigationStack {
      Form {
        Section("Name") {
          TextField("Persona name", text: $name)
        }

        Section("Description") {
          TextEditor(text: $description)
            .frame(minHeight: 88)
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
            onSave(name, description)
            dismiss()
          }
          .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
      }
    }
  }
}
