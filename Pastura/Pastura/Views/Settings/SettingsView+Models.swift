import SwiftUI

// Device-only Models section for `SettingsView`, split into a sibling
// extension to keep `SettingsView.swift` under swiftlint's file_length /
// type_body_length caps. `modelsSection` and `handleCoverCancel` are
// `internal` (not `private`) because the host view's `body` (in the main
// file) references them; the remaining helpers stay `private` to this file.
// The `#if` mirrors the main file — this whole surface is omitted on the
// simulator (which runs `OllamaService`, not the on-device model lifecycle).
#if !targetEnvironment(simulator)
  extension SettingsView {
    // NOTE: device-only (omitted on the simulator), so the simulator
    // ui-tour cannot validate this card's layout — needs real-device QA.
    // ModelSettingsRow has no List-native behavior (delete is via its Menu
    // → confirmationDialog, not swipe), so the ScrollView move is layout-
    // only; it gets the horizontal inset the List cell used to provide.
    @ViewBuilder
    var modelsSection: some View {
      VStack(alignment: .leading, spacing: 7) {
        let catalog = modelManager.catalog
        PasturaSection(String(localized: "Models")) {
          VStack(spacing: 0) {
            ForEach(Array(catalog.enumerated()), id: \.element.id) { index, descriptor in
              if index > 0 { PasturaRowDivider() }
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
              // ModelSettingsRow only carries its own 4pt (Spacing.xxs)
              // vertical padding — fine inside a List cell (which added
              // its own insets) but cramped inside a PasturaCard. Add
              // ~10pt so the row breathes at ~14pt top/bottom, matching
              // the other card rows (infoRow / detailRow).
              .padding(.horizontal, 17)
              .padding(.vertical, 10)
            }
            orphanedFilesRows
          }
        }
        storageTotalLine
        modelsFooter
          .font(.caption)
          .foregroundStyle(Color.muted)
          .padding(.horizontal, PasturaCardMetrics.horizontalMargin + 6)
      }
      // `orphanedModelFiles()` is a filesystem read (not `@Observable`),
      // so seed the local `@State` snapshot on appear; delete refreshes it.
      .onAppear { orphanedFiles = modelManager.orphanedModelFiles() }
    }

    /// Unused-file rows appended below the catalog rows when superseded
    /// leftovers exist on disk. Separated from the catalog block by a
    /// divider; each carries the same horizontal/vertical inset as a
    /// `ModelSettingsRow`.
    @ViewBuilder
    private var orphanedFilesRows: some View {
      ForEach(Array(orphanedFiles.enumerated()), id: \.element.id) { _, file in
        PasturaRowDivider()
        OrphanedModelFileRow(
          file: file,
          onRequestDelete: { pendingOrphanDelete = file }
        )
        .padding(.horizontal, 17)
        .padding(.vertical, 10)
      }
    }

    /// Aggregate footprint line ("Downloaded models · X.X GB"). Hidden when
    /// nothing is on disk (total 0) so the empty state stays quiet. Reads
    /// observed `state` (reactive to download/delete) and the `@State`
    /// orphan snapshot, summing via the pure `totalModelStorageBytes(...)`
    /// so the figure always matches the rows shown above.
    @ViewBuilder
    private var storageTotalLine: some View {
      let readySizes: [Int64] = modelManager.catalog.compactMap { descriptor in
        if case .ready = modelManager.state[descriptor.id] { return descriptor.fileSize }
        return nil
      }
      let total = ModelManager.totalModelStorageBytes(
        readyDescriptorSizes: readySizes, orphanSizes: orphanedFiles.map(\.sizeBytes))
      if total > 0 {
        Text(
          String(
            format: String(localized: "Downloaded models · %@"),
            ModelSettingsRow.formattedFileSize(total))
        )
        .font(.caption)
        .foregroundStyle(Color.metaStrongL3)
        .padding(.horizontal, PasturaCardMetrics.horizontalMargin + 6)
      }
    }

    @ViewBuilder
    private var modelsFooter: some View {
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

    /// Whether any descriptor other than `id` is mid-download or has a
    /// pending cellular consent dialog. Used to disable competing
    /// Download menu items so a second tap during the dialog cannot
    /// overwrite `pendingCellularConsent` (#191 multi-row guard).
    private func isOtherDownloading(excluding id: ModelID) -> Bool {
      if let pending = modelManager.pendingCellularConsent, pending.id != id {
        return true
      }
      return modelManager.state.contains { entryID, entryState in
        guard entryID != id else { return false }
        if case .downloading = entryState { return true }
        return false
      }
    }

    /// Starts the download and decides whether to open the cover now or
    /// defer to the cellular consent flow.
    ///
    /// - **Wi-Fi / pre-consented**: `startDownload` flips state to
    ///   `.downloading` synchronously; the same-frame check opens the
    ///   cover immediately.
    /// - **Cellular without consent**: `startDownload` returns with
    ///   state still `.notDownloaded` and `pendingCellularConsent` set.
    ///   The cover is NOT opened here — the scene-level dialog and the
    ///   `.onChange(of: modelManager.state)` observer above coordinate
    ///   to open it after accept (or never, on decline).
    /// - **Sequential rejection**: `startDownload` is a no-op; neither
    ///   branch fires. The Download menu item is already disabled by
    ///   `otherDownloadInProgress`, so this is defense-in-depth.
    private func presentDownloadCover(for descriptor: ModelDescriptor) {
      modelManager.startDownload(descriptor: descriptor)
      if case .downloading = modelManager.state[descriptor.id] {
        coverDescriptor = descriptor
      } else if modelManager.pendingCellularConsent?.id == descriptor.id {
        pendingCoverDescriptor = descriptor
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
    func handleCoverCancel(descriptor: ModelDescriptor) {
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
        systemPromptSuffix: descriptor.systemPromptSuffix,
        assistantPrefix: descriptor.assistantPrefix
      )
      dependencies.regenerateLLMService(newService)
    }
  }
#endif
