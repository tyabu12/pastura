import SwiftUI

/// Settings screen hosting static informational copy for the Pastura app.
///
/// Pushed onto the root `NavigationStack` via `Route.settings`. Per
/// `.claude/rules/navigation.md`, this view must NOT add
/// `navigationDestination(item:|isPresented:)` modifiers.
///
/// ## Models section (device only)
///
/// On non-simulator builds, shows the catalog with per-descriptor
/// state, Download / Cancel / Use-this-model / Delete actions, and a
/// footer that adapts to the inference-activity registry. The section
/// is omitted on the simulator — that build uses `OllamaService` and
/// the on-device model lifecycle doesn't apply.
///
/// Active-model switch reconstructs the `LlamaCppService` through
/// `AppDependencies.regenerateLLMService(_:)`; it's gated on
/// `simulationActivityRegistry.isActive == false` at the UI layer so
/// the service is never torn down mid-inference.
struct SettingsView: View {
  #if !targetEnvironment(simulator)
    @Environment(ModelManager.self) private var modelManager
    @Environment(AppDependencies.self) private var dependencies
    @State private var pendingDelete: ModelDescriptor?
  #endif

  var body: some View {
    List {
      #if !targetEnvironment(simulator)
        modelsSection
      #endif
      Section {
        contentReportingBody
      } header: {
        Text("Content reporting")
      }
    }
    .navigationTitle("Settings")
    .navigationBarTitleDisplayMode(.inline)
    #if !targetEnvironment(simulator)
      .confirmationDialog(
        // Inline-interpolated title so VoiceOver reads the specific model name
        // rather than a generic "Delete this model?" for every row.
        Text(
          String(
            localized: "Delete \(pendingDelete?.displayName ?? "this model")?"
          )),
        isPresented: Binding(
          get: { pendingDelete != nil },
          set: { if !$0 { pendingDelete = nil } }),
        titleVisibility: .visible,
        presenting: pendingDelete
      ) { descriptor in
        Button(String(localized: "Delete"), role: .destructive) {
          // `try?` is deliberate — the UI pre-empts every `deleteModel`
          // reject path (active-model / not-ready / unknown-id), so a
          // throw here means a genuine race we can't meaningfully
          // recover from inside the confirmation callback. The state
          // will simply stay `.ready` and the user can try again.
          try? modelManager.deleteModel(id: descriptor.id)
          pendingDelete = nil
        }
        Button(String(localized: "Cancel"), role: .cancel) {
          pendingDelete = nil
        }
      } message: { descriptor in
        Text(
          String(
            localized:
              "Re-downloading \(ModelSettingsRow.formattedFileSize(descriptor.fileSize)) takes a few minutes."
          ))
      }
    #endif
  }

  #if !targetEnvironment(simulator)
    @ViewBuilder
    private var modelsSection: some View {
      Section {
        ForEach(modelManager.catalog, id: \.id) { descriptor in
          ModelSettingsRow(
            descriptor: descriptor,
            state: modelManager.state[descriptor.id] ?? .checking,
            isActive: descriptor.id == modelManager.activeModelID,
            otherDownloadInProgress: isOtherDownloading(excluding: descriptor.id),
            isSwitchLocked: dependencies.simulationActivityRegistry.isActive,
            onDownload: { modelManager.startDownload(descriptor: descriptor) },
            onCancel: { modelManager.cancelDownload(descriptor: descriptor) },
            onSwitchActive: { switchActive(to: descriptor) },
            onRequestDelete: { pendingDelete = descriptor }
          )
        }
      } header: {
        Text("Models")
      } footer: {
        if dependencies.simulationActivityRegistry.isActive {
          Text(
            String(
              localized:
                "Finish the current simulation before switching models. Downloads and deletes of other models remain available."
            ))
        } else {
          Text(
            String(
              localized:
                "You can keep multiple models on this device. Only the active one is loaded in memory."
            ))
        }
      }
    }

    private func isOtherDownloading(excluding id: ModelID) -> Bool {
      modelManager.state.contains { entryID, entryState in
        guard entryID != id else { return false }
        if case .downloading = entryState { return true }
        return false
      }
    }

    /// Persists the new active id and rebuilds the `LlamaCppService`.
    /// Only called from a `.ready` row (Menu action is hidden otherwise),
    /// so `modelFileURL` is guaranteed to point at an on-disk file.
    private func switchActive(to descriptor: ModelDescriptor) {
      modelManager.setActiveModel(descriptor.id)
      let modelPath = modelManager.modelFileURL(for: descriptor).path
      let newService = LlamaCppService(
        modelPath: modelPath,
        stopSequence: descriptor.stopSequence,
        modelIdentifier: descriptor.displayName,
        systemPromptSuffix: descriptor.systemPromptSuffix
      )
      dependencies.regenerateLLMService(newService)
    }
  #endif

  private var contentReportingBody: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(
        "Reports about scenarios on the Share Board are reviewed by "
          + "the Pastura maintainer (github.com/tyabu12)."
      )
      .font(.body)

      Text(
        "To report a scenario: open it from the Share Board, tap "
          + "the More menu, and choose Report this scenario."
      )
      .font(.body)
      .foregroundStyle(.secondary)

      Text("You'll receive a confirmation email when your report is received.")
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
    .padding(.vertical, 4)
  }
}
