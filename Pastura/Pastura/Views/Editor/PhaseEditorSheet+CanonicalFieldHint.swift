import SwiftUI

// Output-fields section + per-phase canonical primary-field hint.
// The hint surfaces the convention enforced by
// `ScenarioValidator.validateForCommit` so curators discover the
// canonical field name at compose time, not at Save. Split out from
// `PhaseEditorSheet.swift` to keep that file under SwiftLint's
// `file_length` limit.

extension PhaseEditorSheet {
  var outputFieldsSection: some View {
    Section {
      ForEach(phase.outputFields.keys.sorted(), id: \.self) { key in
        HStack {
          Text(key)
            .font(.body.monospaced())
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
    } footer: {
      canonicalFieldHint.map(Text.init)
    }
  }

  var canonicalFieldHint: String? {
    switch phase.type {
    case .speakAll, .speakEach:
      return String(
        localized:
          "Use `statement` for the main spoken text. UI display and conversation log key on this field."
      )
    case .choose:
      return String(
        localized:
          "Use `action` for the chosen value. It is restricted to the phase options."
      )
    case .vote:
      return String(localized: "Use `vote` for the target name.")
    case .reflect:
      return String(
        localized:
          "Use `note` for the agent's private memo. This is the reflect phase's only output field."
      )
    case .whisper:
      return String(
        localized:
          "Use `statement` for the whispered text. Whispers stay private to the pair and never enter the public conversation log."
      )
    case .scoreCalc, .assign, .eliminate, .summarize, .conditional, .eventInject:
      return nil
    }
  }
}
