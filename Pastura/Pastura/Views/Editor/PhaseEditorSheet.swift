import SwiftUI

/// Identifies which branch's sub-phase is currently being edited via a
/// nested `PhaseEditorSheet`. `.sheet(item:)` drives the presentation;
/// `onSave` on the nested sheet writes back to the right branch.
///
/// Module-internal (rather than file-private) because the conditional-
/// section UI lives in a sibling extension file and needs to construct
/// these contexts.
struct SubPhaseEditContext: Identifiable {
  let id = UUID()
  let branch: EditablePhase.Branch
  var phase: EditablePhase
}

// swiftlint:disable type_body_length
/// A modal sheet for creating or editing a single phase.
///
/// Displays a type picker at the top, then type-dependent fields below.
/// LLM phases show prompt and output fields; code phases show their
/// specific configuration (logic, source/target, template, etc.).
struct PhaseEditorSheet: View {
  @Environment(\.dismiss) private var dismiss
  @State var phase: EditablePhase
  let onSave: (EditablePhase) -> Void

  /// Phase types selectable in the picker. Call sites pass
  /// `PhaseType.allCases.filter { $0 != .conditional }` when opening the
  /// sheet for a nested sub-phase of a conditional — this is how the
  /// depth-1 rule is enforced at the UI layer. The validator and loader
  /// have the same check as a safety net.
  var availableTypes: [PhaseType] = PhaseType.allCases

  @State private var newOutputFieldName: String = ""
  @State private var newOptionText: String = ""
  // Internal (not private) so the sibling conditional-section extension
  // can present the nested editor from the "Add sub-phase" button.
  @State var editingSubPhase: SubPhaseEditContext?

  var body: some View {
    NavigationStack {
      Form {
        typeSection
        if phase.type.requiresLLM {
          promptSection
          outputFieldsSection
        }
        typeSpecificSection
      }
      .navigationTitle("Edit Phase")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") {
            onSave(phase)
            dismiss()
          }
        }
      }
      .sheet(item: $editingSubPhase) { context in
        // Nested editor — filter `.conditional` out of the picker so the
        // depth-1 rule is enforced at the UI layer (the validator + loader
        // also reject nested conditional as defense in depth).
        PhaseEditorSheet(
          phase: context.phase,
          onSave: { edited in
            writeBackSubPhase(edited, context: context)
          },
          availableTypes: PhaseType.allCases.filter { $0 != .conditional }
        )
        .deepLinkGated()
      }
    }
  }

  private func writeBackSubPhase(_ edited: EditablePhase, context: SubPhaseEditContext) {
    switch context.branch {
    case .then:
      if let index = phase.thenPhases.firstIndex(where: { $0.id == context.phase.id }) {
        phase.thenPhases[index] = edited
      }
    case .else:
      if let index = phase.elsePhases.firstIndex(where: { $0.id == context.phase.id }) {
        phase.elsePhases[index] = edited
      }
    }
  }

  // MARK: - Sections

  private var typeSection: some View {
    Section {
      Picker("Type", selection: $phase.type) {
        ForEach(availableTypes, id: \.self) { type in
          HStack {
            Text(type.rawValue)
            if type.requiresLLM {
              Text("LLM")
                .font(.caption2)
                .foregroundStyle(.purple)
            }
          }
          .tag(type)
        }
      }
    } footer: {
      Text(phaseTypeDescription)
        .font(.caption)
    }
  }

  private var promptSection: some View {
    Section {
      TextEditor(text: $phase.prompt)
        .frame(minHeight: 88)
        .font(.body.monospaced())
    } header: {
      Text("Prompt")
    } footer: {
      Text(
        "Variables: {scoreboard}, {conversation_log}, {opponent_name}, {assigned_topic}, {assigned_word}"
      )
    }
  }

  private var outputFieldsSection: some View {
    Section("Output Fields") {
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
        TextField("Field name", text: $newOutputFieldName)
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
    }
  }

  @ViewBuilder
  private var typeSpecificSection: some View {
    switch phase.type {
    case .choose:
      chooseSection
    case .vote:
      voteSection
    case .speakEach:
      speakEachSection
    case .scoreCalc:
      scoreCalcSection
    case .assign:
      assignSection
    case .summarize:
      summarizeSection
    case .speakAll, .eliminate:
      EmptyView()
    case .conditional:
      conditionalSection
    }
  }

  // `conditionalSection` and its `branchSection` helper live in
  // `PhaseEditorSheet+ConditionalSection.swift` (sibling extension file)
  // to keep this file under SwiftLint's `file_length` limit.

  // MARK: - Type-Specific Sections

  private var chooseSection: some View {
    Group {
      Section("Options") {
        ForEach(phase.options, id: \.self) { option in
          HStack {
            Text(option)
            Spacer()
            Button(role: .destructive) {
              phase.options.removeAll { $0 == option }
            } label: {
              Image(systemName: "minus.circle.fill")
            }
            .buttonStyle(.plain)
          }
        }

        HStack {
          TextField("New option", text: $newOptionText)
            .textInputAutocapitalization(.never)
          Button {
            let text = newOptionText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            phase.options.append(text)
            newOptionText = ""
          } label: {
            Image(systemName: "plus.circle.fill")
          }
          .disabled(newOptionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
      }

      Section("Pairing") {
        Picker("Strategy", selection: pairingBinding) {
          Text("None").tag(Optional<PairingStrategy>.none)
          Text("Round Robin").tag(PairingStrategy?.some(.roundRobin))
        }
      }
    }
  }

  private var voteSection: some View {
    Section {
      Toggle("Exclude Self", isOn: $phase.excludeSelf)
    }
  }

  private var speakEachSection: some View {
    Section("Sub-Rounds") {
      Stepper(
        "Rounds: \(phase.subRounds ?? 1)",
        value: subRoundsBinding,
        in: 1...10
      )
    }
  }

  private var scoreCalcSection: some View {
    Section("Scoring Logic") {
      Picker("Logic", selection: logicBinding) {
        Text("None").tag(Optional<ScoreCalcLogic>.none)
        ForEach(ScoreCalcLogic.allCases, id: \.self) { logic in
          Text(logic.rawValue).tag(ScoreCalcLogic?.some(logic))
        }
      }
    }
  }

  private var assignSection: some View {
    Section {
      TextField("Source key", text: $phase.source)
        .textInputAutocapitalization(.never)
      TextField("Target", text: $phase.target)
        .textInputAutocapitalization(.never)
    } header: {
      Text("Assignment")
    } footer: {
      Text("Source: top-level YAML key (e.g., topics, words). Target: all, random_one")
    }
  }

  private var summarizeSection: some View {
    Section {
      TextEditor(text: $phase.template)
        .frame(minHeight: 66)
        .font(.body.monospaced())
    } header: {
      Text("Template")
    } footer: {
      Text("Variables: {current_round}, {scoreboard}, {vote_results}")
    }
  }

  // MARK: - Bindings

  private var pairingBinding: Binding<PairingStrategy?> {
    Binding(
      get: { phase.pairing },
      set: { phase.pairing = $0 }
    )
  }

  private var logicBinding: Binding<ScoreCalcLogic?> {
    Binding(
      get: { phase.logic },
      set: { phase.logic = $0 }
    )
  }

  private var subRoundsBinding: Binding<Int> {
    Binding(
      get: { phase.subRounds ?? 1 },
      set: { phase.subRounds = $0 == 1 ? nil : $0 }
    )
  }

  // MARK: - Helpers

  private var phaseTypeDescription: String {
    switch phase.type {
    case .speakAll: return "All agents speak simultaneously"
    case .speakEach: return "Agents speak in turn (accumulating context)"
    case .vote: return "All agents vote for one agent"
    case .choose: return "Choose from predefined options"
    case .scoreCalc: return "Calculate scores (code, no LLM)"
    case .assign: return "Distribute info to agents (code)"
    case .eliminate: return "Remove most-voted agent (code)"
    case .summarize: return "Format round summary (code)"
    case .conditional: return "Branch on state (code, then/else sub-phases)"
    }
  }
}
// swiftlint:enable type_body_length
