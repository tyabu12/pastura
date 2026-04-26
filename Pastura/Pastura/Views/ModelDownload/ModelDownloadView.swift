import SwiftUI

/// Screen for downloading a specific on-device LLM model.
///
/// Shown when the model file is not yet on disk, or as the cellular /
/// low-demo-count fallback inside `DemoReplayHostView`. Driven entirely
/// by `ModelManager.state[descriptor.id]` — no separate ViewModel needed.
///
/// `onCancel` overrides the in-progress Cancel button when set: the
/// Settings cover passes a destructive cancel (delete partial + final),
/// while the first-launch slot leaves it nil and falls through to the
/// resume-friendly `cancelDownload(descriptor:)`.
struct ModelDownloadView: View {
  let modelManager: ModelManager
  let descriptor: ModelDescriptor
  let onCancel: (() -> Void)?

  init(
    modelManager: ModelManager,
    descriptor: ModelDescriptor,
    onCancel: (() -> Void)? = nil
  ) {
    self.modelManager = modelManager
    self.descriptor = descriptor
    self.onCancel = onCancel
  }

  /// State for this descriptor, falling back to `.checking` if the entry is
  /// missing from the state dict (only expected pre-`checkModelStatus`).
  private var currentState: ModelState {
    modelManager.state[descriptor.id] ?? .checking
  }

  var body: some View {
    NavigationStack {
      VStack(spacing: 24) {
        Spacer()
        content
        Spacer()
      }
      .padding()
      .navigationTitle("Model Setup")
    }
  }

  @ViewBuilder
  private var content: some View {
    switch currentState {
    case .checking:
      ProgressView("Checking device...")

    case .unsupportedDevice:
      unsupportedDeviceView

    case .notDownloaded:
      // Defensive escape hatch: both auto-DL trigger points
      // (`RootView.handleModelPick` and `RootView.initialize`'s
      // `.notDownloaded` branch) call `startDownload` synchronously,
      // and `Settings.presentDownloadCover` does the same — so this
      // case shouldn't normally render. Surface it via `errorView`
      // with retry-able copy in case `startDownload` is rejected by
      // the sequential-download policy or fails to enqueue.
      errorView(
        message: String(
          localized:
            "Couldn't start the download. Please try again."))

    case .downloading(let progress):
      downloadingView(progress: progress)

    case .ready:
      readyView

    case .error(let message):
      errorView(message: message)
    }
  }

  // MARK: - State Views

  private var unsupportedDeviceView: some View {
    VStack(spacing: 16) {
      Image(systemName: "exclamationmark.triangle.fill")
        .font(.system(size: 48))
        .foregroundStyle(Color.warning)
      Text("Unsupported Device")
        .font(.title2.bold())
      Text(
        "This device does not have enough memory to run the AI model. At least 8 GB of RAM is required."
      )
      .font(.subheadline)
      .foregroundStyle(.secondary)
      .multilineTextAlignment(.center)
      Text("Supported: iPhone 15 Pro and later")
        .font(.caption)
        .foregroundStyle(.tertiary)
    }
  }

  private func downloadingView(progress: Double) -> some View {
    VStack(spacing: 16) {
      Image(systemName: "arrow.down.circle")
        .font(.system(size: 48))
        .foregroundStyle(Color.moss)
        .symbolEffect(.pulse)
      Text("Downloading Model...")
        .font(.title2.bold())
      ProgressView(value: progress) {
        Text("\(Int(progress * 100))%")
          .font(.subheadline.monospacedDigit())
      }
      .progressViewStyle(.linear)
      Text("Please keep the app open during download.")
        .font(.caption)
        .foregroundStyle(.secondary)
      Button("Cancel") {
        if let onCancel {
          onCancel()
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

  private var readyView: some View {
    VStack(spacing: 16) {
      Image(systemName: "checkmark.circle.fill")
        .font(.system(size: 48))
        .foregroundStyle(Color.success)
      Text("Model Ready")
        .font(.title2.bold())
    }
  }

  private func errorView(message: String) -> some View {
    VStack(spacing: 16) {
      Image(systemName: "exclamationmark.triangle.fill")
        .font(.system(size: 48))
        .foregroundStyle(Color.danger)
      Text("Download Failed")
        .font(.title2.bold())
      Text(message)
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
      Button {
        modelManager.startDownload(descriptor: descriptor)
      } label: {
        Label("Retry", systemImage: "arrow.clockwise")
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(.borderedProminent)
      .controlSize(.large)
    }
  }

}
