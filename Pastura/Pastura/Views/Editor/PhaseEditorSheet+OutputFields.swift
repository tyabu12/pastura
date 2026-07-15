import SwiftUI

// Output-fields section: the field-name rows (each with an inline
// FieldDisplay description + a canonical-role pill) and the add-field
// control. Split out of `PhaseEditorSheet.swift` to keep that file under
// SwiftLint's `file_length` limit.

extension PhaseEditorSheet {
  var outputFieldsSection: some View {
    Section {
      ForEach(phase.outputFields.keys.sorted(), id: \.self) { key in
        VStack(alignment: .leading, spacing: 4) {
          HStack {
            Text(key)
              .font(.body.monospaced())
            fieldRolePill(for: key)
            Spacer()
            Text(phase.outputFields[key] ?? "string")
              .foregroundStyle(.secondary)
            Button(role: .destructive) {
              phase.outputFields.removeValue(forKey: key)
            } label: {
              Image(systemName: "minus.circle.fill")
            }
            .buttonStyle(.plain)
          }
          // Inline caption (FieldDisplay SSOT) so an author understands
          // seeded fields like `inner_thought` / `reason` in place.
          if let description = FieldDisplay.description(for: key) {
            Text(description)
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
      }

      HStack {
        TextField(String(localized: "Field name"), text: $newOutputFieldName)
          .font(.body.monospaced())
          .textInputAutocapitalization(.never)
        Button {
          let name = newOutputFieldName.trimmingCharacters(in: .whitespacesAndNewlines)
          guard !name.isEmpty else { return }
          phase.outputFields[name] = "string"
          newOutputFieldName = ""
        } label: {
          Image(systemName: "plus.circle.fill")
        }
        .disabled(newOutputFieldName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
    } header: {
      Text(String(localized: "Output Fields"))
    }
  }

  /// A capsule tag marking the row's canonical role — primary field (moss) or
  /// private-thought field (ink). Renders nothing for a custom / non-canonical
  /// key (e.g. narrate, whose primary and thought fields are both nil).
  @ViewBuilder
  private func fieldRolePill(for key: String) -> some View {
    if key == ScenarioConventions.primaryField(for: phase.type) {
      fieldPill(String(localized: "Primary"), tint: Color.mossDark)
    } else if key == ScenarioConventions.thoughtField(for: phase.type) {
      fieldPill(String(localized: "Thought"), tint: Color.inkSecondary)
    }
  }

  private func fieldPill(_ text: String, tint: Color) -> some View {
    Text(text)
      .font(.caption2.weight(.semibold))
      .padding(.horizontal, 7)
      .padding(.vertical, 2)
      .background(tint.opacity(0.16), in: Capsule())
      .foregroundStyle(tint)
  }
}
