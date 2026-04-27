import SwiftUI

/// Per-`ModelState` UI for `ModelDownloadHostView`. Absorbs the rendering
/// formerly provided by `ModelDownloadView` so the host view owns every
/// download-time surface — keeps callers (RootView's
/// `.needsModelDownload` slot, Settings cover) from having to dispatch
/// on `ModelState` themselves.
///
/// Lives in a sibling file so the host view's main file stays under
/// swiftlint's 400-line `file_length` cap. Sibling pattern matches
/// `ModelDownloadHostView+Routing.swift`.
extension ModelDownloadHostView {

  // MARK: - State dispatch

  /// Disjoint output of the state-to-view dispatch function. Each case
  /// maps to exactly one rendering branch in
  /// ``stateBranchView(_:progress:errorMessage:)``.
  enum StateView: Equatable {
    /// Initial post-init state — `checkModelStatus()` has not run yet.
    case checking
    /// Device is below the 6.5 GB RAM floor (Phase 2).
    case unsupportedDevice
    /// Cellular network with no consent. Renders the Wi-Fi advisory
    /// with a Try Again button. ADR-007 §3.3 (c) decline path.
    case wifiRequired
    /// Defensive fallback for `.notDownloaded` outside the cellular
    /// gate — typically a sequential-download rejection. Was the
    /// `errorView("Couldn't start the download…")` in the old
    /// `ModelDownloadView`.
    case notDownloadedDefensive
    /// `.downloading` but bundled demo count is below
    /// `minPlayableDemoCount`. Plain progress bar — the rotation loop
    /// would be unsatisfying with 0–1 demos (spec §5.2).
    case plainProgress
    /// `.error` arrived before replay started. Shows a full-screen
    /// "Download Failed" with a Retry button. ADR-007 §3.3 (b)
    /// no-replay-started branch.
    case error(message: String)
    /// `.downloading` with sufficient demos / `.error` after replay
    /// started / `.ready`. Renders the demo-host body
    /// (`demoHostBody` in the main file).
    case demoHost
  }

  /// Pure dispatch from `(ModelState, demosCount, replayHadStarted,
  /// requiresCellularConsent)` to `StateView`. Extracted for unit
  /// testability — `ModelDownloadHostViewTests` exercises every case.
  ///
  /// Cellular-network detection is **not** an input here: the cellular
  /// gate moved upstream to `ModelManager.startDownload` (#191), so by
  /// the time this dispatch runs, either consent was granted (state is
  /// `.downloading` / `.ready`) or the gate fired (state stays
  /// `.notDownloaded` and `requiresCellularConsent == true`).
  static func stateView(
    state: ModelState,
    demosCount: Int,
    replayHadStarted: Bool,
    requiresCellularConsent: Bool
  ) -> StateView {
    switch state {
    case .checking:
      return .checking
    case .unsupportedDevice:
      return .unsupportedDevice
    case .notDownloaded:
      return requiresCellularConsent ? .wifiRequired : .notDownloadedDefensive
    case .downloading:
      return demosCount >= Self.minPlayableDemoCount ? .demoHost : .plainProgress
    case .error(let message):
      return replayHadStarted ? .demoHost : .error(message: message)
    case .ready:
      return .demoHost
    }
  }

  // MARK: - Plain-state rendering

  /// Common chrome around plain-state UI: `NavigationStack` + centered
  /// `VStack` + "Model Setup" navigation title — matches what
  /// `ModelDownloadView` used to provide before absorption (#191).
  @ViewBuilder
  private func plainContainer<Content: View>(
    @ViewBuilder content: () -> Content
  ) -> some View {
    NavigationStack {
      VStack(spacing: 24) {
        Spacer()
        content()
        Spacer()
      }
      .padding()
      .navigationTitle("Model Setup")
    }
  }

  @ViewBuilder
  var checkingFallback: some View {
    plainContainer {
      ProgressView(String(localized: "Checking device..."))
    }
  }

  @ViewBuilder
  var unsupportedDeviceFallback: some View {
    plainContainer {
      VStack(spacing: 16) {
        Image(systemName: "exclamationmark.triangle.fill")
          .font(.system(size: 48))
          .foregroundStyle(Color.warning)
        Text(String(localized: "Unsupported Device"))
          .font(.title2.bold())
        Text(
          String(
            localized:
              "This device does not have enough memory to run the AI model. At least 8 GB of RAM is required."
          )
        )
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        Text(String(localized: "Supported: iPhone 15 Pro and later"))
          .font(.caption)
          .foregroundStyle(.tertiary)
      }
    }
  }

  /// Wi-Fi advisory shown when the cellular gate set
  /// `pendingCellularConsent` and the user declined (or has not yet
  /// accepted). Try Again re-fires `startDownload`, which re-presents
  /// the scene-level confirmation dialog if the user is still on
  /// cellular. ADR-007 §3.3 (c) decline path.
  @ViewBuilder
  var wifiRequiredFallback: some View {
    plainContainer {
      VStack(spacing: 16) {
        Image(systemName: "wifi.slash")
          .font(.system(size: 48))
          .foregroundStyle(Color.moss)
        Text(String(localized: "Wi-Fi recommended"))
          .font(.title2.bold())
        Text(
          String(
            localized: "This download is set to Wi-Fi only. Tap Try Again to change.")
        )
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        Button {
          modelManager.startDownload(descriptor: descriptor)
        } label: {
          Label(String(localized: "Try Again"), systemImage: "arrow.clockwise")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
      }
    }
  }

  @ViewBuilder
  var notDownloadedDefensiveFallback: some View {
    plainErrorFallback(
      message: String(localized: "Couldn't start the download. Please try again."))
  }

  /// Plain progress bar shown when `.downloading` but the bundled demo
  /// count is below the floor (rotation loop unsatisfying with 0–1
  /// demos — spec §5.2). Cancel routes through the same confirmation
  /// dialog as the demo-host PromoCard's Cancel when the host is given
  /// an `onCancel`; otherwise (first-launch slot) cancels directly with
  /// `cancelDownload` to keep the partial file for resume.
  @ViewBuilder
  func plainProgressFallback(progress: Double) -> some View {
    plainContainer {
      VStack(spacing: 16) {
        Image(systemName: "arrow.down.circle")
          .font(.system(size: 48))
          .foregroundStyle(Color.moss)
          .symbolEffect(.pulse)
        Text(String(localized: "Downloading Model..."))
          .font(.title2.bold())
        ProgressView(value: progress) {
          Text("\(Int(progress * 100))%")
            .font(.subheadline.monospacedDigit())
        }
        .progressViewStyle(.linear)
        Text(String(localized: "Please keep the app open during download."))
          .font(.caption)
          .foregroundStyle(.secondary)
        Button(String(localized: "Cancel")) {
          if let trigger = triggerCancelConfirmation {
            trigger()
          } else {
            // First-launch fallback: resume-friendly cancel preserves the
            // partial file so the user can retry without re-downloading.
            modelManager.cancelDownload(descriptor: descriptor)
          }
        }
        // Neutral cancel per design-system §2.6: `inkSecondary` text on a plain
        // (no-border) button. The §2.6 "rule border" requirement applies only
        // when a border is rendered; default-style Button has none.
        .foregroundStyle(Color.inkSecondary)
      }
    }
  }

  /// Full-screen "Download Failed" used by `.error` (no replay started)
  /// and `.notDownloaded` defensive. Retry calls `startDownload` —
  /// re-passes through the cellular gate when applicable, so a
  /// post-decline retry on cellular re-presents the modal.
  @ViewBuilder
  func plainErrorFallback(message: String) -> some View {
    plainContainer {
      VStack(spacing: 16) {
        Image(systemName: "exclamationmark.triangle.fill")
          .font(.system(size: 48))
          .foregroundStyle(Color.danger)
        Text(String(localized: "Download Failed"))
          .font(.title2.bold())
        Text(message)
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
        Button {
          modelManager.startDownload(descriptor: descriptor)
        } label: {
          Label(String(localized: "Retry"), systemImage: "arrow.clockwise")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
      }
    }
  }
}
