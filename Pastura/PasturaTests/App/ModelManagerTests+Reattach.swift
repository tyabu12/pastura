import Foundation
import Testing
import os

@testable import Pastura

// Sibling extension of `ModelManagerTests` per testing.md split rule.
// Tests live in the SAME `@Suite` as `ModelManagerTests` so they share its
// `.serialized` trait — required because the underlying mocks and the
// SUT's filesystem paths overlap across tests.

// MARK: - AttachStub helper

/// Test downloader that returns a synthesized `attachToInFlight` map and
/// records per-URL `cancel(url:)` invocations. Test code retains the
/// continuations so it can drive the streams forward with synthesized
/// `.progress` / `.completed` / `.failed` events.
final class AttachStubDownloader: ModelDownloader, @unchecked Sendable {
  // @unchecked Sendable: mutable state is guarded by OSAllocatedUnfairLock.
  let attachMap: [URL: AsyncStream<DownloadEvent>]
  let continuations: [URL: AsyncStream<DownloadEvent>.Continuation]
  let cancelledURLs: OSAllocatedUnfairLock<[URL]> = .init(initialState: [])

  init(urls: [URL]) {
    var attachMap: [URL: AsyncStream<DownloadEvent>] = [:]
    var continuations: [URL: AsyncStream<DownloadEvent>.Continuation] = [:]
    for url in urls {
      let (stream, continuation) = AsyncStream<DownloadEvent>.makeStream()
      attachMap[url] = stream
      continuations[url] = continuation
    }
    self.attachMap = attachMap
    self.continuations = continuations
  }

  func download(
    from url: URL,
    resumeOffset: Int64,
    to destination: URL,
    progressHandler: @Sendable @escaping (Int64, Int64) -> Void
  ) async throws {
    // Not exercised in attach tests.
  }

  func attachToInFlight() async -> [URL: AsyncStream<DownloadEvent>] {
    attachMap
  }

  func cancel(url: URL) async {
    cancelledURLs.withLock { $0.append(url) }
    if let continuation = continuations[url] {
      continuation.yield(.failed(URLError(.cancelled)))
      continuation.finish()
    }
  }

  // MARK: - Test API

  /// Yields a synthesized event to the stream for `url`. Tests use this to
  /// drive the observer Task without spinning up real URLSession.
  func emit(_ event: DownloadEvent, for url: URL) {
    continuations[url]?.yield(event)
  }

  /// Finishes the stream for `url` so the observer Task exits.
  func finish(_ url: URL) {
    continuations[url]?.finish()
  }
}

// MARK: - Tests

extension ModelManagerTests {

  // MARK: - attachToInFlightDownloads — catalog matching

  @Test("attachToInFlightDownloads transitions catalog-matched .notDownloaded → .downloading")
  func attachTransitionsCatalogMatchedToDownloading() async {
    let descriptor = makeTestDescriptor()
    let downloader = AttachStubDownloader(urls: [descriptor.downloadURL])
    let sut = makeSUT(
      downloader: downloader,
      catalog: [descriptor],
      networkPathMonitor: MockNetworkPathMonitor(isCellular: false),
      consentStore: MockCellularConsentStore(hasCellularConsent: false)
    )
    sut.checkModelStatus()
    #expect(sut.state[descriptor.id] == .notDownloaded)

    await sut.attachToInFlightDownloads()

    if case .downloading(let progress) = sut.state[descriptor.id] {
      #expect(p == 0.0)
    } else {
      Issue.record(
        "expected .downloading state, got \(String(describing: sut.state[descriptor.id]))")
    }
    #expect(downloader.cancelledURLs.withLock { $0 }.isEmpty)
    downloader.finish(descriptor.downloadURL)  // tidy
  }

  @Test("attachToInFlightDownloads cancels catalog-miss URLs without touching state")
  func attachCancelsCatalogMissURLs() async {
    let descriptor = makeTestDescriptor()
    let strayURL = URL(string: "https://example.com/unknown-model.gguf")!
    let downloader = AttachStubDownloader(urls: [strayURL])
    let sut = makeSUT(
      downloader: downloader, catalog: [descriptor],
      networkPathMonitor: MockNetworkPathMonitor(isCellular: false),
      consentStore: MockCellularConsentStore(hasCellularConsent: false)
    )
    sut.checkModelStatus()
    let stateBefore = sut.state[descriptor.id]

    await sut.attachToInFlightDownloads()

    #expect(sut.state[descriptor.id] == stateBefore)
    #expect(downloader.cancelledURLs.withLock { $0 } == [strayURL])
  }

  // MARK: - Cellular re-evaluation (PR2 item 5)

  @Test(
    "attachToInFlightDownloads on cellular without consent cancels + sets pendingCellularConsent")
  func attachCellularNoConsentCancelsAndPromptsForConsent() async {
    let descriptor = makeTestDescriptor()
    let downloader = AttachStubDownloader(urls: [descriptor.downloadURL])
    let sut = makeSUT(
      downloader: downloader, catalog: [descriptor],
      networkPathMonitor: MockNetworkPathMonitor(isCellular: true),
      consentStore: MockCellularConsentStore(hasCellularConsent: false)
    )
    sut.checkModelStatus()
    #expect(sut.pendingCellularConsent == nil)

    await sut.attachToInFlightDownloads()

    #expect(downloader.cancelledURLs.withLock { $0 } == [descriptor.downloadURL])
    #expect(sut.state[descriptor.id] == .notDownloaded)
    #expect(sut.pendingCellularConsent?.id == descriptor.id)
  }

  @Test("attachToInFlightDownloads on cellular WITH consent proceeds to .downloading")
  func attachCellularWithConsentProceeds() async {
    let descriptor = makeTestDescriptor()
    let downloader = AttachStubDownloader(urls: [descriptor.downloadURL])
    let sut = makeSUT(
      downloader: downloader, catalog: [descriptor],
      networkPathMonitor: MockNetworkPathMonitor(isCellular: true),
      consentStore: MockCellularConsentStore(hasCellularConsent: true)
    )
    sut.checkModelStatus()

    await sut.attachToInFlightDownloads()

    if case .downloading = sut.state[descriptor.id] {
      // pass
    } else {
      Issue.record("expected .downloading on cellular+consent path")
    }
    #expect(sut.pendingCellularConsent == nil)
    #expect(downloader.cancelledURLs.withLock { $0 }.isEmpty)
    downloader.finish(descriptor.downloadURL)
  }

  // MARK: - Observer event handling

  @Test("observer .progress event updates descriptor state.progress")
  func observerProgressUpdatesState() async throws {
    let descriptor = makeTestDescriptor()
    let downloader = AttachStubDownloader(urls: [descriptor.downloadURL])
    let sut = makeSUT(
      downloader: downloader, catalog: [descriptor],
      networkPathMonitor: MockNetworkPathMonitor(isCellular: false),
      consentStore: MockCellularConsentStore(hasCellularConsent: false)
    )
    sut.checkModelStatus()
    await sut.attachToInFlightDownloads()

    downloader.emit(.progress(0.42), for: descriptor.downloadURL)
    // Yield until the observer Task processes the event.
    try await Task.sleep(nanoseconds: 50_000_000)

    if case .downloading(let progress) = sut.state[descriptor.id] {
      #expect(p == 0.42)
    } else {
      Issue.record("expected .downloading(0.42)")
    }
    downloader.finish(descriptor.downloadURL)
  }

  @Test("observer .failed (non-cancel) transitions descriptor to .error")
  func observerFailedTransitionsToError() async throws {
    let descriptor = makeTestDescriptor()
    let downloader = AttachStubDownloader(urls: [descriptor.downloadURL])
    let sut = makeSUT(
      downloader: downloader, catalog: [descriptor],
      networkPathMonitor: MockNetworkPathMonitor(isCellular: false),
      consentStore: MockCellularConsentStore(hasCellularConsent: false)
    )
    sut.checkModelStatus()
    await sut.attachToInFlightDownloads()

    downloader.emit(.failed(URLError(.networkConnectionLost)), for: descriptor.downloadURL)
    downloader.finish(descriptor.downloadURL)
    try await Task.sleep(nanoseconds: 50_000_000)

    if case .error = sut.state[descriptor.id] {
      // pass
    } else {
      Issue.record(
        "expected .error after .failed event, got \(String(describing: sut.state[descriptor.id]))")
    }
  }

  @Test("observer .failed(.cancelled) maps to .notDownloaded")
  func observerCancelledMapsToNotDownloaded() async throws {
    let descriptor = makeTestDescriptor()
    let downloader = AttachStubDownloader(urls: [descriptor.downloadURL])
    let sut = makeSUT(
      downloader: downloader, catalog: [descriptor],
      networkPathMonitor: MockNetworkPathMonitor(isCellular: false),
      consentStore: MockCellularConsentStore(hasCellularConsent: false)
    )
    sut.checkModelStatus()
    await sut.attachToInFlightDownloads()

    downloader.emit(.failed(URLError(.cancelled)), for: descriptor.downloadURL)
    downloader.finish(descriptor.downloadURL)
    try await Task.sleep(nanoseconds: 50_000_000)

    #expect(sut.state[descriptor.id] == .notDownloaded)
  }
}
