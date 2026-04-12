import CryptoKit
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
  /// Expected file size for integrity check (Q4_K_M GGUF from HuggingFace LFS metadata).
  /// Set to 0 to skip size validation.
  static let modelFileSize: Int64 = 3_106_731_392
  /// SHA256 hash of the model file (lowercase hex), from HuggingFace LFS metadata
  /// (unsloth/gemma-4-E2B-it-GGUF, `oid` field). nil to skip hash verification.
  static let modelSHA256: String? =
    "a67d147c4b461fd5ad394acffa954ecc8686970671d2de8562d6db8888181011"

  // MARK: - Published State

  private(set) var state: ModelState = .checking

  // MARK: - Dependencies

  private let downloader: any ModelDownloader
  private let fileManager: FileManager
  private let physicalMemory: UInt64
  private let expectedFileSize: Int64
  private let expectedSHA256: String?
  private var downloadTask: Task<Void, Never>?

  // MARK: - Computed

  /// Directory for the completed model file: Library/Application Support/.
  /// Application Support persists across app updates and is not purged by the OS,
  /// unlike Library/Caches/. The model file is excluded from iCloud backup
  /// (isExcludedFromBackup) because it can be re-downloaded (~3 GB).
  var modelDirectoryURL: URL {
    fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? fileManager.temporaryDirectory
  }

  var modelFileURL: URL {
    modelDirectoryURL.appendingPathComponent(Self.modelFileName)
  }

  /// Partial download file stored in Library/Caches/.
  /// Caches is appropriate because: not backed up by iCloud, and if the OS purges it
  /// under storage pressure, the download simply restarts (resume offset = 0).
  var downloadFileURL: URL {
    let cachesDir =
      fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
      ?? fileManager.temporaryDirectory
    return cachesDir.appendingPathComponent(Self.downloadFileName)
  }

  // MARK: - Init

  init(
    downloader: any ModelDownloader = URLSessionModelDownloader(),
    fileManager: FileManager = .default,
    physicalMemory: UInt64 = ProcessInfo.processInfo.physicalMemory,
    expectedFileSize: Int64 = modelFileSize,
    expectedSHA256: String? = modelSHA256
  ) {
    self.downloader = downloader
    self.fileManager = fileManager
    self.physicalMemory = physicalMemory
    self.expectedFileSize = expectedFileSize
    self.expectedSHA256 = expectedSHA256
  }

  // MARK: - Public Methods

  /// Checks device compatibility and model file status. Sets `state` accordingly.
  func checkModelStatus() {
    guard physicalMemory >= Self.minimumRAM else {
      state = .unsupportedDevice
      return
    }

    if fileManager.fileExists(atPath: modelFileURL.path) {
      // Only check file size (not SHA256) at launch — hashing 3 GB blocks the UI for ~2s.
      // SHA256 is verified once during download; corruption after download is unlikely.
      if expectedFileSize > 0 {
        let attrs = try? fileManager.attributesOfItem(atPath: modelFileURL.path)
        let fileSize = attrs?[.size] as? Int64 ?? 0
        if fileSize != expectedFileSize {
          // Corrupt or incomplete file at final path — remove it
          try? fileManager.removeItem(at: modelFileURL)
          state = .notDownloaded
          return
        }
      }
      // Best-effort: re-apply on every launch as a safety net in case a prior attempt failed.
      excludeFromBackup(modelFileURL)
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
              let estimatedTotal = Double(max(expectedFileSize, 3_100_000_000))
              progress = min(Double(bytesReceived) / estimatedTotal, 0.99)
            }
            self.state = .downloading(progress: min(progress, 1.0))
          }
        }
      )

      if let error = await verifyDownloadIntegrity() {
        try? fileManager.removeItem(at: downloadFileURL)
        state = .error(error)
        return
      }

      // Ensure Application Support directory exists before moving the file.
      let modelDir = modelFileURL.deletingLastPathComponent()
      try fileManager.createDirectory(at: modelDir, withIntermediateDirectories: true)

      // Atomic rename from Caches/.download to Application Support/ final path.
      // Same volume on iOS, so this is an atomic rename (no copy+delete).
      if fileManager.fileExists(atPath: modelFileURL.path) {
        try fileManager.removeItem(at: modelFileURL)
      }
      try fileManager.moveItem(at: downloadFileURL, to: modelFileURL)

      excludeFromBackup(modelFileURL)
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

  // MARK: - Backup Exclusion

  /// Marks a file as excluded from iCloud backup.
  /// Best-effort: failure is non-fatal because the file is still usable,
  /// and checkModelStatus() re-applies on every launch as a safety net.
  private func excludeFromBackup(_ url: URL) {
    var mutableURL = url
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    try? mutableURL.setResourceValues(values)
  }

  // MARK: - Download Integrity

  /// Validates file size and SHA256 hash of the downloaded file.
  /// Returns an error message if verification fails, or nil if the file is valid.
  private func verifyDownloadIntegrity() async -> String? {
    // Validate file size if expected size is known
    if expectedFileSize > 0 {
      let attrs = try? fileManager.attributesOfItem(atPath: downloadFileURL.path)
      let fileSize = attrs?[.size] as? Int64 ?? 0
      if fileSize != expectedFileSize {
        return "Downloaded file size mismatch (expected \(expectedFileSize), got \(fileSize))"
      }
    }

    // Validate SHA256 hash if expected hash is known.
    // Runs off MainActor to avoid UI freeze on large files (~2s for 3 GB).
    if let expectedSHA256 {
      let downloadURL = downloadFileURL
      let actualSHA256: String
      do {
        actualSHA256 = try await Task.detached {
          try Self.computeSHA256(of: downloadURL)
        }.value
      } catch {
        return "Failed to verify download: \(error.localizedDescription)"
      }
      if actualSHA256 != expectedSHA256 {
        return "Download verification failed. The file may be corrupted — please try again."
      }
    }

    return nil
  }

  // MARK: - SHA256

  /// Computes SHA256 of a file using streaming reads to avoid loading the full file into memory.
  /// Returns lowercase hex string. Marked `nonisolated` because ModelManager inherits MainActor
  /// isolation and hashing a 3 GB file on MainActor would freeze the UI.
  nonisolated static func computeSHA256(of fileURL: URL) throws -> String {
    let handle = try FileHandle(forReadingFrom: fileURL)
    defer { try? handle.close() }

    var hasher = SHA256()
    let bufferSize = 1_024 * 1_024  // 1 MB chunks
    while autoreleasepool(invoking: {
      let data = handle.readData(ofLength: bufferSize)
      guard !data.isEmpty else { return false }
      hasher.update(data: data)
      return true
    }) {}

    let digest = hasher.finalize()
    return digest.map { String(format: "%02x", $0) }.joined()
  }

  /// Removes both the model file and any partial download from disk.
  func deleteModel() {
    try? fileManager.removeItem(at: modelFileURL)
    try? fileManager.removeItem(at: downloadFileURL)
    state = .notDownloaded
  }
}
