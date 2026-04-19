import Foundation
import Testing

@testable import Pastura

// MARK: - Mock

/// Mock that emits ONLY sub-1.0 progress callbacks and never a terminal
/// `received == total` callback. Mirrors production `URLSessionDownloadDelegate`
/// behavior: `didWriteData` is not guaranteed to fire one final time at 100%
/// after the last chunk — completion arrives via `didCompleteWithError(nil)`.
struct SubOneProgressMockDownloader: ModelDownloader, Sendable {
  let simulateBytes: Int64

  init(simulateBytes: Int64 = 1000) {
    self.simulateBytes = simulateBytes
  }

  func download(
    from url: URL,
    resumeOffset: Int64,
    to destination: URL,
    progressHandler: @Sendable @escaping (Int64, Int64) -> Void
  ) async throws {
    let data = Data(repeating: 0x42, count: Int(simulateBytes))
    try data.write(to: destination)
    // Emit only a mid-progress callback — never terminal 100%.
    progressHandler(simulateBytes / 2, simulateBytes)
  }
}

// MARK: - Tests

// Shares filesystem paths with the main suite, so serialize.
@Suite("ModelManager Progress", .serialized, .timeLimit(.minutes(1)))
@MainActor
struct ModelManagerProgressTests {

  @Test(
    "downloadModel reaches 100% even when downloader skips terminal callback"
  )
  func downloadCompletesWhenDownloaderSkipsTerminalProgress() async {
    // Production URLSession does not guarantee a terminal `didWriteData` call;
    // ModelManager must explicitly bring `state` to 1.0 before SHA256 verification
    // so the user sees 100% rather than stalling at the last sub-1.0 sample
    // during the ~2 s SHA256 hash on a 3 GB file.
    let sut = ModelManager(
      downloader: SubOneProgressMockDownloader(simulateBytes: 1000),
      // Skip size validation — the mock writes 1000 bytes, not the production 3.1 GB.
      expectedFileSize: 0,
      // Use SHA256 verification to exercise the post-download path that
      // includes the explicit `state = .downloading(progress: 1.0)` transition.
      expectedSHA256: "9a5670771141349931d69d6eb982faa01def544dc17a161ef83b3277fb7c0c3c"
    )
    // Pre-clean leftover files from any parallel suite (ModelManagerTests shares
    // these paths). Swift Testing runs suites in parallel by default; `.serialized`
    // only orders tests *within* a suite.
    try? FileManager.default.removeItem(at: sut.modelFileURL)
    try? FileManager.default.removeItem(at: sut.downloadFileURL)
    sut.checkModelStatus()
    #expect(sut.state == .notDownloaded)

    let snapshots = StateSnapshots()
    snapshots.startObserving(sut)

    await sut.downloadModel()
    defer {
      try? FileManager.default.removeItem(at: sut.modelFileURL)
      try? FileManager.default.removeItem(at: sut.downloadFileURL)
    }

    // Let the `StateSnapshots` re-arm Tasks settle. Progress callbacks were
    // already drained when `downloadModel()` returned, but the `withObservationTracking`
    // re-arm hops through `Task { @MainActor }`, so a few yields ensure any
    // post-`.ready` snapshot is recorded before we read `snapshots.progresses`.
    // Five yields is empirical headroom over the typical one-or-two it takes.
    for _ in 0..<5 { await Task.yield() }

    guard case .ready = sut.state else {
      Issue.record("Expected .ready but got \(sut.state)")
      return
    }

    let progresses = snapshots.progresses
    #expect(
      progresses.contains(where: { $0 >= 0.999 }),
      "Expected progress to reach 1.0 before .ready; observed \(progresses)"
    )
  }
}

// MARK: - Helpers

/// Re-arming `withObservationTracking` collector for `ModelManager.state`.
/// Each fired change records the current progress value (if any) and re-arms
/// tracking for the next change. Lives on MainActor because it reads/writes
/// `ModelManager.state`.
@MainActor
private final class StateSnapshots {
  private(set) var progresses: [Double] = []

  func startObserving(_ manager: ModelManager) {
    record(manager.state)
    withObservationTracking {
      _ = manager.state
    } onChange: { [weak self, weak manager] in
      // onChange fires synchronously on the mutating actor; re-arm via a Task
      // so the next mutation is captured.
      Task { @MainActor [weak self, weak manager] in
        guard let self, let manager else { return }
        self.startObserving(manager)
      }
    }
  }

  private func record(_ state: ModelState) {
    if case .downloading(let progress) = state {
      progresses.append(progress)
    }
  }
}
