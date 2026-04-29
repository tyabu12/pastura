import Foundation
import Testing
import os

@testable import Pastura

// MARK: - Mock
//
// Mock that records every `resumeOffset` it sees, and on the first call writes
// `bytesOnFirstCall` bytes to the destination before throwing. Used to verify
// that `ModelManager.performDownload` reads the partial-file size from disk on
// retry and forwards it as `resumeOffset` to the next downloader call.

final class ResumeOffsetRecordingDownloader: ModelDownloader, @unchecked Sendable {
  // @unchecked Sendable: mutable state guarded by `OSAllocatedUnfairLock`.
  private let lock: OSAllocatedUnfairLock<State>

  struct State {
    var capturedResumeOffsets: [Int64] = []
  }

  let bytesOnFirstCall: Int64
  let error: any Error & Sendable

  init(bytesOnFirstCall: Int64, error: any Error & Sendable) {
    self.bytesOnFirstCall = bytesOnFirstCall
    self.error = error
    self.lock = OSAllocatedUnfairLock(initialState: State())
  }

  var capturedResumeOffsets: [Int64] {
    lock.withLock { $0.capturedResumeOffsets }
  }

  func download(
    from url: URL,
    resumeOffset: Int64,
    to destination: URL,
    progressHandler: @Sendable @escaping (Int64, Int64) -> Void
  ) async throws {
    let callIndex = lock.withLock { state -> Int in
      state.capturedResumeOffsets.append(resumeOffset)
      return state.capturedResumeOffsets.count - 1
    }

    if callIndex == 0 {
      // First call — leave partial bytes on disk so ModelManager's next
      // performDownload sees a non-zero resumeOffset from the partial file.
      let data = Data(repeating: 0x42, count: Int(bytesOnFirstCall))
      try data.write(to: destination)
    }
    // Always throw — we only care about resumeOffset capture, not finalization.
    throw error
  }
}

// MARK: - Test (joins the serialized `ModelManagerTests` suite)
//
// Extension on the existing `ModelManagerTests` struct keeps this test inside
// the parent `.serialized` suite — see `.claude/rules/testing.md`. A standalone
// `@Suite` would race against the parent on shared filesystem paths
// (Application Support / Caches), passing locally but failing on CI's slower
// runner.

extension ModelManagerTests {

  @Test(
    "performDownload reads resumeOffset from partial .download file size on retry"
  )
  func performDownloadReadsResumeOffsetFromPartialFile() async {
    let descriptor = makeTestDescriptor()
    let recorder = ResumeOffsetRecordingDownloader(
      bytesOnFirstCall: 250,
      error: URLError(.timedOut)
    )
    let sut = makeSUT(downloader: recorder, catalog: [descriptor])
    sut.checkModelStatus()

    // First attempt — fails after writing 250 bytes to .download
    await sut.downloadModel(descriptor: descriptor)
    guard case .error = sut.activeState else {
      Issue.record("Expected .error after first attempt, got \(sut.activeState)")
      return
    }

    let partialURL = sut.downloadFileURL(for: descriptor)
    let partialAttrs = try? FileManager.default.attributesOfItem(atPath: partialURL.path)
    #expect((partialAttrs?[.size] as? Int64) == 250)

    // Second attempt — verifies ModelManager reads the partial-file size and
    // forwards it as the new resumeOffset.
    await sut.downloadModel(descriptor: descriptor)

    let offsets = recorder.capturedResumeOffsets
    #expect(
      offsets == [0, 250],
      "Expected first call resumeOffset=0, retry resumeOffset=250; got \(offsets)"
    )

    // Cleanup
    try? FileManager.default.removeItem(at: sut.modelFileURL(for: descriptor))
    try? FileManager.default.removeItem(at: partialURL)
  }
}
