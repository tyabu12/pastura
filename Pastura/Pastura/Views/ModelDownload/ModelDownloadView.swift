import SwiftUI

/// Screen for downloading the on-device LLM model.
///
/// Shown when the model file is not yet on disk. Driven entirely by
/// `ModelManager.state` — no separate ViewModel needed.
struct ModelDownloadView: View {
  let modelManager: ModelManager

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
    switch modelManager.state {
    case .checking:
      ProgressView("Checking device...")

    case .unsupportedDevice:
      unsupportedDeviceView

    case .notDownloaded:
      notDownloadedView

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
        .foregroundStyle(.orange)
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

  private var notDownloadedView: some View {
    VStack(spacing: 16) {
      Image(systemName: "arrow.down.circle")
        .font(.system(size: 48))
        .foregroundStyle(.blue)
      Text("Download AI Model")
        .font(.title2.bold())
      VStack(spacing: 4) {
        Text("Gemma 4 E2B (Q4_K_M)")
          .font(.subheadline)
        Text("~3.1 GB download")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      Text("The model runs entirely on-device. No internet needed after download.")
        .font(.caption)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
      Button {
        modelManager.startDownload()
      } label: {
        Label("Download Model", systemImage: "arrow.down.circle.fill")
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(.borderedProminent)
      .controlSize(.large)
    }
  }

  private func downloadingView(progress: Double) -> some View {
    VStack(spacing: 16) {
      Image(systemName: "arrow.down.circle")
        .font(.system(size: 48))
        .foregroundStyle(.blue)
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
        modelManager.cancelDownload()
      }
      .foregroundStyle(.red)
    }
  }

  private var readyView: some View {
    VStack(spacing: 16) {
      Image(systemName: "checkmark.circle.fill")
        .font(.system(size: 48))
        .foregroundStyle(.green)
      Text("Model Ready")
        .font(.title2.bold())
    }
  }

  private func errorView(message: String) -> some View {
    VStack(spacing: 16) {
      Image(systemName: "exclamationmark.triangle.fill")
        .font(.system(size: 48))
        .foregroundStyle(.red)
      Text("Download Failed")
        .font(.title2.bold())
      Text(message)
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
      Button {
        modelManager.startDownload()
      } label: {
        Label("Retry", systemImage: "arrow.clockwise")
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(.borderedProminent)
      .controlSize(.large)
    }
  }
}
