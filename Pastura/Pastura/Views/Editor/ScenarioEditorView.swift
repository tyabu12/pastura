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

  @State private var editingPersonaIndex: Int?
  @State private var editingPhaseIndex: Int?
  @State private var showNewPersonaSheet = false
  @State private var showNewPhaseSheet = false

  var body: some View {
    VStack(spacing: 0) {
      // Mode toggle
      Picker("Editor Mode", selection: modeBinding) {
        Text("Visual").tag(EditorMode.visual)
        Text("YAML").tag(EditorMode.yaml)
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
    .navigationTitle(viewModel.scenarioName.isEmpty ? "New Scenario" : viewModel.scenarioName)
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .confirmationAction) {
        Button("Save") {
          Task {
            if await viewModel.save() {
              dismiss()
            }
          }
        }
        .disabled(viewModel.isSaving)
      }
    }
    .sheet(isPresented: $showNewPersonaSheet) {
      PersonaEditorSheet(name: "", description: "") { name, description in
        viewModel.personas.append(EditablePersona(name: name, description: description))
        viewModel.agentCount = viewModel.personas.count
      }
    }
    .sheet(item: $editingPersonaIndex) { index in
      let persona = viewModel.personas[index]
      PersonaEditorSheet(name: persona.name, description: persona.description) {
        name, description in
        viewModel.personas[index].name = name
        viewModel.personas[index].description = description
      }
    }
    .sheet(isPresented: $showNewPhaseSheet) {
      PhaseEditorSheet(phase: EditablePhase()) { phase in
        viewModel.phases.append(phase)
      }
    }
    .sheet(item: $editingPhaseIndex) { index in
      PhaseEditorSheet(phase: viewModel.phases[index]) { phase in
        viewModel.phases[index] = phase
      }
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
    Section("Basic Info") {
      TextField("Scenario ID", text: $viewModel.scenarioId)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .font(.body.monospaced())
      TextField("Name", text: $viewModel.scenarioName)
      TextField("Description", text: $viewModel.scenarioDescription)
      Stepper("Rounds: \(viewModel.rounds)", value: $viewModel.rounds, in: 1...30)
    }
  }

  private var contextSection: some View {
    Section("Context") {
      TextEditor(text: $viewModel.context)
        .frame(minHeight: 88)
    }
  }

  private var personasSection: some View {
    Section {
      ForEach(Array(viewModel.personas.enumerated()), id: \.element.id) { index, persona in
        Button {
          editingPersonaIndex = index
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
      }
      .onDelete { indexSet in
        viewModel.personas.remove(atOffsets: indexSet)
        viewModel.agentCount = viewModel.personas.count
      }

      Button {
        showNewPersonaSheet = true
      } label: {
        Label("Add Persona", systemImage: "plus.circle")
      }
    } header: {
      HStack {
        Text("Personas")
        Spacer()
        Text("\(viewModel.personas.count) agents")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
  }

  private var phasesSection: some View {
    Section {
      ForEach(Array(viewModel.phases.enumerated()), id: \.element.id) { index, phase in
        Button {
          editingPhaseIndex = index
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
        Label("Add Phase", systemImage: "plus.circle")
      }
    } header: {
      HStack {
        Text("Phases")
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
            .foregroundStyle(.yellow)
          Text(error)
            .font(.caption)
        }
      }
    }
    .padding(.horizontal)
    .padding(.vertical, 8)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.red.opacity(0.1))
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

// MARK: - Int Identifiable conformance for sheet binding

extension Int: @retroactive Identifiable {
  public var id: Int { self }
}
