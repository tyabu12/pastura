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

  /// Content validator for the Save-tap inline check (#261). Default-
  /// constructed in production; tests inject a deterministic instance.
  /// Forwarded to the nested sub-phase sheet so depth-1 nested edits
  /// share the same validator and remain test-deterministic.
  var validator: ScenarioContentValidator = ScenarioContentValidator()

  @State private var newOutputFieldName: String = ""
  @State private var newOptionText: String = ""
  // Internal (not private) so the sibling conditional-section extension
  // can present the nested editor from the "Add sub-phase" button.
  @State var editingSubPhase: SubPhaseEditContext?

  // Per-field inline error state populated on Save tap when the
  // validator surfaces a violation. Each property maps 1:1 to the
  // corresponding visible Section footer below the field.
  // `conditionError` is non-private so the sibling conditional-section
  // extension can render it inside `conditionalSection`.
  @State private var promptError: String?
  @State private var templateError: String?
  @State var conditionError: String?

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
      .navigationTitle(String(localized: "Edit Phase"))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(String(localized: "Cancel")) { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button(String(localized: "Save")) {
            if !runInlineValidation() {
              return
            }
            onSave(phase)
            dismiss()
          }
        }
      }
      .sheet(item: $editingSubPhase) { context in
        // Nested editor — filter `.conditional` out of the picker so the
        // depth-1 rule is enforced at the UI layer (the validator + loader
        // also reject nested conditional as defense in depth). The
        // validator is forwarded so nested Save runs against the same
        // blocklist instance the outer sheet uses (#261).
        PhaseEditorSheet(
          phase: context.phase,
          onSave: { edited in
            writeBackSubPhase(edited, context: context)
          },
          availableTypes: PhaseType.allCases.filter { $0 != .conditional },
          validator: validator
        )
        .deepLinkGated()
      }
    }
  }

  /// Runs `ScenarioContentValidator` on the fields the active phase type
  /// exposes in the UI, then mirrors per-field findings into `@State` for
  /// inline error rendering. Returns `true` if Save should proceed.
  ///
  /// Visible-fields-only by design: residual text in fields that the
  /// active type's UI does not expose passes through here cleanly, then
  /// gets caught by `ScenarioContentValidator.validate(_ scenario:)` on
  /// the editor's outer Save (defense-in-depth, ADR-005 §4).
  private func runInlineValidation() -> Bool {
    let prompt = phase.type.requiresLLM ? phase.prompt : ""
    let template = phase.type == .summarize ? phase.template : ""
    let condition = phase.type == .conditional ? phase.condition : ""
    let findings = validator.validate(
      phasePrompt: prompt,
      template: template,
      condition: condition
    )
    promptError = findings.prompt
    templateError = findings.template
    conditionError = findings.condition
    return !findings.hasIssue
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
      Picker(String(localized: "Type"), selection: $phase.type) {
        ForEach(availableTypes, id: \.self) { type in
          HStack {
            Text(type.rawValue)
            if type.requiresLLM {
              // `info` here is a quiet category badge for LLM-required phase types,
              // not a notification — see design-system §2.6 for the alert-family scope.
              Text(String(localized: "LLM"))
                .font(.caption2)
                .foregroundStyle(Color.info)
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
      Text(String(localized: "Prompt"))
    } footer: {
      VStack(alignment: .leading, spacing: 4) {
        Text(
          String(
            localized:
              "Variables: {scoreboard}, {conversation_log}, {opponent_name}, {assigned_topic}, {assigned_word}, {current_event}"
          )
        )
        .font(.caption)
        if let promptError {
          Text(promptError)
            .font(.caption)
            .foregroundStyle(Color.danger)
        }
      }
    }
  }

  private var outputFieldsSection: some View {
    Section(String(localized: "Output Fields")) {
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
    case .eventInject:
      eventInjectSection
    }
  }

  // `conditionalSection` and its `branchSection` helper live in
  // `PhaseEditorSheet+ConditionalSection.swift`. `eventInjectSection`
  // and its `probabilityBinding` helper live in
  // `PhaseEditorSheet+EventInjectSection.swift`. Both sibling
  // extension files keep this file under SwiftLint's `file_length` limit.

  // MARK: - Type-Specific Sections

  private var chooseSection: some View {
    Group {
      Section(String(localized: "Options")) {
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
          TextField(String(localized: "New option"), text: $newOptionText)
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

      Section(String(localized: "Pairing")) {
        Picker(String(localized: "Strategy"), selection: pairingBinding) {
          Text(String(localized: "None")).tag(Optional<PairingStrategy>.none)
          Text(String(localized: "Round Robin")).tag(PairingStrategy?.some(.roundRobin))
        }
      }
    }
  }

  private var voteSection: some View {
    Section {
      Toggle(String(localized: "Exclude Self"), isOn: $phase.excludeSelf)
    }
  }

  private var speakEachSection: some View {
    Section(String(localized: "Sub-Rounds")) {
      Stepper(
        "Rounds: \(phase.subRounds ?? 1)",
        value: subRoundsBinding,
        in: 1...10
      )
    }
  }

  private var scoreCalcSection: some View {
    Section(String(localized: "Scoring Logic")) {
      Picker(String(localized: "Logic"), selection: logicBinding) {
        Text(String(localized: "None")).tag(Optional<ScoreCalcLogic>.none)
        ForEach(ScoreCalcLogic.allCases, id: \.self) { logic in
          Text(logic.rawValue).tag(ScoreCalcLogic?.some(logic))
        }
      }
    }
  }

  private var assignSection: some View {
    Section {
      TextField(String(localized: "Source key"), text: $phase.source)
        .textInputAutocapitalization(.never)
      TextField(String(localized: "Target"), text: $phase.target)
        .textInputAutocapitalization(.never)
    } header: {
      Text(String(localized: "Assignment"))
    } footer: {
      Text(
        String(
          localized: "Source: top-level YAML key (e.g., topics, words). Target: all, random_one"))
    }
  }

  private var summarizeSection: some View {
    Section {
      TextEditor(text: $phase.template)
        .frame(minHeight: 66)
        .font(.body.monospaced())
    } header: {
      Text(String(localized: "Template"))
    } footer: {
      VStack(alignment: .leading, spacing: 4) {
        Text(String(localized: "Variables: {current_round}, {scoreboard}, {vote_results}"))
          .font(.caption)
        if let templateError {
          Text(templateError)
            .font(.caption)
            .foregroundStyle(Color.danger)
        }
      }
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

  // Returned as `String` (not `LocalizedStringKey`) because the consumer is
  // `Text(phaseTypeDescription)` which uses the verbatim-String overload —
  // wrap each branch with `String(localized:)` so the value goes through
  // Bundle resolution before display.
  private var phaseTypeDescription: String {
    switch phase.type {
    case .speakAll: return String(localized: "All agents speak simultaneously")
    case .speakEach: return String(localized: "Agents speak in turn (accumulating context)")
    case .vote: return String(localized: "All agents vote for one agent")
    case .choose: return String(localized: "Choose from predefined options")
    case .scoreCalc: return String(localized: "Calculate scores (code, no LLM)")
    case .assign: return String(localized: "Distribute info to agents (code)")
    case .eliminate: return String(localized: "Remove most-voted agent (code)")
    case .summarize: return String(localized: "Format round summary (code)")
    case .conditional: return String(localized: "Branch on state (code, then/else sub-phases)")
    case .eventInject:
      return String(localized: "Inject a random event from extraData (code, no LLM)")
    }
  }
}
// swiftlint:enable type_body_length
