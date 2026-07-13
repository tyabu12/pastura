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
    case .scoreCalc, .assign, .eliminate, .summarize, .conditional, .eventInject,
      .relationshipUpdate, .narrate:
      return nil
    }
  }

  /// The phase-aware `{token}` hint listed under an LLM phase's prompt editor
  /// (#920 B, ADR-024 D4). Reads the linter-owned ``PlaceholderAvailability``
  /// map instead of a static hardcoded list: the tokens this phase's handler
  /// injects (``PlaceholderAvailability/supplied(for:chooseRoundRobin:)`` — so a
  /// round-robin `choose` gains `{opponent_name}` and the whisper channel, and
  /// `vote` gains `{candidates}`) unioned with the cross-phase state tokens any
  /// prompt may read (``PlaceholderAvailability/crossPhaseStateReadable``),
  /// sorted and brace-wrapped. `static` so it is unit-testable without rendering
  /// the sheet.
  static func promptVariableHint(for phase: EditablePhase) -> String {
    PlaceholderAvailability
      .supplied(for: phase.type, chooseRoundRobin: phase.pairing == .roundRobin)
      .union(PlaceholderAvailability.crossPhaseStateReadable)
      .sorted()
      .map { "{\($0)}" }
      .joined(separator: ", ")
  }
}
