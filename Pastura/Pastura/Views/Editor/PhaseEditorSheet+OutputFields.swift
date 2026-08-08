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
              .foregroundStyle(Color.inkSecondary)
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
              .foregroundStyle(Color.inkSecondary)
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
      fieldPill(String(localized: "Primary"), wash: Color.mossDark, label: Color.mossOnWash)
    } else if key == ScenarioConventions.thoughtField(for: phase.type) {
      fieldPill(String(localized: "Thought"), wash: Color.inkSecondary, label: Color.inkSecondary)
    }
  }

  /// Wash and label are separate parameters because the moss arm needs them to
  /// differ: the designed wash is `mossDark` at 0.16, but `mossDark` text on it
  /// measures ≈3.87:1 in light — under the 4.5:1 bar at `caption2` — so the
  /// label reads the `mossOnWash` role token instead, which brings it to
  /// ≈5.71:1 (#1327). The ink arm still passes one token twice — its light half
  /// clears the bar at ≈5.50:1, and its *dark*-side gap (≈4.41:1, the opposite
  /// asymmetry) is tracked separately in #1408.
  private func fieldPill(_ text: String, wash: Color, label: Color) -> some View {
    Text(text)
      .font(.caption2.weight(.semibold))
      .padding(.horizontal, 7)
      .padding(.vertical, 2)
      .background(wash.opacity(0.16), in: Capsule())
      .foregroundStyle(label)
  }
}
