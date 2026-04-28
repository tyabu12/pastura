import SwiftUI
import os

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
  @Environment(\.openURL) private var openURL

  #if !targetEnvironment(simulator)
    @Environment(ModelManager.self) private var modelManager
    @Environment(AppDependencies.self) private var dependencies
    @State private var pendingDelete: ModelDescriptor?
    /// Descriptor whose Download action should present the DL demo cover.
    /// Bound to `.fullScreenCover(item:)` — `Identifiable` is supplied by
    /// the conformance on `ModelDescriptor`.
    @State private var coverDescriptor: ModelDescriptor?
    // Surfaces `.cannotDeleteActive` / `.notReadyForDelete` / `.unknownModel`
    // that slip past the UI guard — a genuine UI-state-vs-ModelManager race.
    // User flow stays silent (row stays `.ready`), but Console.app shows the
    // race for field debugging.
    private static let logger = Logger(subsystem: "com.tyabu12.Pastura", category: "SettingsModels")
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
      Section {
        Button {
          guard let url = URL(string: "https://tyabu12.github.io/pastura/legal/privacy-policy/")
          else { return }
          openURL(url)
        } label: {
          HStack {
            Text(String(localized: "Privacy Policy"))
              .foregroundStyle(.primary)
            Spacer()
            Image(systemName: "arrow.up.right.square")
              .foregroundStyle(.secondary)
          }
        }
        .accessibilityIdentifier("settings.privacyPolicyLink")
      } header: {
        Text("About")
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
          // The UI pre-empts every `deleteModel` reject path (active-model /
          // not-ready / unknown-id), so a throw here means a genuine
          // UI-state-vs-ModelManager race. Log for field debugging; the
          // user flow stays silent (row stays `.ready`, they can try again).
          do {
            try modelManager.deleteModel(id: descriptor.id)
          } catch {
            Self.logger.error(
              "deleteModel unexpectedly threw for \(descriptor.id, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
          }
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
      .fullScreenCover(item: $coverDescriptor) { descriptor in
        // `.deepLinkGated()` makes the cover behave like a sheet for
        // deep-link queueing — a `pastura://` URL arriving while a
        // model is downloading toasts instead of pushing under the
        // cover. Settings is a long-lived modal context here.
        DemoReplayHostView(
          modelManager: modelManager,
          descriptor: descriptor,
          showsCompleteOverlay: false,
          onComplete: { coverDescriptor = nil },
          onCancel: { handleCoverCancel(descriptor: descriptor) }
        )
        .deepLinkGated()
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
            onDownload: { presentDownloadCover(for: descriptor) },
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

    /// Starts the download and, only if the state actually flipped to
    /// `.downloading`, presents the demo cover. The state mutation in
    /// `startDownload` is synchronous (sets `.downloading(progress: 0)`
    /// before returning), so the same-frame check is safe and avoids
    /// presenting an empty cover when the sequential-download policy
    /// silently rejects the call. The Download menu item is already
    /// disabled by `otherDownloadInProgress`, so the rejection branch
    /// here is defense-in-depth.
    private func presentDownloadCover(for descriptor: ModelDescriptor) {
      modelManager.startDownload(descriptor: descriptor)
      if case .downloading = modelManager.state[descriptor.id] {
        coverDescriptor = descriptor
      }
    }

    /// Dismisses the cover immediately, then runs the destructive cancel
    /// in a detached task. Awaiting before dismissal would freeze the
    /// cover while files are removed; the user has already confirmed,
    /// so the destructive flow can finish in the background. Subsequent
    /// state observations rebuild the row as `.notDownloaded` once the
    /// task lands.
    ///
    /// Re-tap-during-cleanup race is benign: while the in-flight
    /// download Task is still alive the row's Menu shows Cancel (not
    /// Download), so the user cannot start a second download until
    /// `performDownload`'s catch handler has set state to
    /// `.notDownloaded`. By the time the row's menu flips to Download,
    /// the only remaining work in `cancelDownloadAndDelete` is the two
    /// `removeItem` calls — a microsecond window not worth guarding.
    private func handleCoverCancel(descriptor: ModelDescriptor) {
      coverDescriptor = nil
      Task { await modelManager.cancelDownloadAndDelete(descriptor: descriptor) }
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
