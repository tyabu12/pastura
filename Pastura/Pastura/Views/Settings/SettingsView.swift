import SwiftUI
import os

/// Settings screen hosting the Models section (device only) and a
/// Legal section with Privacy Policy + content-report sheet.
///
/// Pushed onto the root `NavigationStack` via `Route.settings`. Per
/// `.claude/rules/navigation.md`, this view must NOT add
/// `navigationDestination(item:|isPresented:)` modifiers — sheets
/// (`.sheet(isPresented:)`) and `.fullScreenCover(item:)` are exempt
/// from that rule and are used here for the report sheet and download
/// cover respectively.
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
///
/// ## Legal section
///
/// Two rows: an external Privacy Policy link (opens Safari via
/// `Environment(\.openURL)`) and a "Send a content report" Button
/// that presents `ReportScenarioSheet(scenario: nil)` via
/// `.sheet(isPresented:)`. The sheet carries `.deepLinkGated()` for
/// symmetry with `GalleryScenarioDetailView`'s callsite — see
/// navigation.md QA scenario 9. ADR-005 §6.6 substantive commitment
/// ("Settings surface exposes report-mechanism copy per §6.4") is
/// preserved by `ReportScenarioSheet`'s introCopy.
struct SettingsView: View {
  @Environment(\.openURL) private var openURL

  /// Bound to `.sheet(isPresented:)` for the "Send a content report"
  /// row inside the Legal section. The sheet reuses
  /// `ReportScenarioSheet` with `scenario: nil` (Settings has no
  /// specific scenario context) — see ADR-005 §6.7 dual-use precedent.
  @State private var isReportSheetPresented: Bool = false

  /// Bound to `.sheet(isPresented:)` for the "Licenses"
  /// row inside the Legal section.
  @State private var isLicensesSheetPresented: Bool = false

  #if !targetEnvironment(simulator)
    @Environment(ModelManager.self) private var modelManager
    @Environment(AppDependencies.self) private var dependencies
    @State private var pendingDelete: ModelDescriptor?
    /// Descriptor whose Download action should present the DL demo cover.
    /// Bound to `.fullScreenCover(item:)` — `Identifiable` is supplied by
    /// the conformance on `ModelDescriptor`.
    @State private var coverDescriptor: ModelDescriptor?
    /// Descriptor that the user tapped Download on while the cellular
    /// gate was about to fire (#191). Holds the descriptor across the
    /// scene-level consent dialog: on accept, the state observer below
    /// flips `coverDescriptor` to this value once `ModelManager` has
    /// transitioned to `.downloading`. On decline, `pendingCellularConsent`
    /// reverts to nil and the matching observer clears this so the
    /// cover never opens.
    @State private var pendingCoverDescriptor: ModelDescriptor?
    // Surfaces `.cannotDeleteActive` / `.notReadyForDelete` / `.unknownModel`
    // that slip past the UI guard — a genuine UI-state-vs-ModelManager race.
    // User flow stays silent (row stays `.ready`), but Console.app shows the
    // race for field debugging.
    private static let logger = Logger(subsystem: "app.pastura.Pastura", category: "SettingsModels")
  #endif

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: PasturaCardMetrics.interCardSpacing) {
        #if !targetEnvironment(simulator)
          modelsSection
        #endif
        // Theme D (tappable-row green language) is intentionally left as-is:
        // these stay `Button`s with `.foregroundStyle(.primary)`, which the
        // Button context resolves to the moss accent. Only the container
        // (card) and field tone change here.
        PasturaSection(String(localized: "Legal")) {
          VStack(spacing: 0) {
            Button {
              guard let url = LocalizedPublicPages.privacyPolicy() else { return }
              openURL(url)
            } label: {
              HStack {
                Text(String(localized: "Privacy Policy"))
                  .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "arrow.up.right.square")
                  .foregroundStyle(.secondary)
              }
              .padding(.horizontal, 17)
              .padding(.vertical, 15)
              .contentShape(Rectangle())
            }
            .accessibilityIdentifier("settings.privacyPolicyLink")

            PasturaRowDivider()
            Button {
              isReportSheetPresented = true
            } label: {
              HStack {
                Text(String(localized: "Send a content report"))
                  .foregroundStyle(.primary)
                Spacer()
              }
              .padding(.horizontal, 17)
              .padding(.vertical, 15)
              .contentShape(Rectangle())
            }
            .accessibilityIdentifier("settings.sendContentReportButton")

            PasturaRowDivider()
            Button {
              isLicensesSheetPresented = true
            } label: {
              HStack {
                Text(String(localized: "Licenses"))
                  .foregroundStyle(.primary)
                Spacer()
              }
              .padding(.horizontal, 17)
              .padding(.vertical, 15)
              .contentShape(Rectangle())
            }
            .accessibilityIdentifier("settings.licensesLink")
          }
        }
      }
      .padding(.vertical, PasturaCardMetrics.interCardSpacing)
    }
    .background(Color.screenBackground.ignoresSafeArea())
    .navigationTitle(String(localized: "Settings"))
    .navigationBarTitleDisplayMode(.inline)
    .navigationBarBackButtonHidden(true)
    .preservesPasturaSwipeBackGesture()
    .toolbar {
      ToolbarItem(placement: .topBarLeading) {
        PasturaBackButton()
      }
      .hidingPasturaSharedBackground()
    }
    // `.deepLinkGated()` mirrors the existing report sheet at
    // GalleryScenarioDetailView's call site — a `pastura://` URL
    // arriving while the user is mid-report queues until the sheet
    // dismisses, rather than pushing a gallery detail under it (see
    // navigation.md QA scenario 9).
    .sheet(isPresented: $isReportSheetPresented) {
      ReportScenarioSheet(scenario: nil)
        .deepLinkGated()
    }
    .sheet(isPresented: $isLicensesSheetPresented) {
      LicensesSheet()
        .deepLinkGated()
    }
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
        ModelDownloadHostView(
          modelManager: modelManager,
          descriptor: descriptor,
          showsCompleteOverlay: false,
          onComplete: { coverDescriptor = nil },
          onCancel: { handleCoverCancel(descriptor: descriptor) }
        )
        .deepLinkGated()
      }
      // Cellular gate state observer (#191): user tapped Download while
      // cellular consent was required, so `presentDownloadCover` queued
      // the descriptor in `pendingCoverDescriptor` instead of opening
      // the cover. When the user accepts the scene-level dialog,
      // `acceptCellularConsent` re-fires `startDownload`, state flips
      // to `.downloading`, and we open the cover here.
      .onChange(of: modelManager.state) { _, newState in
        guard let pending = pendingCoverDescriptor else { return }
        if case .downloading = newState[pending.id] {
          coverDescriptor = pending
          pendingCoverDescriptor = nil
        }
      }
      // Decline detection: if `pendingCellularConsent` clears without
      // the state transitioning to `.downloading`, the user declined
      // (or tapped outside the dialog). Clear the queued cover so a
      // later same-frame state change doesn't accidentally open it.
      .onChange(of: modelManager.pendingCellularConsent) { old, new in
        guard old != nil, new == nil, let pending = pendingCoverDescriptor else { return }
        if case .downloading = modelManager.state[pending.id] { return }
        pendingCoverDescriptor = nil
      }
    #endif
  }

  #if !targetEnvironment(simulator)
    // NOTE: device-only (omitted on the simulator), so the simulator
    // ui-tour cannot validate this card's layout — needs real-device QA.
    // ModelSettingsRow has no List-native behavior (delete is via its Menu
    // → confirmationDialog, not swipe), so the ScrollView move is layout-
    // only; it gets the horizontal inset the List cell used to provide.
    @ViewBuilder
    private var modelsSection: some View {
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
              .padding(.horizontal, 17)
            }
          }
        }
        modelsFooter
          .font(.caption)
          .foregroundStyle(Color.muted)
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
        systemPromptSuffix: descriptor.systemPromptSuffix,
        assistantPrefix: descriptor.assistantPrefix
      )
      dependencies.regenerateLLMService(newService)
    }
  #endif
}
