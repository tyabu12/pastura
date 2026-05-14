import Foundation
import Testing

@testable import Pastura

// Sibling extension of `URLSessionModelDownloaderTests` per testing.md split rule.
// Tests live in the SAME `@Suite` so they share the `.serialized` trait — critical
// because `CapturingMockURLProtocol`'s static configuration vector requires
// serialized access.

extension URLSessionModelDownloaderTests {

  // MARK: - Singleton refactor invariants

  @Test("URLSessionModelDownloader.shared is a process-wide singleton")
  func sharedReturnsSameInstance() {
    // Lazy `static let` semantics: two accesses return the same instance.
    // This guards against accidental re-construction (which would crash on
    // Apple's per-`.background(withIdentifier:)` identifier-uniqueness
    // constraint).
    let first = URLSessionModelDownloader.shared
    let second = URLSessionModelDownloader.shared
    #expect(first === second)
  }

  // MARK: - Orphan cleanup (PR1 item 2 prep)

  @Test("cancelInFlightTasks completes on a session with no in-flight tasks")
  func cancelInFlightTasksCompletesOnEmptySession() async {
    // Smoke test for the `getAllTasks` path. The session has no tasks
    // (no `download(...)` was ever called), so `getAllTasks` returns an
    // empty array and `cancelInFlightTasks` resumes immediately. Verifies
    // the URLSession plumbing doesn't deadlock or crash when there is
    // nothing to cancel — the common case at cold start when the user
    // has never started a BG download.
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [CapturingMockURLProtocol.self]
    let downloader = URLSessionModelDownloader(sessionConfiguration: config)
    await downloader.cancelInFlightTasks()
    // No assertions: the test passes if `await` returns.
  }

  @Test("two consecutive downloads on the same instance both succeed")
  func twoConsecutiveDownloadsSucceedOnSameInstance() async throws {
    // Regression guard for the singleton-session refactor: with the old
    // per-call URLSession pattern, `DownloadDelegate.didCompleteWithError`
    // called `session.finishTasksAndInvalidate()` on every completion. Under
    // a shared session, that would tear down the session after the first
    // download, breaking every subsequent call.
    //
    // The refactor removes the invalidate. This test exercises the
    // sequence-of-two contract that today's per-call pattern handled
    // trivially.
    CapturingMockURLProtocol.reset()
    defer { CapturingMockURLProtocol.reset() }

    let bodySize = 200
    CapturingMockURLProtocol.responseProvider = { _ in
      .success(
        statusCode: 200,
        headers: ["Content-Length": "\(bodySize)"],
        body: Data(repeating: 0x42, count: bodySize)
      )
    }

    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [CapturingMockURLProtocol.self]
    let downloader = URLSessionModelDownloader(sessionConfiguration: config)

    let url = URL(string: "https://example.com/model.gguf")!
    let destA = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString + ".download")
    let destB = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString + ".download")
    defer {
      try? FileManager.default.removeItem(at: destA)
      try? FileManager.default.removeItem(at: destB)
    }

    try await downloader.download(
      from: url, resumeOffset: 0, to: destA, progressHandler: { _, _ in })
    try await downloader.download(
      from: url, resumeOffset: 0, to: destB, progressHandler: { _, _ in })

    let attrsA = try FileManager.default.attributesOfItem(atPath: destA.path)
    let attrsB = try FileManager.default.attributesOfItem(atPath: destB.path)
    #expect((attrsA[.size] as? Int64) == Int64(bodySize))
    #expect((attrsB[.size] as? Int64) == Int64(bodySize))
  }

  // MARK: - attachToInFlight (PR2 item 2)

  @Test("attachToInFlight on a session with no in-flight tasks returns empty map")
  func attachToInFlightOnEmptySessionReturnsEmpty() async {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [CapturingMockURLProtocol.self]
    let downloader = URLSessionModelDownloader(sessionConfiguration: config)
    let map = await downloader.attachToInFlight()
    #expect(map.isEmpty)
  }

  // MARK: - cancel(url:) (PR2 item 2)

  @Test("cancel(url:) on a URL with no matching task is a safe no-op")
  func cancelUnknownURLIsNoOp() async {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [CapturingMockURLProtocol.self]
    let downloader = URLSessionModelDownloader(sessionConfiguration: config)
    await downloader.cancel(url: URL(string: "https://example.com/missing.gguf")!)
    // No assertion: the test passes if `await` returns and the resume-data
    // cache stays empty (no spurious blob writes).
    #expect(
      downloader.cachedResumeData(for: URL(string: "https://example.com/missing.gguf")!) == nil)
  }
}
