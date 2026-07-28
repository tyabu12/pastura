import SwiftUI
import os

/// Settings screen hosting the Models section (device only), a Feedback
/// section (rate the app + content-report sheet), and a Legal section.
///
/// The Settings tab's root content, mounted in the tab's
/// `NavigationStack` by `RootTabView` (ADR-016 D4). Per
/// `.claude/rules/navigation.md`, this view must NOT add
/// `navigationDestination(item:|isPresented:)` modifiers — the tab's
/// stack runs the same `Route` destination registry, so mixing scopes
/// would fight it; sheets (`.sheet(isPresented:)`) and
/// `.fullScreenCover(item:)` are exempt from that rule and are used
/// here for the report sheet and download cover respectively.
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
/// ## Feedback section
///
/// Two rows: "Rate Pastura" (external App Store write-review link, #1279)
/// and a "Send a content report" Button that presents
/// `ReportSheet(context: .general)` via the
/// `.reportSheet(isPresented:context:)` helper (which applies
/// `.deepLinkGated()` internally — see navigation.md QA scenario 9).
/// ADR-005 §6.6 substantive commitment ("Settings surface exposes
/// report-mechanism copy per §6.4") is preserved by `ReportSheet`'s
/// introCopy — it binds the surface, not the section header.
///
/// ## Legal section
///
/// Two rows: an external Privacy Policy link (opens Safari via
/// `Environment(\.openURL)`) and an in-app "Licenses" sheet.
struct SettingsView: View {
  // Not `private` — read by the `+Feedback.swift` sibling extension's
  // `externalLinkRow`, and `private` is file-scoped.
  @Environment(\.openURL) var openURL

  /// Opt-in: keep a simulation running (parked in memory) when leaving its
  /// screen, skipping the leave dialog (ADR-017 Phase B, #682). Mirrors the
  /// `FeatureFlags` value at init and persists every flip via its setter, so the
  /// flag stays the single source of truth.
  @State private var keepRunningOnLeave = FeatureFlags.keepRunningOnLeaveEnabled

  /// Opt-out: show the viewer-prediction sheet before the first vote reveal
  /// (#915). Mirrors the `FeatureFlags` value at init and persists every flip
  /// via its setter, so the flag stays the single source of truth.
  @State private var viewerPredictionEnabled = FeatureFlags.viewerPredictionEnabled

  /// Bound to `.reportSheet(isPresented:context:)` for the "Send a
  /// content report" row inside the Feedback section. The sheet reuses
  /// `ReportSheet` with `context: .general` (Settings has no
  /// specific scenario context) — see ADR-005 §6.7 dual-use precedent.
  /// Not `private` — written by the `+Feedback.swift` sibling extension.
  @State var isReportSheetPresented: Bool = false

  /// Bound to `.sheet(isPresented:)` for the "Licenses"
  /// row inside the Legal section.
  @State private var isLicensesSheetPresented: Bool = false

  // Lifted out of the `#if !simulator` block (where the Models section
  // also reads it): the Past Results section's clear-all needs the
  // simulation repository + activity registry on the simulator too.
  // Not `private` — read by the `+PastResults.swift` and `+Models.swift`
  // sibling extensions.
  @Environment(AppDependencies.self) var dependencies

  /// Bound to the clear-all confirmation `.alert` for the "Clear all
  /// results" row. Not `private` — read by the `+PastResults.swift`
  /// sibling extension.
  @State var isShowingClearAllConfirm = false
  /// Set when `deleteAll()` throws; surfaced via an alert. Not `private`
  /// — written by the `+PastResults.swift` sibling extension.
  @State var clearAllError: String?
  /// Byte size of the past-results content (runs + turns + code-phase
  /// events) for the Past Results storage caption + advisory growth-cap
  /// warning (#565/#770). Excludes scenarios + SQLite overhead so it
  /// reaches 0 after a clear-all. `nil` until loaded (and left `nil` on
  /// read failure → caption hidden). Not `private` — read / written by the
  /// `+PastResults.swift` extension.
  @State var pastResultsByteCount: Int64?

  #if !targetEnvironment(simulator)
    // `internal` (not `private`): the device-only helpers in the sibling
    // `SettingsView+Models.swift` extension read these. `dependencies` is
    // shared with `+PastResults.swift`, so it lives at the top level above.
    @Environment(ModelManager.self) var modelManager
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
        simulationSection
        // Theme D — tappable-row language split by destination: rows that
        // leave the app (Rate Pastura, Privacy Policy) take the green
        // `Color.link` dialect + external-link arrow and no chevron; rows
        // opening an in-app sheet (report, licenses) take the standard in-app
        // vocabulary (`PasturaRowLabel`: ink text + trailing chevron) shared
        // with Home / ScenarioDetail / Results. The explicit `Color.link` form
        // (not `.link`) sidesteps the ShapeStyle-vs-Color token trap; the
        // shared `externalLinkRow` helper keeps the two external rows from
        // drifting apart.
        feedbackSection
        PasturaSection(String(localized: "Legal"), style: .grouped) {
          VStack(spacing: 0) {
            externalLinkRow(
              title: String(localized: "Privacy Policy"),
              url: LocalizedPublicPages.privacyPolicy(),
              accessibilityIdentifier: "settings.privacyPolicyLink")

            PasturaRowDivider(leadingInset: PasturaCardMetrics.horizontalMargin)
            Button {
              isLicensesSheetPresented = true
            } label: {
              PasturaRowLabel(title: String(localized: "Licenses"))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("settings.licensesLink")
          }
        }

        pastResultsSection
      }
      .padding(.vertical, PasturaCardMetrics.interCardSpacing)
    }
    .background(Color.screenBackground.ignoresSafeArea())
    // Load the DB size for the Past Results storage caption + advisory
    // cap (#565). `.task` (not `.onAppear`) gives a cancellation-aware
    // async context for the off-main read; it re-fires when the view is
    // recreated, and `clearAllResults()` re-loads explicitly after a purge.
    .task { await loadStorageUsage() }
    .onChange(of: keepRunningOnLeave) { _, newValue in
      FeatureFlags.setKeepRunningOnLeave(newValue)
    }
    .onChange(of: viewerPredictionEnabled) { _, newValue in
      FeatureFlags.setViewerPredictionEnabled(newValue)
    }
    .navigationTitle(String(localized: "Settings"))
    .navigationBarTitleDisplayMode(.inline)
    .reportSheet(isPresented: $isReportSheetPresented, context: .general)
    .sheet(isPresented: $isLicensesSheetPresented) {
      LicensesSheet()
        .deepLinkGated()
    }
    .modifier(
      ClearAllConfirmationModifier(
        isPresented: $isShowingClearAllConfirm,
        error: $clearAllError,
        onConfirm: { await clearAllResults() }
      )
    )
    #if !targetEnvironment(simulator)
      // `.alert` (not `.confirmationDialog`): iOS 26 renders a Menu-
      // triggered confirmationDialog as a popover whose arrow anchors to
      // the body centre. A centred alert presents correctly.
      .alert(
        // Title carries the specific model name so VoiceOver reads it rather
        // than a generic "Delete this model?" for every row. Uses the
        // Form-B `String(format:)` path (not `String(localized: "...\(x)...")`)
        // because the interpolated form's runtime lookup key becomes the
        // substituted string, missing the catalog → English on ja (#578).
        String(
          format: String(localized: "Delete %@?"),
          pendingDelete?.displayName ?? String(localized: "this model")),
        isPresented: Binding(
          get: { pendingDelete != nil },
          set: { if !$0 { pendingDelete = nil } }),
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
            format: String(localized: "Re-downloading %@ takes a few minutes."),
            ModelSettingsRow.formattedFileSize(descriptor.fileSize)))
      }
      // Orphaned-file delete — mirrors the per-model confirmation above
      // (also `.alert` for the iOS 26 popover-anchor reason). Orphans have
      // no catalog entry, so deletion is unconditional (the
      // `deleteOrphanedFile` catalog-membership guard is defense-in-depth).
      .alert(
        String(localized: "Delete this file?"),
        isPresented: Binding(
          get: { pendingOrphanDelete != nil },
          set: { if !$0 { pendingOrphanDelete = nil } }),
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

  /// Simulation-behaviour toggles: keep-running-on-leave (opt-in, ADR-017
  /// Phase B, #682) and viewer prediction (opt-out, #915). Label-closure form
  /// per the i18n convenience-init convention (`.claude/rules/i18n.md`).
  private var simulationSection: some View {
    PasturaSection(String(localized: "Simulation"), style: .grouped) {
      Toggle(isOn: $keepRunningOnLeave) {
        VStack(alignment: .leading, spacing: 3) {
          Text(String(localized: "Keep running when I leave"))
            .foregroundStyle(Color.ink)
          Text(
            String(
              localized:
                "Leave the simulation screen without pausing — the run keeps going in memory and resumes when you return."
            )
          )
          .font(.caption)
          .foregroundStyle(Color.muted)
        }
      }
      .tint(Color.link)
      .padding(.horizontal, 17)
      .padding(.vertical, 13)
      .accessibilityIdentifier("settings.keepRunningOnLeaveToggle")

      Toggle(isOn: $viewerPredictionEnabled) {
        VStack(alignment: .leading, spacing: 3) {
          Text(String(localized: "Predict the outcome"))
            .foregroundStyle(Color.ink)
          Text(
            String(
              localized:
                "Before the votes are revealed, guess the outcome and track your streak. You can always skip."
            )
          )
          .font(.caption)
          .foregroundStyle(Color.muted)
        }
      }
      .tint(Color.link)
      .padding(.horizontal, 17)
      .padding(.vertical, 13)
      .accessibilityIdentifier("settings.viewerPredictionToggle")
    }
  }
}
