import Foundation

/// State of the on-device LLM model.
public enum ModelState: Equatable, Sendable {
  /// Checking device compatibility and model file status.
  case checking
  /// Device does not meet minimum RAM requirement (8 GB).
  case unsupportedDevice
  /// Model is not downloaded. If a partial `.download` file exists, resume is possible.
  case notDownloaded
  /// Model is being downloaded. `progress` is 0.0–1.0.
  case downloading(progress: Double)
  /// Model file is on disk and ready for use.
  case ready(modelPath: String)
  /// An error occurred during download or validation.
  case error(String)
}

/// Manages the on-device LLM model lifecycle: device check, download, storage, and deletion.
///
/// Lives in the App layer because it depends on HTTP (URLSession), filesystem (FileManager),
/// and device capabilities (ProcessInfo) — all App-level concerns. `LlamaCppService` receives
/// the model path via its constructor; it never imports this class.
@Observable
final class ModelManager {
  // MARK: - Constants

  static let modelFileName = "gemma-4-E2B-it-Q4_K_M.gguf"
  static let downloadFileName = "gemma-4-E2B-it-Q4_K_M.gguf.download"
  static let modelURL: URL = {
    guard
      let url = URL(
        string:
          // ggml-org repo only has Q8_0/f16; Q4_K_M is provided by unsloth
          "https://huggingface.co/unsloth/gemma-4-E2B-it-GGUF/resolve/main/gemma-4-E2B-it-Q4_K_M.gguf"
      )
    else {
      preconditionFailure("Invalid hardcoded model URL")
    }
    return url
  }()
  /// Minimum physical memory reported by ProcessInfo to allow model download.
  /// iOS reports ~7.4–7.6 GB on 8 GB devices (kernel reserves ~0.5 GB)
  /// and ~5.4–5.6 GB on 6 GB devices. 6.5 GiB cleanly separates the two tiers.
  static let minimumRAM: UInt64 = 6_500_000_000
  /// Expected file size for integrity check (~3.1 GB Q4_K_M).
  /// Set to 0 to skip size validation (useful during initial deployment before size is known).
  static let expectedFileSize: Int64 = 0

  // MARK: - Published State

  private(set) var state: ModelState = .checking

  // MARK: - Dependencies

  private let downloader: any ModelDownloader
  private let fileManager: FileManager
  private let physicalMemory: UInt64
  private var downloadTask: Task<Void, Never>?

  // MARK: - Computed

  /// Full path to the model file in the Documents directory.
  var modelDirectoryURL: URL {
    // Documents directory is the standard location for user-downloaded content.
    // It persists across app updates and is backed up by iCloud (appropriate for a 3 GB file
    // the user explicitly downloaded).
    // Fallback to temp directory only as a safety net — .documentDirectory should always
    // exist on iOS. Using temp would mean the model file is lost on reboot, but this
    // path is unreachable in practice.
    fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
      ?? fileManager.temporaryDirectory
  }

  var modelFileURL: URL {
    modelDirectoryURL.appendingPathComponent(Self.modelFileName)
  }

  var downloadFileURL: URL {
    modelDirectoryURL.appendingPathComponent(Self.downloadFileName)
  }

  // MARK: - Init

  init(
    downloader: any ModelDownloader = URLSessionModelDownloader(),
    fileManager: FileManager = .default,
    physicalMemory: UInt64 = ProcessInfo.processInfo.physicalMemory
  ) {
    self.downloader = downloader
    self.fileManager = fileManager
    self.physicalMemory = physicalMemory
  }

  // MARK: - Public Methods

  /// Checks device compatibility and model file status. Sets `state` accordingly.
  func checkModelStatus() {
    guard physicalMemory >= Self.minimumRAM else {
      state = .unsupportedDevice
      return
    }

    if fileManager.fileExists(atPath: modelFileURL.path) {
      // Validate file size if expected size is known
      if Self.expectedFileSize > 0 {
        let attrs = try? fileManager.attributesOfItem(atPath: modelFileURL.path)
        let fileSize = attrs?[.size] as? Int64 ?? 0
        if fileSize != Self.expectedFileSize {
          // Corrupt or incomplete file at final path — remove it
          try? fileManager.removeItem(at: modelFileURL)
          state = .notDownloaded
          return
        }
      }
      state = .ready(modelPath: modelFileURL.path)
    } else {
      state = .notDownloaded
    }
  }

  /// Starts downloading the model file from HuggingFace. Stores the task for cancellation.
  func startDownload() {
    // Allow download from .notDownloaded or .error states only
    switch state {
    case .notDownloaded, .error:
      break
    default:
      return
    }

    // Set state synchronously to prevent re-entry before the Task body runs.
    state = .downloading(progress: 0)
    downloadTask = Task { await performDownload() }
  }

  /// Downloads the model file. Supports resume from partial downloads.
  func downloadModel() async {
    // Allow download from .notDownloaded or .error states only
    switch state {
    case .notDownloaded, .error:
      break
    default:
      return
    }

    await performDownload()
  }

  private func performDownload() async {
    // Determine resume offset from existing partial download
    let resumeOffset: Int64
    if fileManager.fileExists(atPath: downloadFileURL.path) {
      let attrs = try? fileManager.attributesOfItem(atPath: downloadFileURL.path)
      resumeOffset = attrs?[.size] as? Int64 ?? 0
    } else {
      resumeOffset = 0
    }

    state = .downloading(progress: resumeOffset > 0 ? 0.01 : 0.0)

    do {
      try await downloader.download(
        from: Self.modelURL,
        resumeOffset: resumeOffset,
        to: downloadFileURL,
        progressHandler: { [weak self] bytesReceived, totalBytes in
          Task { @MainActor [weak self] in
            guard let self else { return }
            let progress: Double
            if totalBytes > 0 {
              progress = Double(bytesReceived) / Double(totalBytes)
            } else {
              // Content-Length unknown — estimate from expected file size (~3.1 GB)
              let estimatedTotal = Double(max(Self.expectedFileSize, 3_100_000_000))
              progress = min(Double(bytesReceived) / estimatedTotal, 0.99)
            }
            self.state = .downloading(progress: min(progress, 1.0))
          }
        }
      )

      // Validate file size if expected size is known
      if Self.expectedFileSize > 0 {
        let attrs = try fileManager.attributesOfItem(atPath: downloadFileURL.path)
        let fileSize = attrs[.size] as? Int64 ?? 0
        if fileSize != Self.expectedFileSize {
          try? fileManager.removeItem(at: downloadFileURL)
          state = .error(
            "Downloaded file size mismatch (expected \(Self.expectedFileSize), got \(fileSize))")
          return
        }
      }

      // Atomic rename from .download to final path
      // Remove existing file at destination if present (e.g., corrupt from prior attempt)
      if fileManager.fileExists(atPath: modelFileURL.path) {
        try fileManager.removeItem(at: modelFileURL)
      }
      try fileManager.moveItem(at: downloadFileURL, to: modelFileURL)

      state = .ready(modelPath: modelFileURL.path)
    } catch is CancellationError {
      // Download was cancelled — keep partial file for resume
      state = .notDownloaded
    } catch {
      // Keep partial .download file for resume
      state = .error(error.localizedDescription)
    }
  }

  /// Cancels an in-progress download. The partial file is kept for resume.
  func cancelDownload() {
    downloadTask?.cancel()
    downloadTask = nil
    state = .notDownloaded
  }

  /// Removes both the model file and any partial download from disk.
  func deleteModel() {
    try? fileManager.removeItem(at: modelFileURL)
    try? fileManager.removeItem(at: downloadFileURL)
    state = .notDownloaded
  }
}
