import SwiftUI
import UniformTypeIdentifiers

/// Screen for importing YAML scenarios via paste, file picker, or editing.
struct ImportView: View {
  var editingId: String?

  @Environment(AppDependencies.self) private var dependencies
  @Environment(\.dismiss) private var dismiss
  @State private var viewModel: ImportViewModel?
  @State private var showFilePicker = false
  @State private var showPromptCopied = false

  var body: some View {
    Group {
      if let viewModel {
        importContent(viewModel: viewModel)
      } else {
        ProgressView()
      }
    }
    .navigationTitle(
      editingId != nil
        ? String(localized: "Edit Scenario") : String(localized: "Import Scenario")
    )
    .navigationBarTitleDisplayMode(.inline)
    .task {
      // Defer assignment until loadForEditing completes so the TextEditor
      // never renders the default empty `yamlText` between VM creation and
      // the DB read landing. Mirrors the `ScenarioEditorHost` pattern in
      // HomeView.swift. Guard prevents re-creation under `.task` re-fire
      // (iPad multitasking, scenePhase transitions).
      guard viewModel == nil else { return }
      let newViewModel = ImportViewModel(repository: dependencies.scenarioRepository)
      if let editingId {
        await newViewModel.loadForEditing(scenarioId: editingId)
      }
      viewModel = newViewModel
    }
  }

  private func importContent(viewModel: ImportViewModel) -> some View {
    @Bindable var bindable = viewModel
    return VStack(spacing: 0) {
      TextEditor(text: $bindable.yamlText)
        .font(.system(.body, design: .monospaced))
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)
        .padding(.horizontal, 4)
        .onChange(of: bindable.yamlText) {
          viewModel.validate()
        }
      Divider()
      validationFeedback(viewModel: viewModel)
      Divider()
      importActionBar(viewModel: viewModel)
    }
    .fileImporter(
      isPresented: $showFilePicker,
      allowedContentTypes: [.yaml, .plainText]
    ) { result in
      if case .success(let url) = result {
        loadFile(url: url, viewModel: viewModel)
      }
    }
    .overlay(alignment: .top) {
      promptCopiedToast
    }
    .animation(.default, value: showPromptCopied)
  }

  @ViewBuilder
  private func validationFeedback(viewModel: ImportViewModel) -> some View {
    if !viewModel.validationErrors.isEmpty {
      VStack(alignment: .leading, spacing: 4) {
        ForEach(viewModel.validationErrors, id: \.self) { error in
          Label(error, systemImage: "xmark.circle.fill")
            .font(.caption)
            .foregroundStyle(Color.dangerInk)
        }
      }
      .padding(.horizontal)
      .padding(.vertical, 8)
    } else if viewModel.isValid {
      Label(String(localized: "Valid scenario"), systemImage: "checkmark.circle.fill")
        .font(.caption)
        .foregroundStyle(Color.successInk)
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
  }

  private func importActionBar(viewModel: ImportViewModel) -> some View {
    HStack(spacing: 12) {
      Button {
        showFilePicker = true
      } label: {
        Label(String(localized: "File"), systemImage: "doc")
          .font(.subheadline)
      }

      Button {
        UIPasteboard.general.string = ImportViewModel.scenarioGenerationPrompt
        showPromptCopied = true
      } label: {
        Label(String(localized: "Copy Gen Prompt"), systemImage: "doc.on.doc")
          .font(.subheadline)
      }

      Spacer()

      Button {
        Task {
          if await viewModel.save() {
            dismiss()
          }
        }
      } label: {
        Text(String(localized: "Import"))
          .fontWeight(.semibold)
      }
      .buttonStyle(.borderedProminent)
      .disabled(!viewModel.isValid || viewModel.isSaving)
    }
    .padding()
  }

  @ViewBuilder
  private var promptCopiedToast: some View {
    if showPromptCopied {
      Text(String(localized: "Prompt copied!"))
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .transition(.move(edge: .top).combined(with: .opacity))
        .task {
          try? await Task.sleep(for: .seconds(2))
          showPromptCopied = false
        }
    }
  }

  private func loadFile(url: URL, viewModel: ImportViewModel) {
    guard url.startAccessingSecurityScopedResource() else { return }
    defer { url.stopAccessingSecurityScopedResource() }

    if let content = try? String(contentsOf: url, encoding: .utf8) {
      viewModel.yamlText = content
      viewModel.validate()
    }
  }
}
