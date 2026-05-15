import Foundation
import Testing

@testable import Pastura

@Suite("ModelDownloader Protocol API", .timeLimit(.minutes(1)))
struct ModelDownloaderProtocolTests {

  /// Bare-minimum conformance that implements ONLY `download(...)` — verifies
  /// the protocol-extension default impls for `attachToInFlight()` /
  /// `cancel(url:)` make the new API safe to adopt for test doubles.
  struct BareMockDownloader: ModelDownloader, Sendable {
    func download(
      from url: URL,
      resumeOffset: Int64,
      to destination: URL,
      progressHandler: @Sendable @escaping (Int64, Int64) -> Void
    ) async throws {}
  }

  @Test func defaultAttachToInFlightReturnsEmpty() async {
    let mock = BareMockDownloader()
    let result = await mock.attachToInFlight()
    #expect(result.isEmpty)
  }

  @Test func defaultCancelURLDoesNotCrash() async {
    let mock = BareMockDownloader()
    await mock.cancel(url: URL(string: "https://example.com/missing")!)
    // No assertion — the only failure mode is crash/throw. Reaching here is the success criterion.
  }

  @Test func downloadEventEnumExhaustiveSwitch() {
    let progress: DownloadEvent = .progress(0.5)
    let completed: DownloadEvent = .completed(modelURL: URL(string: "file:///tmp/x")!)
    let failed: DownloadEvent = .failed(URLError(.cancelled))

    func label(_ event: DownloadEvent) -> String {
      switch event {
      case .progress: return "progress"
      case .completed: return "completed"
      case .failed: return "failed"
      }
    }

    #expect(label(progress) == "progress")
    #expect(label(completed) == "completed")
    #expect(label(failed) == "failed")
  }

  @Test func downloadEventProgressPayload() {
    let event: DownloadEvent = .progress(0.42)
    guard case .progress(let value) = event else {
      Issue.record("expected .progress case")
      return
    }
    #expect(value == 0.42)
  }

  @Test func downloadEventCompletedPayload() {
    let url = URL(string: "file:///tmp/staged.gguf.tmp")!
    let event: DownloadEvent = .completed(modelURL: url)
    guard case .completed(let modelURL) = event else {
      Issue.record("expected .completed case")
      return
    }
    #expect(modelURL == url)
  }

  @Test func downloadEventFailedPayload() {
    let err = URLError(.timedOut)
    let event: DownloadEvent = .failed(err)
    guard case .failed(let error) = event else {
      Issue.record("expected .failed case")
      return
    }
    #expect((error as? URLError)?.code == .timedOut)
  }

  /// AsyncStream<DownloadEvent> is the public contract for `attachToInFlight()` —
  /// this test exists so a regression that breaks Sendable conformance on
  /// `DownloadEvent` (e.g., adding a non-Sendable associated value) fails
  /// here rather than at a downstream callsite.
  @Test func downloadEventIsSendableUsableInAsyncStream() async {
    let stream = AsyncStream<DownloadEvent> { continuation in
      continuation.yield(.progress(0.5))
      continuation.yield(.completed(modelURL: URL(string: "file:///tmp/x")!))
      continuation.finish()
    }
    var collected: [DownloadEvent] = []
    for await event in stream {
      collected.append(event)
    }
    #expect(collected.count == 2)
  }
}
