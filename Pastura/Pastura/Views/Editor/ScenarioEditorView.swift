import SwiftUI

/// The main dual-mode scenario editor view.
///
/// Supports two modes toggled via a segmented picker:
/// - **Visual**: Form-based editing with sections for basic info, context,
///   personas, and phases (with drag-to-reorder).
/// - **YAML**: Raw text editor for direct YAML editing.
///
/// YAML is the source of truth. Visual edits are serialized to YAML on mode
/// switch and on save. Invalid YAML blocks the switch to visual mode.
struct ScenarioEditorView: View {
  @Bindable var viewModel: ScenarioEditorViewModel
  @Environment(\.dismiss) private var dismiss

  @State private var editingPersona: EditablePersona?
  @State private var editingPhase: EditablePhase?
  @State private var showNewPersonaSheet = false
  @State private var showNewPhaseSheet = false

  var body: some View {
    VStack(spacing: 0) {
      // Mode toggle
      Picker(String(localized: "Editor Mode"), selection: modeBinding) {
        Text(String(localized: "Visual")).tag(EditorMode.visual)
        Text(String(localized: "YAML")).tag(EditorMode.yaml)
      }
      .pickerStyle(.segmented)
      .padding()

      // Validation errors
      if !viewModel.validationErrors.isEmpty {
        validationBanner
      }

      // Content
      if viewModel.editorMode == .visual {
        visualEditor
      } else {
        yamlEditor
      }
    }
    .navigationTitle(
      viewModel.scenarioName.isEmpty ? String(localized: "New Scenario") : viewModel.scenarioName
    )
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .confirmationAction) {
        Button(String(localized: "Save")) {
          Task {
            if await viewModel.save() {
              dismiss()
            }
          }
        }
        .disabled(viewModel.isSaving)
        .accessibilityIdentifier("editor.saveButton")
      }
    }
    .sheet(isPresented: $showNewPersonaSheet) {
      PersonaEditorSheet(name: "", description: "") { name, description in
        viewModel.personas.append(EditablePersona(name: name, description: description))
        viewModel.agentCount = viewModel.personas.count
      }
      .deepLinkGated()
    }
    .sheet(item: $editingPersona) { persona in
      PersonaEditorSheet(
        name: persona.name,
        description: persona.description
      ) { newName, newDescription in
        if let idx = viewModel.personas.firstIndex(where: { $0.id == persona.id }) {
          viewModel.personas[idx].name = newName
          viewModel.personas[idx].description = newDescription
        }
      }
      .deepLinkGated()
    }
    .sheet(isPresented: $showNewPhaseSheet) {
      PhaseEditorSheet(phase: EditablePhase()) { phase in
        viewModel.phases.append(phase)
      }
      .deepLinkGated()
    }
    .sheet(item: $editingPhase) { phase in
      PhaseEditorSheet(phase: phase) { updated in
        if let idx = viewModel.phases.firstIndex(where: { $0.id == phase.id }) {
          viewModel.phases[idx] = updated
        }
      }
      .deepLinkGated()
    }
  }

  // MARK: - Visual Editor

  private var visualEditor: some View {
    Form {
      basicInfoSection
      contextSection
      personasSection
      phasesSection
    }
  }

  private var basicInfoSection: some View {
    Section(String(localized: "Basic Info")) {
      TextField(String(localized: "Scenario ID"), text: $viewModel.scenarioId)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .font(.body.monospaced())
      TextField(String(localized: "Name"), text: $viewModel.scenarioName)
        .accessibilityIdentifier("editor.titleField")
      TextField(
        String(localized: "Description"), text: $viewModel.scenarioDescription, axis: .vertical
      )
      .lineLimit(2...5)
      roundsControl
    }
  }

  /// Slider + stepper hybrid for discrete integer values (1...30).
  /// Matches iOS HIG for discrete tunable values where both precise
  /// increments (±) and quick scrubbing (drag) are desirable.
  private var roundsControl: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text(String(localized: "Rounds"))
        Spacer()
        Text("\(viewModel.rounds)")
          .monospacedDigit()
          .foregroundStyle(.secondary)
      }
      HStack {
        Button {
          viewModel.rounds = max(1, viewModel.rounds - 1)
        } label: {
          Image(systemName: "minus.circle.fill")
            .font(.title3)
        }
        .buttonStyle(.plain)
        .disabled(viewModel.rounds <= 1)

        Slider(value: roundsSliderBinding, in: 1...30, step: 1)

        Button {
          viewModel.rounds = min(30, viewModel.rounds + 1)
        } label: {
          Image(systemName: "plus.circle.fill")
            .font(.title3)
        }
        .buttonStyle(.plain)
        .disabled(viewModel.rounds >= 30)
      }
    }
  }

  private var roundsSliderBinding: Binding<Double> {
    Binding(
      get: { Double(viewModel.rounds) },
      set: { viewModel.rounds = Int($0) }
    )
  }

  private var contextSection: some View {
    Section(String(localized: "Context")) {
      TextEditor(text: $viewModel.context)
        .frame(minHeight: 88)
    }
  }

  private var personasSection: some View {
    Section {
      ForEach(viewModel.personas) { persona in
        Button {
          editingPersona = persona
        } label: {
          VStack(alignment: .leading, spacing: 4) {
            Text(persona.name.isEmpty ? "(unnamed)" : persona.name)
              .font(.body.bold())
              .foregroundStyle(.primary)
            if !persona.description.isEmpty {
              Text(persona.description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            }
          }
        }
        .buttonStyle(.plain)
      }
      .onDelete { indexSet in
        viewModel.personas.remove(atOffsets: indexSet)
        viewModel.agentCount = viewModel.personas.count
      }

      Button {
        showNewPersonaSheet = true
      } label: {
        Label(String(localized: "Add Persona"), systemImage: "plus.circle")
      }
    } header: {
      HStack {
        Text(String(localized: "Personas"))
        Spacer()
        Text("\(viewModel.personas.count) agents")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
  }

  private var phasesSection: some View {
    Section {
      ForEach(viewModel.phases) { phase in
        Button {
          editingPhase = phase
        } label: {
          PhaseBlockRow(phase: phase)
        }
        .buttonStyle(.plain)
      }
      .onDelete { indexSet in
        viewModel.phases.remove(atOffsets: indexSet)
      }
      .onMove { source, destination in
        viewModel.phases.move(fromOffsets: source, toOffset: destination)
      }

      Button {
        showNewPhaseSheet = true
      } label: {
        Label(String(localized: "Add Phase"), systemImage: "plus.circle")
      }
    } header: {
      HStack {
        Text(String(localized: "Phases"))
        Spacer()
        Text("\(viewModel.phases.count) steps")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
  }

  // MARK: - YAML Editor

  private var yamlEditor: some View {
    TextEditor(text: $viewModel.yamlText)
      .font(.body.monospaced())
      .autocorrectionDisabled()
      .textInputAutocapitalization(.never)
      .padding(.horizontal)
  }

  // MARK: - Validation Banner

  private var validationBanner: some View {
    VStack(alignment: .leading, spacing: 4) {
      ForEach(viewModel.validationErrors, id: \.self) { error in
        HStack(spacing: 6) {
          Image(systemName: "exclamationmark.triangle.fill")
            .foregroundStyle(Color.warning)
          Text(error)
            .font(.caption)
        }
      }
    }
    .padding(.horizontal)
    .padding(.vertical, 8)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.dangerSoft)
  }

  // MARK: - Mode Binding

  /// Custom binding that triggers serialization/parsing on mode switch.
  private var modeBinding: Binding<EditorMode> {
    Binding(
      get: { viewModel.editorMode },
      set: { newMode in
        if newMode == .yaml {
          viewModel.switchToYAMLMode()
        } else {
          viewModel.switchToVisualMode()
        }
      }
    )
  }
}
