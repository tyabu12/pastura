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
    // `internal` (not `private`): the device-only helpers in the sibling
    // `SettingsView+Models.swift` extension read these.
    @Environment(ModelManager.self) var modelManager
    @Environment(AppDependencies.self) var dependencies
    @State var pendingDelete: ModelDescriptor?
    /// Descriptor whose Download action should present the DL demo cover.
    /// Bound to `.fullScreenCover(item:)` — `Identifiable` is supplied by
    /// the conformance on `ModelDescriptor`.
    @State var coverDescriptor: ModelDescriptor?
    /// Descriptor that the user tapped Download on while the cellular
    /// gate was about to fire (#191). Holds the descriptor across the
    /// scene-level consent dialog: on accept, the state observer below
    /// flips `coverDescriptor` to this value once `ModelManager` has
    /// transitioned to `.downloading`. On decline, `pendingCellularConsent`
    /// reverts to nil and the matching observer clears this so the
    /// cover never opens.
    @State var pendingCoverDescriptor: ModelDescriptor?
    /// Orphaned `.gguf` files on disk that match no catalog entry
    /// (superseded-model leftovers). Held in local `@State` rather than
    /// read live from `modelManager` because `orphanedModelFiles()` is a
    /// filesystem read, not `@Observable` — deleting an orphan would not
    /// otherwise invalidate the view. Refreshed on appear and after each
    /// orphan delete.
    @State var orphanedFiles: [OrphanedModelFile] = []
    /// Orphaned file pending the destructive-confirmation dialog. Mirrors
    /// `pendingDelete`'s pattern for catalog models.
    @State var pendingOrphanDelete: OrphanedModelFile?
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
      // Orphaned-file delete — mirrors the per-model confirmation above.
      // Orphans have no catalog entry, so deletion is unconditional (the
      // `deleteOrphanedFile` catalog-membership guard is defense-in-depth).
      .confirmationDialog(
        Text(String(localized: "Delete this file?")),
        isPresented: Binding(
          get: { pendingOrphanDelete != nil },
          set: { if !$0 { pendingOrphanDelete = nil } }),
        titleVisibility: .visible,
        presenting: pendingOrphanDelete
      ) { file in
        Button(String(localized: "Delete"), role: .destructive) {
          modelManager.deleteOrphanedFile(fileName: file.fileName)
          orphanedFiles = modelManager.orphanedModelFiles()
          pendingOrphanDelete = nil
        }
        Button(String(localized: "Cancel"), role: .cancel) {
          pendingOrphanDelete = nil
        }
      } message: { file in
        Text(
          String(
            format: String(localized: "Frees up %@."),
            ModelSettingsRow.formattedFileSize(file.sizeBytes)))
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
}
