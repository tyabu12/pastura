// swiftlint:disable file_length
// Deliberately long: ModelManager owns the per-descriptor state machine,
// download pipeline (with throttled progress), integrity verification
// (fileSize + streaming SHA256), and filesystem layout (Application Support
// / Caches conventions). Splitting these into separate files would require
// widening `private` fields (`state`, `downloader`, `fileManager`,
// `downloadTasks`) to `internal`, which weakens the class's state
// encapsulation for a mechanical line-count win. Prefer the focused,
// self-contained class. See LlamaCppService.swift for the same pattern.
import CryptoKit
import Foundation
import os

/// State of a single on-device LLM model.
public enum ModelState: Equatable, Sendable {
  /// Checking device compatibility and model file status.
  case checking
  /// Device does not meet minimum RAM requirement (shared 6.5 GB floor in Phase 2).
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

/// Manages on-device LLM model lifecycle: device check, download, storage, deletion.
///
/// Multi-model aware. State is tracked per-descriptor so multiple models can coexist
/// on disk; only one is loaded in memory at a time (the "active" model, persisted in
/// UserDefaults). View call-sites that operate on the active model can use the
/// `active*` convenience wrappers (`activeState`, `startActiveDownload`, ...).
///
/// Download policy: **sequential** — at most one descriptor is `.downloading` at
/// any time. Concurrent download attempts are rejected to avoid network/CPU
/// contention (two 3 GB GGUF downloads would saturate cellular and run two
/// off-MainActor SHA256 hashes).
///
/// ### State machine (per-descriptor)
///
/// | Action                | idle / `.notDownloaded` | `.downloading`                 | `.ready`                      | `.error`      |
/// |-----------------------|-------------------------|--------------------------------|-------------------------------|---------------|
/// | `startDownload(d)`    | → `.downloading`†       | no-op (own descriptor)         | no-op (already done)          | → `.downloading` |
/// | `cancelDownload(d)`   | no-op                   | → `.notDownloaded`, keep partial | no-op                       | no-op         |
/// | `deleteModel(d)`      | remove partial if any, → `.notDownloaded` | cancel + remove partial, → `.notDownloaded` | remove file, → `.notDownloaded` | remove file + partial, → `.notDownloaded` |
/// | `setActiveModel(id)`  | validate id ∈ catalog, write UserDefaults — does not touch state dict |
///
/// †: `startDownload` is also rejected (no-op) if ANY descriptor is already
/// `.downloading` (sequential-download policy).
///
/// Lives in the App layer because it depends on HTTP (URLSession), filesystem
/// (FileManager), and device capabilities (ProcessInfo) — all App-level concerns.
/// `LlamaCppService` receives a model path via its constructor; it never imports
/// this class.
@Observable
final class ModelManager {
  // MARK: - Constants

  /// Minimum physical memory reported by ProcessInfo to allow any model download.
  /// iOS reports ~7.4–7.6 GB on 8 GB devices (kernel reserves ~0.5 GB)
  /// and ~5.4–5.6 GB on 6 GB devices. 6.5 GiB cleanly separates the two tiers.
  ///
  /// Phase 2 uses a shared floor across all catalog descriptors. `ModelDescriptor.minRAM`
  /// is reserved for Phase 3 tier-auto (where a lighter model targets 6 GB devices).
  static let minimumRAM: UInt64 = 6_500_000_000

  /// UserDefaults key for the persisted active model id.
  static let activeModelIDKey = "com.pastura.activeModelID"

  // MARK: - Published State

  /// Per-descriptor state, keyed by `ModelDescriptor.id`. Populated at init with
  /// `.checking` for every catalog entry; `checkModelStatus()` resolves each.
  private(set) var state: [ModelID: ModelState]

  /// Currently-active model's id. Persisted in UserDefaults under `activeModelIDKey`.
  /// Falls back to `ModelRegistry.defaultInitialModelID` if no persisted value
  /// exists or the persisted id is not in the current catalog.
  private(set) var activeModelID: ModelID

  // MARK: - Dependencies

  private let downloader: any ModelDownloader
  private let fileManager: FileManager
  private let physicalMemory: UInt64
  private let userDefaults: UserDefaults
  let catalog: [ModelDescriptor]
  private var downloadTasks: [ModelID: Task<Void, Never>] = [:]

  // MARK: - Paths

  /// Directory for completed model files: Library/Application Support/.
  /// Application Support persists across app updates and is not purged by the OS,
  /// unlike Library/Caches/. Files are excluded from iCloud backup
  /// (isExcludedFromBackup) because they can be re-downloaded (~3 GB each).
  var modelDirectoryURL: URL {
    fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? fileManager.temporaryDirectory
  }

  /// Directory for partial downloads: Library/Caches/.
  /// Caches is appropriate because: not backed up by iCloud, and if the OS purges it
  /// under storage pressure, the download simply restarts (resume offset = 0).
  var cachesDirectoryURL: URL {
    fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
      ?? fileManager.temporaryDirectory
  }

  /// Absolute file URL for the completed model corresponding to `descriptor`.
  func modelFileURL(for descriptor: ModelDescriptor) -> URL {
    modelDirectoryURL.appendingPathComponent(descriptor.fileName)
  }

  /// Absolute file URL for the partial download corresponding to `descriptor`.
  /// Naming convention is `<fileName>.download`, which preserves the legacy Gemma
  /// partial-file path (`gemma-4-E2B-it-Q4_K_M.gguf.download`) automatically.
  func downloadFileURL(for descriptor: ModelDescriptor) -> URL {
    cachesDirectoryURL.appendingPathComponent(descriptor.fileName + ".download")
  }

  // MARK: - Convenience (active model)

  /// The `ModelDescriptor` matching `activeModelID`, or `nil` if the catalog is empty.
  /// `nil` is only expected during test setup with an empty catalog — production
  /// `ModelRegistry.catalog` always contains at least one entry.
  var activeDescriptor: ModelDescriptor? {
    catalog.first(where: { $0.id == activeModelID })
  }

  /// State of the currently-active model. `.checking` if the active id is not in
  /// the state dict (should not happen post-`checkModelStatus`).
  var activeState: ModelState {
    state[activeModelID] ?? .checking
  }

  /// Whether any catalog descriptor is currently downloading. Used by
  /// `startDownload` to enforce the sequential-download policy.
  var isAnyDownloadInProgress: Bool {
    state.values.contains {
      if case .downloading = $0 { return true }
      return false
    }
  }

  // MARK: - Init

  init(
    downloader: any ModelDownloader = URLSessionModelDownloader(),
    fileManager: FileManager = .default,
    physicalMemory: UInt64 = ProcessInfo.processInfo.physicalMemory,
    userDefaults: UserDefaults = .standard,
    catalog: [ModelDescriptor] = ModelRegistry.catalog
  ) {
    self.downloader = downloader
    self.fileManager = fileManager
    self.physicalMemory = physicalMemory
    self.userDefaults = userDefaults
    self.catalog = catalog
    self.activeModelID = Self.resolveInitialActiveID(
      persistedID: userDefaults.string(forKey: Self.activeModelIDKey),
      catalog: catalog
    )

    // Seed all catalog descriptors with `.checking` so `activeState` is well-defined
    // before the first `checkModelStatus()`.
    var initial: [ModelID: ModelState] = [:]
    for descriptor in catalog {
      initial[descriptor.id] = .checking
    }
    self.state = initial
  }

  /// Resolves which descriptor id should be active at init time.
  ///
  /// Resolution order:
  /// 1. Persisted UserDefaults value, if it's present in `catalog`
  /// 2. `ModelRegistry.defaultInitialModelID`, if it's present in `catalog`
  /// 3. First descriptor in `catalog` (covers test catalogs that exclude the default)
  /// 4. Empty string (only reached with an empty catalog — not a production scenario)
  ///
  /// Exposed as `static` so it can be unit-tested in isolation.
  static func resolveInitialActiveID(
    persistedID: String?,
    catalog: [ModelDescriptor]
  ) -> ModelID {
    if let persistedID, catalog.contains(where: { $0.id == persistedID }) {
      return persistedID
    }
    if catalog.contains(where: { $0.id == ModelRegistry.defaultInitialModelID }) {
      return ModelRegistry.defaultInitialModelID
    }
    return catalog.first?.id ?? ""
  }

  // MARK: - Public Methods

  /// Resolves each catalog descriptor's state by inspecting the filesystem.
  /// Sets every descriptor to `.unsupportedDevice` if `physicalMemory < minimumRAM`.
  func checkModelStatus() {
    guard physicalMemory >= Self.minimumRAM else {
      for descriptor in catalog {
        state[descriptor.id] = .unsupportedDevice
      }
      return
    }
    for descriptor in catalog {
      state[descriptor.id] = computeState(for: descriptor)
    }
  }

  /// Sets the active model to `id` and persists it in UserDefaults. No-op if
  /// `id` is not in the current catalog — callers should validate first.
  ///
  /// **Important**: This does not trigger LLMService regeneration — that is
  /// orchestrated by AppDependencies in PR B. Callers must also ensure no
  /// simulation is currently running (enforced via SimulationActivityRegistry
  /// in PR B), or the running simulation's LLMService may be unloaded mid-flight.
  func setActiveModel(_ id: ModelID) {
    guard catalog.contains(where: { $0.id == id }) else { return }
    activeModelID = id
    userDefaults.set(id, forKey: Self.activeModelIDKey)
  }

  /// Starts downloading `descriptor`. Rejected (no-op) if any descriptor is
  /// already `.downloading` (sequential-download policy) or if `descriptor`'s
  /// current state is not `.notDownloaded` / `.error`.
  func startDownload(descriptor: ModelDescriptor) {
    guard !isAnyDownloadInProgress else { return }
    let currentState = state[descriptor.id] ?? .checking
    switch currentState {
    case .notDownloaded, .error:
      break
    default:
      return
    }
    // Set synchronously to prevent re-entry before the Task body runs.
    state[descriptor.id] = .downloading(progress: 0)
    downloadTasks[descriptor.id] = Task { await performDownload(descriptor: descriptor) }
  }

  /// Async variant of `startDownload`. Same gating semantics; awaits the
  /// download directly rather than storing the Task.
  func downloadModel(descriptor: ModelDescriptor) async {
    guard !isAnyDownloadInProgress else { return }
    let currentState = state[descriptor.id] ?? .checking
    switch currentState {
    case .notDownloaded, .error:
      break
    default:
      return
    }
    await performDownload(descriptor: descriptor)
  }

  /// Cancels an in-progress download for `descriptor`. The partial file is
  /// kept for resume. No-op if no download is in flight for this descriptor
  /// — specifically, the state transition to `.notDownloaded` only fires
  /// when the current state is `.downloading`; `.ready` / `.error` /
  /// `.notDownloaded` are preserved so a stray call from the UI cannot
  /// silently flip a completed model to `.notDownloaded`.
  func cancelDownload(descriptor: ModelDescriptor) {
    downloadTasks[descriptor.id]?.cancel()
    downloadTasks[descriptor.id] = nil
    if case .downloading = state[descriptor.id] {
      state[descriptor.id] = .notDownloaded
    }
  }

  /// Removes both the completed model file and any partial download for
  /// `descriptor`. Cancels an in-flight download for the same descriptor first.
  func deleteModel(descriptor: ModelDescriptor) {
    downloadTasks[descriptor.id]?.cancel()
    downloadTasks[descriptor.id] = nil
    try? fileManager.removeItem(at: modelFileURL(for: descriptor))
    try? fileManager.removeItem(at: downloadFileURL(for: descriptor))
    state[descriptor.id] = .notDownloaded
  }

  // MARK: - Private: State Computation

  private func computeState(for descriptor: ModelDescriptor) -> ModelState {
    let fileURL = modelFileURL(for: descriptor)
    guard fileManager.fileExists(atPath: fileURL.path) else {
      return .notDownloaded
    }
    // Only check file size (not SHA256) at launch — hashing ~3 GB blocks the UI
    // for ~2 s. SHA256 is verified once at download time.
    if descriptor.fileSize > 0 {
      let attrs = try? fileManager.attributesOfItem(atPath: fileURL.path)
      let fileSize = attrs?[.size] as? Int64 ?? 0
      if fileSize != descriptor.fileSize {
        try? fileManager.removeItem(at: fileURL)
        return .notDownloaded
      }
    }
    // Best-effort: re-apply on every launch as a safety net in case a prior attempt failed.
    excludeFromBackup(fileURL)
    return .ready(modelPath: fileURL.path)
  }

  // MARK: - Private: Download

  private func performDownload(descriptor: ModelDescriptor) async {
    let modelURL = modelFileURL(for: descriptor)
    let partialURL = downloadFileURL(for: descriptor)

    // Determine resume offset from existing partial download
    let resumeOffset: Int64
    if fileManager.fileExists(atPath: partialURL.path) {
      let attrs = try? fileManager.attributesOfItem(atPath: partialURL.path)
      resumeOffset = attrs?[.size] as? Int64 ?? 0
    } else {
      resumeOffset = 0
    }

    state[descriptor.id] = .downloading(progress: resumeOffset > 0 ? 0.01 : 0.0)

    // Throttle UI updates to ~10 Hz (100ms). URLSession's `didWriteData`
    // callback fires hundreds of times per second on a 3 GB download; without
    // throttling, every tick spawned a `Task { @MainActor }` and saturated the
    // MainActor scheduler for the entire multi-minute download.
    //
    // Wrapped in `OSAllocatedUnfairLock` because two callsites mutate it:
    // production URLSession's serial delegate queue (off-MainActor) and
    // `MockModelDownloader` in tests (on MainActor).
    let throttle = OSAllocatedUnfairLock<ProgressThrottle>(initialState: ProgressThrottle())
    let expectedSize = descriptor.fileSize
    let descriptorID = descriptor.id

    do {
      try await downloader.download(
        from: descriptor.downloadURL,
        resumeOffset: resumeOffset,
        to: partialURL,
        progressHandler: { [weak self] bytesReceived, totalBytes in
          let shouldEmit = throttle.withLock { $0.shouldEmit(now: .now) }
          guard shouldEmit else { return }
          Task { @MainActor [weak self] in
            guard let self else { return }
            let progress: Double
            if totalBytes > 0 {
              progress = Double(bytesReceived) / Double(totalBytes)
            } else {
              // Content-Length unknown — estimate from expected file size.
              // 3.1 GB lower-bound matches the Phase-2 Gemma size; Qwen (2.5 GB)
              // will show slightly pessimistic progress when Content-Length is
              // absent, which is acceptable for a rare edge case.
              let estimatedTotal = Double(max(expectedSize, 3_100_000_000))
              progress = min(Double(bytesReceived) / estimatedTotal, 0.99)
            }
            self.state[descriptorID] = .downloading(progress: min(progress, 1.0))
          }
        }
      )

      try await finalizeDownload(
        descriptor: descriptor, modelURL: modelURL, partialURL: partialURL
      )
    } catch is CancellationError {
      // Download was cancelled — keep partial file for resume
      state[descriptor.id] = .notDownloaded
    } catch {
      // Keep partial .download file for resume
      state[descriptor.id] = .error(error.localizedDescription)
    }
  }

  /// Post-download finalization: force terminal 100%, verify integrity,
  /// atomically rename the partial into Application Support, and mark the
  /// descriptor `.ready`. Extracted from `performDownload` to keep that
  /// function under swiftlint's function_body_length cap.
  private func finalizeDownload(
    descriptor: ModelDescriptor, modelURL: URL, partialURL: URL
  ) async throws {
    // Force a terminal 100% transition before SHA256 verification.
    // Production URLSession does not guarantee a final `didWriteData` call
    // at `received == total`, and even if it did, it could be throttled out
    // above. Without this, the UI stalls at ~99% during the ~2 s SHA256 hash
    // on a 3 GB file.
    state[descriptor.id] = .downloading(progress: 1.0)

    if let error = await verifyDownloadIntegrity(descriptor: descriptor) {
      try? fileManager.removeItem(at: partialURL)
      state[descriptor.id] = .error(error)
      return
    }

    // Ensure Application Support directory exists before moving the file.
    let modelDir = modelURL.deletingLastPathComponent()
    try fileManager.createDirectory(at: modelDir, withIntermediateDirectories: true)

    // Atomic rename from Caches/.download to Application Support/ final path.
    // Same volume on iOS, so this is an atomic rename (no copy+delete).
    if fileManager.fileExists(atPath: modelURL.path) {
      try fileManager.removeItem(at: modelURL)
    }
    try fileManager.moveItem(at: partialURL, to: modelURL)

    excludeFromBackup(modelURL)
    state[descriptor.id] = .ready(modelPath: modelURL.path)
  }

  // MARK: - Private: Integrity

  /// Validates file size and SHA256 hash of the downloaded partial file.
  /// Returns an error message if verification fails, or `nil` if the file is valid.
  private func verifyDownloadIntegrity(descriptor: ModelDescriptor) async -> String? {
    let partialURL = downloadFileURL(for: descriptor)

    // Validate file size if the descriptor provides one (0 = skip, used only in tests)
    if descriptor.fileSize > 0 {
      let attrs = try? fileManager.attributesOfItem(atPath: partialURL.path)
      let fileSize = attrs?[.size] as? Int64 ?? 0
      if fileSize != descriptor.fileSize {
        return "Downloaded file size mismatch (expected \(descriptor.fileSize), got \(fileSize))"
      }
    }

    // Validate SHA256 if provided (empty string = skip, used only in tests).
    // Runs off MainActor to avoid UI freeze on large files (~2 s for 3 GB).
    guard !descriptor.sha256.isEmpty else { return nil }

    let actualSHA256: String
    do {
      actualSHA256 = try await Task.detached {
        try Self.computeSHA256(of: partialURL)
      }.value
    } catch {
      return "Failed to verify download: \(error.localizedDescription)"
    }
    if actualSHA256 != descriptor.sha256 {
      return "Download verification failed. The file may be corrupted — please try again."
    }
    return nil
  }

  // MARK: - Private: Backup Exclusion + SHA256

  /// Marks a file as excluded from iCloud backup.
  /// Best-effort: failure is non-fatal because the file is still usable,
  /// and `checkModelStatus()` re-applies on every launch as a safety net.
  private func excludeFromBackup(_ url: URL) {
    var mutableURL = url
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    try? mutableURL.setResourceValues(values)
  }

  /// Computes SHA256 of a file using streaming reads to avoid loading the full
  /// file into memory. Returns lowercase hex string. Marked `nonisolated` because
  /// ModelManager inherits MainActor isolation and hashing a 3 GB file on MainActor
  /// would freeze the UI.
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
}

// MARK: - Convenience (active-model wrappers)
//
// Lives in an extension so the primary class body stays under swiftlint's
// type_body_length cap. Callers can still invoke `modelManager.startActiveDownload()`
// / `cancelActiveDownload()` as if they were declared on the class itself.

extension ModelManager {
  /// Starts the download for the currently-active model. No-op if no active
  /// descriptor is resolvable (empty catalog). Preserves the old single-model
  /// `startDownload()` call-site ergonomics.
  func startActiveDownload() {
    guard let descriptor = activeDescriptor else { return }
    startDownload(descriptor: descriptor)
  }

  /// Cancels the download for the currently-active model, if any.
  func cancelActiveDownload() {
    guard let descriptor = activeDescriptor else { return }
    cancelDownload(descriptor: descriptor)
  }
}
