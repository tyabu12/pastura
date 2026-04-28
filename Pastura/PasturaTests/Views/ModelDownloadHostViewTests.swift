import Foundation
import Testing

@testable import Pastura

// MARK: - ModelDownloadHostView.stateView

// `ModelDownloadHostView` is a View (implicitly @MainActor). `StateView` and
// `stateView` are declared inside it, so their Equatable conformance is
// also @MainActor-bound. The suite must run on the main actor.
@Suite("ModelDownloadHostView", .serialized, .timeLimit(.minutes(1)))
@MainActor
struct ModelDownloadHostViewTests {

  // MARK: - stateView: pre-download states (no cellular consent dependency)

  @Test func checkingReturnsCheckingFallback() {
    let result = ModelDownloadHostView.stateView(
      state: .checking,
      demosCount: 10,
      replayHadStarted: true,
      requiresCellularConsent: false)
    #expect(result == .checking)
  }

  @Test func unsupportedDeviceReturnsUnsupportedDeviceFallback() {
    let result = ModelDownloadHostView.stateView(
      state: .unsupportedDevice,
      demosCount: 10,
      replayHadStarted: true,
      requiresCellularConsent: false)
    #expect(result == .unsupportedDevice)
  }

  // MARK: - stateView: .notDownloaded splits on cellular consent

  @Test func notDownloadedWithCellularConsentRequired_returnsWifiRequired() {
    // Cellular gate fired in ModelManager.startDownload — show the
    // Wi-Fi advisory with a Try Again button (#191 / ADR-007 §3.3 (c)).
    let result = ModelDownloadHostView.stateView(
      state: .notDownloaded,
      demosCount: 10,
      replayHadStarted: true,
      requiresCellularConsent: true)
    #expect(result == .wifiRequired)
  }

  @Test func notDownloadedWithoutCellularConsent_returnsDefensive() {
    // Defensive escape hatch — auto-DL trigger paths normally flip
    // straight to .downloading on Wi-Fi, so this case only fires when
    // the sequential-download policy rejected the call.
    let result = ModelDownloadHostView.stateView(
      state: .notDownloaded,
      demosCount: 10,
      replayHadStarted: false,
      requiresCellularConsent: false)
    #expect(result == .notDownloadedDefensive)
  }

  // MARK: - stateView: .downloading with floor enforcement (spec §5.2)

  @Test func downloadingWithZeroDemosReturnsPlainProgress() {
    let result = ModelDownloadHostView.stateView(
      state: .downloading(progress: 0.5),
      demosCount: 0,
      replayHadStarted: false,
      requiresCellularConsent: false)
    #expect(result == .plainProgress)
  }

  @Test func downloadingWithOneDemoReturnsPlainProgress_belowFloor() {
    // spec §5.2: a single surviving demo is below the minPlayableDemoCount
    // floor (2). The rotation loop would be unsatisfying — render the
    // plain progress fallback inline instead.
    let result = ModelDownloadHostView.stateView(
      state: .downloading(progress: 0.5),
      demosCount: 1,
      replayHadStarted: false,
      requiresCellularConsent: false)
    #expect(result == .plainProgress)
  }

  @Test func downloadingWithTwoDemosReturnsDemoHost_atFloor() {
    let result = ModelDownloadHostView.stateView(
      state: .downloading(progress: 0.5),
      demosCount: 2,
      replayHadStarted: false,
      requiresCellularConsent: false)
    #expect(result == .demoHost)
  }

  @Test func downloadingWithFiveDemosReturnsDemoHost() {
    let result = ModelDownloadHostView.stateView(
      state: .downloading(progress: 0.1),
      demosCount: 5,
      replayHadStarted: false,
      requiresCellularConsent: false)
    #expect(result == .demoHost)
  }

  // MARK: - stateView: .error respects replayHadStarted (ADR-007 §3.3 (b))

  @Test func errorBeforeReplayStartedReturnsPlainError() {
    let result = ModelDownloadHostView.stateView(
      state: .error("network timeout"),
      demosCount: 5,
      replayHadStarted: false,
      requiresCellularConsent: false)
    #expect(result == .error(message: "network timeout"))
  }

  @Test func errorAfterReplayStartedReturnsDemoHost() {
    // Inline retry affordance in PromoCard keeps playback alive.
    let result = ModelDownloadHostView.stateView(
      state: .error("network timeout"),
      demosCount: 5,
      replayHadStarted: true,
      requiresCellularConsent: false)
    #expect(result == .demoHost)
  }

  // MARK: - stateView: .ready

  @Test func readyReturnsDemoHost() {
    let result = ModelDownloadHostView.stateView(
      state: .ready(modelPath: "x"),
      demosCount: 0,
      replayHadStarted: false,
      requiresCellularConsent: false)
    #expect(result == .demoHost)
  }

  // MARK: - stateView: cellular consent does NOT short-circuit other states

  @Test func cellularConsentDoesNotAffectDownloadingDispatch() {
    // Once the gate is passed (state has reached .downloading), the
    // cellular flag is irrelevant — demo replay should play even on
    // a still-cellular network because the user accepted consent.
    let result = ModelDownloadHostView.stateView(
      state: .downloading(progress: 0.5),
      demosCount: 5,
      replayHadStarted: false,
      requiresCellularConsent: true)
    #expect(result == .demoHost)
  }

  @Test func cellularConsentDoesNotAffectReadyDispatch() {
    let result = ModelDownloadHostView.stateView(
      state: .ready(modelPath: "x"),
      demosCount: 5,
      replayHadStarted: true,
      requiresCellularConsent: true)
    #expect(result == .demoHost)
  }

  // MARK: - readyDispatch: Settings cover path

  @Test func settingsCover_dispatchesFireOnComplete() {
    // Settings cover passes `showsCompleteOverlay: false` and dismisses
    // immediately on `.ready` — VM presence doesn't matter.
    let result = ModelDownloadHostView.readyDispatch(
      showsCompleteOverlay: false,
      hasReplayVM: true)
    #expect(result == .fireOnComplete)
  }

  @Test func settingsCover_dispatchesFireOnComplete_evenWithoutVM() {
    let result = ModelDownloadHostView.readyDispatch(
      showsCompleteOverlay: false,
      hasReplayVM: false)
    #expect(result == .fireOnComplete)
  }

  // MARK: - readyDispatch: first-launch slot, no overlay rendered

  @Test func firstLaunchNoVM_firesImmediately_doesNotAwaitTap() {
    // Cellular safety net or sub-floor demo count — `replayVM` is nil so
    // the overlay never renders. No tap surface available; fire onReady
    // directly. Issue #202 critical: don't strand the user with no
    // visible UI to tap.
    let result = ModelDownloadHostView.readyDispatch(
      showsCompleteOverlay: true,
      hasReplayVM: false)
    #expect(result == .fireOnReady(awaitsTap: false))
  }

  // MARK: - readyDispatch: first-launch slot, overlay rendered

  @Test func firstLaunchWithVM_awaitsTap() {
    // Normal path — overlay renders, user must tap it to acknowledge
    // "Ready" and proceed to HomeView. No timer — explicit user action
    // (per real-device QA: auto-transition felt jarring; user wakes up
    // on home screen with no clear "setup complete" beat).
    let result = ModelDownloadHostView.readyDispatch(
      showsCompleteOverlay: true,
      hasReplayVM: true)
    #expect(result == .fireOnReady(awaitsTap: true))
  }
}

// MARK: - PromoCard.computeSlotState

@Suite("PromoCard.computeSlotState", .serialized, .timeLimit(.minutes(1)))
struct PromoCardComputeSlotStateTests {

  let now = Date(timeIntervalSince1970: 1_000_000)

  // MARK: - Slot stays when not enough time has passed

  @Test func stillInsideSlot_slotUnchanged() {
    // foregroundElapsed=10, inflight=5 → total=15 < slotDuration=20
    let anchor = now.addingTimeInterval(-5)
    let result = PromoCard.computeSlotState(
      previousSlot: 0,
      foregroundElapsed: 10,
      lastAnchor: anchor,
      now: now,
      slotDuration: 20)
    #expect(result.slot == 0)
    #expect(result.foregroundElapsed == 10)
    #expect(result.lastAnchor == anchor)
  }

  // MARK: - Slot advances exactly at boundary

  @Test func exactlyAtBoundary_slotAdvances() {
    // foregroundElapsed=0, inflight=20 → total=20 == slotDuration=20
    let anchor = now.addingTimeInterval(-20)
    let result = PromoCard.computeSlotState(
      previousSlot: 0,
      foregroundElapsed: 0,
      lastAnchor: anchor,
      now: now,
      slotDuration: 20)
    #expect(result.slot == 1)
    #expect(result.foregroundElapsed == 0)
    // Anchor resets to `now` when foregrounded.
    #expect(result.lastAnchor == now)
  }

  // MARK: - Background pause: anchor nil, no advancement

  @Test func bgPauseMidSlot_slotUnchanged_elapsedPreserved() {
    // lastAnchor = nil → inflight = 0. No time accumulates while BG.
    let result = PromoCard.computeSlotState(
      previousSlot: 1,
      foregroundElapsed: 10,
      lastAnchor: nil,
      now: now,
      slotDuration: 20)
    #expect(result.slot == 1)
    #expect(result.foregroundElapsed == 10)
    #expect(result.lastAnchor == nil)
  }

  @Test func bgPause_withInsufficientForegroundElapsed_slotUnchanged() {
    // foregroundElapsed=10 < slotDuration=20, anchor=nil (BG) → inflight=0.
    // total = 10 < 20 → slot does not advance.
    let result = PromoCard.computeSlotState(
      previousSlot: 0,
      foregroundElapsed: 10,
      lastAnchor: nil,
      now: now,
      slotDuration: 20)
    #expect(result.slot == 0)
    #expect(result.foregroundElapsed == 10)
    #expect(result.lastAnchor == nil)
  }

  // MARK: - Resume after BG: anchor set to now, inflight accumulates

  @Test func resumeAfterBG_slotAdvancesWhenTotalReachesDuration() {
    // Simulates: BG with foregroundElapsed=15 accumulated, then FG sets
    // lastAnchor=now. After 5s inflight (anchor = now - 5), total = 20.
    let anchor = now.addingTimeInterval(-5)
    let result = PromoCard.computeSlotState(
      previousSlot: 0,
      foregroundElapsed: 15,
      lastAnchor: anchor,
      now: now,
      slotDuration: 20)
    #expect(result.slot == 1)
    #expect(result.foregroundElapsed == 0)
    #expect(result.lastAnchor == now)
  }

  @Test func resumeAfterBG_slotDoesNotAdvanceWhenInsufficientInflight() {
    // BG accumulated foregroundElapsed=15, but only 3s inflight after FG.
    // total = 18 < 20 → no advance.
    let anchor = now.addingTimeInterval(-3)
    let result = PromoCard.computeSlotState(
      previousSlot: 2,
      foregroundElapsed: 15,
      lastAnchor: anchor,
      now: now,
      slotDuration: 20)
    #expect(result.slot == 2)
    #expect(result.foregroundElapsed == 15)
    #expect(result.lastAnchor == anchor)
  }

  // MARK: - Wrap-around 0 → 1 → 2 → 0

  @Test func wrapAround_threeAdvancements_returnToSlotZero() {
    // Each call represents a tick exactly at the boundary (inflight = slotDuration).
    // Call 1: 0 → 1
    var anchor: Date? = now.addingTimeInterval(-20)
    let result1 = PromoCard.computeSlotState(
      previousSlot: 0, foregroundElapsed: 0,
      lastAnchor: anchor, now: now, slotDuration: 20)
    #expect(result1.slot == 1)

    // Call 2: 1 → 2 (reset anchor to now, then advance again 20s later)
    let now2 = now.addingTimeInterval(20)
    anchor = result1.lastAnchor  // = now after slot advance
    let result2 = PromoCard.computeSlotState(
      previousSlot: result1.slot, foregroundElapsed: result1.foregroundElapsed,
      lastAnchor: anchor, now: now2, slotDuration: 20)
    #expect(result2.slot == 2)

    // Call 3: 2 → 0 (mod 3 wrap-around)
    let now3 = now2.addingTimeInterval(20)
    anchor = result2.lastAnchor  // = now2 after slot advance
    let result3 = PromoCard.computeSlotState(
      previousSlot: result2.slot, foregroundElapsed: result2.foregroundElapsed,
      lastAnchor: anchor, now: now3, slotDuration: 20)
    #expect(result3.slot == 0)
  }

  // MARK: - Wrap-around with BG in the middle

  @Test func wrapAroundWithBGInMiddle_anchorStaysNilThroughSlotBoundary() {
    // Slot 1 accumulated 30s foreground, goes BG (anchor=nil).
    // While BG a tick fires: total = foregroundElapsed + 0 = 30 >= slotDuration=20.
    // Slot should advance to 2, anchor must stay nil (BG).
    let result = PromoCard.computeSlotState(
      previousSlot: 1,
      foregroundElapsed: 30,
      lastAnchor: nil,
      now: now,
      slotDuration: 20)
    #expect(result.slot == 2)
    #expect(result.foregroundElapsed == 0)
    #expect(result.lastAnchor == nil, "Anchor must remain nil while backgrounded")

    // Simulate FG return: `handleScenePhase(.active)` sets anchor = now.
    // After slotDuration inflight, slot advances again (2 → 0).
    let fgNow = now.addingTimeInterval(20)
    let result2 = PromoCard.computeSlotState(
      previousSlot: result.slot,
      foregroundElapsed: result.foregroundElapsed,
      lastAnchor: fgNow.addingTimeInterval(-20),  // anchor set at FG return
      now: fgNow,
      slotDuration: 20)
    #expect(result2.slot == 0)
    #expect(result2.lastAnchor == fgNow)
  }
}
