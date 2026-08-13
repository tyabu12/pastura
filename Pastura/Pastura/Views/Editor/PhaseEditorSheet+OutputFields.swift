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
      fieldPill(String(localized: "Thought"), wash: Color.inkSecondary, label: Color.inkOnWash)
    }
  }

  /// Wash and label are separate parameters because **both** arms need them to
  /// differ — each label reads its family's `*OnWash` role token rather than the
  /// token filling the capsule under it.
  ///
  /// **Figures below are worst-case per appearance** — composited on
  /// `screenBackground` in light and `nightBubble` in dark, the convention
  /// `DesignTokensTests+MossOnWash` / `+InkOnWash` assert against. Earlier
  /// revisions of this comment measured on `bubbleBackground`, so the light
  /// numbers here read lower than the ones they replace (moss ≈5.73 → 5.509,
  /// ink ≈5.48 → 5.270). That is the ground changing, not the contrast.
  ///
  /// - **moss arm**: the designed wash is `mossDark` at 0.16, on which `mossDark`
  ///   text measures 3.737:1 — under the 4.5:1 bar at `caption2`. `mossOnWash`
  ///   brings it to 5.509:1 (#1327).
  /// - **ink arm**: the wash is `inkSecondary` at the same 0.16, where
  ///   `inkSecondary` text was the **opposite asymmetry** — 5.270:1 in light,
  ///   fine, but 4.413:1 in dark, the worst of the four self-washes and the only
  ///   one strictly under the bar. `inkOnWash` brings dark to 4.991:1 and leaves
  ///   light untouched, its two halves being byte-identical (#1408).
  private func fieldPill(_ text: String, wash: Color, label: Color) -> some View {
    Text(text)
      .font(.caption2.weight(.semibold))
      .padding(.horizontal, 7)
      .padding(.vertical, 2)
      .background(wash.opacity(0.16), in: Capsule())
      .foregroundStyle(label)
  }
}
