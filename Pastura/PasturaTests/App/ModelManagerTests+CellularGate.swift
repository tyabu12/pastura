import Foundation
import Testing

@testable import Pastura

// MARK: - Tests (joins the serialized `ModelManagerTests` suite)
//
// Cellular consent gate (#191): `ModelManager.startDownload(descriptor:)`
// rejects when the network is cellular and the user has not yet granted
// one-time consent. The gate sets `pendingCellularConsent = descriptor`
// and lets the scene-level `.confirmationDialog` drive accept / decline.
//
// All tests inject `MockNetworkPathMonitor` + `MockCellularConsentStore`
// so the gate state is deterministic — no real `NWPathMonitor` callback
// races. Mocks are file-scope (mirrors `MockModelDownloader` in the base
// file).

extension ModelManagerTests {

  // MARK: - Gate Behavior

  @Test("startDownload sets pendingCellularConsent on cellular without consent")
  func startDownloadGatesOnCellular() {
    let monitor = MockNetworkPathMonitor(isCellular: true)
    let consent = MockCellularConsentStore(hasCellularConsent: false)
    let descriptor = makeTestDescriptor()
    let sut = makeSUT(
      catalog: [descriptor], networkPathMonitor: monitor, consentStore: consent)
    sut.checkModelStatus()
    #expect(sut.state[descriptor.id] == .notDownloaded)

    sut.startDownload(descriptor: descriptor)

    #expect(sut.pendingCellularConsent?.id == descriptor.id)
    #expect(sut.state[descriptor.id] == .notDownloaded)
    #expect(consent.hasCellularConsent == false)
  }

  @Test("startDownload bypasses gate on Wi-Fi (no cellular)")
  func startDownloadBypassesGateOnWifi() {
    let monitor = MockNetworkPathMonitor(isCellular: false)
    let consent = MockCellularConsentStore(hasCellularConsent: false)
    let descriptor = makeTestDescriptor()
    let sut = makeSUT(
      catalog: [descriptor], networkPathMonitor: monitor, consentStore: consent)
    sut.checkModelStatus()

    sut.startDownload(descriptor: descriptor)

    #expect(sut.pendingCellularConsent == nil)
    if case .downloading = sut.state[descriptor.id] {
    } else {
      Issue.record(
        "Expected .downloading state, got \(String(describing: sut.state[descriptor.id]))")
    }
  }

  @Test("startDownload bypasses gate when cellular consent already granted")
  func startDownloadBypassesGateWithConsent() {
    let monitor = MockNetworkPathMonitor(isCellular: true)
    let consent = MockCellularConsentStore(hasCellularConsent: true)
    let descriptor = makeTestDescriptor()
    let sut = makeSUT(
      catalog: [descriptor], networkPathMonitor: monitor, consentStore: consent)
    sut.checkModelStatus()

    sut.startDownload(descriptor: descriptor)

    #expect(sut.pendingCellularConsent == nil)
    if case .downloading = sut.state[descriptor.id] {
    } else {
      Issue.record(
        "Expected .downloading state, got \(String(describing: sut.state[descriptor.id]))")
    }
  }

  @Test("requiresCellularConsent reflects monitor + consent store state")
  func requiresCellularConsentAccessor() {
    let monitor = MockNetworkPathMonitor(isCellular: false)
    let consent = MockCellularConsentStore(hasCellularConsent: false)
    let sut = makeSUT(networkPathMonitor: monitor, consentStore: consent)
    #expect(sut.requiresCellularConsent == false)

    monitor.isCellular = true
    #expect(sut.requiresCellularConsent == true)

    consent.hasCellularConsent = true
    #expect(sut.requiresCellularConsent == false)
  }

  // MARK: - Accept / Decline

  @Test("acceptCellularConsent persists consent and resumes download")
  func acceptCellularConsentResumesDownload() {
    let monitor = MockNetworkPathMonitor(isCellular: true)
    let consent = MockCellularConsentStore(hasCellularConsent: false)
    let descriptor = makeTestDescriptor()
    let sut = makeSUT(
      catalog: [descriptor], networkPathMonitor: monitor, consentStore: consent)
    sut.checkModelStatus()
    sut.startDownload(descriptor: descriptor)
    #expect(sut.pendingCellularConsent?.id == descriptor.id)

    sut.acceptCellularConsent()

    #expect(consent.hasCellularConsent == true)
    #expect(sut.pendingCellularConsent == nil)
    if case .downloading = sut.state[descriptor.id] {
    } else {
      Issue.record(
        "Expected .downloading after accept, got \(String(describing: sut.state[descriptor.id]))")
    }
  }

  @Test("declineCellularConsent clears pending without persisting consent")
  func declineCellularConsentClearsPending() {
    let monitor = MockNetworkPathMonitor(isCellular: true)
    let consent = MockCellularConsentStore(hasCellularConsent: false)
    let descriptor = makeTestDescriptor()
    let sut = makeSUT(
      catalog: [descriptor], networkPathMonitor: monitor, consentStore: consent)
    sut.checkModelStatus()
    sut.startDownload(descriptor: descriptor)
    #expect(sut.pendingCellularConsent?.id == descriptor.id)

    sut.declineCellularConsent()

    #expect(sut.pendingCellularConsent == nil)
    #expect(consent.hasCellularConsent == false)
    #expect(sut.state[descriptor.id] == .notDownloaded)
  }

  @Test("acceptCellularConsent is a no-op when no pending request")
  func acceptCellularConsentNoOpWhenIdle() {
    let monitor = MockNetworkPathMonitor(isCellular: false)
    let consent = MockCellularConsentStore(hasCellularConsent: false)
    let sut = makeSUT(networkPathMonitor: monitor, consentStore: consent)
    sut.checkModelStatus()

    sut.acceptCellularConsent()

    #expect(consent.hasCellularConsent == false)
    #expect(sut.pendingCellularConsent == nil)
  }

  // MARK: - Multi-Row Guard

  @Test("startDownload for second row during pending consent is a no-op")
  func secondRowDownloadDuringPendingConsentIsNoop() {
    let monitor = MockNetworkPathMonitor(isCellular: true)
    let consent = MockCellularConsentStore(hasCellularConsent: false)
    let first = makeTestDescriptor(id: "a", fileName: "a.gguf")
    let second = makeTestDescriptor(id: "b", fileName: "b.gguf")
    let sut = makeSUT(
      catalog: [first, second], networkPathMonitor: monitor, consentStore: consent)
    sut.checkModelStatus()

    sut.startDownload(descriptor: first)
    #expect(sut.pendingCellularConsent?.id == first.id)

    sut.startDownload(descriptor: second)

    // Second tap must NOT overwrite pending consent for the first descriptor.
    #expect(sut.pendingCellularConsent?.id == first.id)
    #expect(sut.state[second.id] == .notDownloaded)
  }

  // MARK: - Sequential Gate vs Cellular Gate Ordering

  @Test("sequential gate takes priority — cellular gate does not fire when another DL is in flight")
  func sequentialGateTakesPriorityOverCellularGate() {
    let monitor = MockNetworkPathMonitor(isCellular: true)
    let consent = MockCellularConsentStore(hasCellularConsent: true)  // pre-consented
    let first = makeTestDescriptor(id: "a", fileName: "a.gguf")
    let second = makeTestDescriptor(id: "b", fileName: "b.gguf")
    let sut = makeSUT(
      catalog: [first, second], networkPathMonitor: monitor, consentStore: consent)
    sut.checkModelStatus()

    // First descriptor downloading (consented).
    sut.startDownload(descriptor: first)
    if case .downloading = sut.state[first.id] {
    } else {
      Issue.record("Expected first to be .downloading")
      return
    }

    // Now revoke consent and try a second download on cellular — sequential
    // gate should reject before the cellular gate gets a chance.
    consent.hasCellularConsent = false
    sut.startDownload(descriptor: second)

    // Sequential rejection: pending consent stays nil (we returned at the
    // sequential guard, before the cellular gate had a chance).
    #expect(sut.pendingCellularConsent == nil)
    #expect(sut.state[second.id] == .notDownloaded)
  }

  // MARK: - Retry After Error

  @Test("retry after error on cellular without consent re-fires the gate")
  func retryAfterErrorOnCellularRequiresConsent() async {
    // First attempt runs on Wi-Fi (gate bypassed) but the downloader throws,
    // landing the descriptor in `.error`. Then we flip the network to
    // cellular and retry — the gate must fire even though the descriptor's
    // current state is `.error`, since `PromoCard.onRetry` is one of the
    // entry points the centralized gate must catch.
    let monitor = MockNetworkPathMonitor(isCellular: false)
    let consent = MockCellularConsentStore(hasCellularConsent: false)
    let downloader = MockModelDownloader(error: URLError(.notConnectedToInternet))
    let descriptor = makeTestDescriptor()
    let sut = makeSUT(
      downloader: downloader,
      catalog: [descriptor],
      networkPathMonitor: monitor,
      consentStore: consent)
    sut.checkModelStatus()

    await sut.downloadModel(descriptor: descriptor)
    guard case .error = sut.state[descriptor.id] else {
      Issue.record(
        "Expected .error after failed download, got \(String(describing: sut.state[descriptor.id]))"
      )
      return
    }

    // Flip to cellular and retry — gate must intercept.
    monitor.isCellular = true
    sut.startDownload(descriptor: descriptor)

    #expect(sut.pendingCellularConsent?.id == descriptor.id)
    if case .error = sut.state[descriptor.id] {
    } else {
      Issue.record("Expected state to remain .error during pending consent")
    }
  }
}
