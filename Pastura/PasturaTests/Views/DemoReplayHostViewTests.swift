import Foundation
import Testing

@testable import Pastura

// MARK: - DemoReplayHostView.fallbackBranch

// `DemoReplayHostView` is a View (implicitly @MainActor). `Branch` and
// `fallbackBranch` are declared inside it, so their Equatable conformance
// is also @MainActor-bound. The suite must run on the main actor.
@Suite("DemoReplayHostView", .serialized, .timeLimit(.minutes(1)))
@MainActor
struct DemoReplayHostViewTests {

  // MARK: - fallbackBranch: cellular takes priority

  @Test func cellularReturnsFallback_regardlessOfState() {
    // Cellular is the Option A safety net — overrides every other condition.
    let result = DemoReplayHostView.fallbackBranch(
      state: .downloading(progress: 0.5),
      demosCount: 10,
      replayHadStarted: true,
      isCellular: true)
    #expect(result == .modelDownload)
  }

  @Test func cellularReturnsFallback_evenWhenReady() {
    let result = DemoReplayHostView.fallbackBranch(
      state: .ready(modelPath: "x"),
      demosCount: 5,
      replayHadStarted: true,
      isCellular: true)
    #expect(result == .modelDownload)
  }

  // MARK: - fallbackBranch: pre-download states always fall back

  @Test func checkingReturnsFallback() {
    let result = DemoReplayHostView.fallbackBranch(
      state: .checking,
      demosCount: 10,
      replayHadStarted: true,
      isCellular: false)
    #expect(result == .modelDownload)
  }

  @Test func unsupportedDeviceReturnsFallback() {
    let result = DemoReplayHostView.fallbackBranch(
      state: .unsupportedDevice,
      demosCount: 10,
      replayHadStarted: true,
      isCellular: false)
    #expect(result == .modelDownload)
  }

  @Test func notDownloadedReturnsFallback() {
    let result = DemoReplayHostView.fallbackBranch(
      state: .notDownloaded,
      demosCount: 10,
      replayHadStarted: true,
      isCellular: false)
    #expect(result == .modelDownload)
  }

  // MARK: - fallbackBranch: .downloading with floor enforcement (spec §5.2)

  @Test func downloadingWithZeroDemosReturnsFallback() {
    let result = DemoReplayHostView.fallbackBranch(
      state: .downloading(progress: 0.5),
      demosCount: 0,
      replayHadStarted: false,
      isCellular: false)
    #expect(result == .modelDownload)
  }

  @Test func downloadingWithOneDemoReturnsFallback_belowFloor() {
    // spec §5.2: a single surviving demo is below the minPlayableDemoCount
    // floor (2). The rotation loop would be unsatisfying — defer to fallback.
    let result = DemoReplayHostView.fallbackBranch(
      state: .downloading(progress: 0.5),
      demosCount: 1,
      replayHadStarted: false,
      isCellular: false)
    #expect(result == .modelDownload)
  }

  @Test func downloadingWithTwoDemosReturnsDemoHost_atFloor() {
    let result = DemoReplayHostView.fallbackBranch(
      state: .downloading(progress: 0.5),
      demosCount: 2,
      replayHadStarted: false,
      isCellular: false)
    #expect(result == .demoHost)
  }

  @Test func downloadingWithFiveDemosReturnsDemoHost() {
    let result = DemoReplayHostView.fallbackBranch(
      state: .downloading(progress: 0.1),
      demosCount: 5,
      replayHadStarted: false,
      isCellular: false)
    #expect(result == .demoHost)
  }

  // MARK: - fallbackBranch: .error respects replayHadStarted (ADR-007 §3.3 (b))

  @Test func errorBeforeReplayStartedReturnsFallback() {
    let result = DemoReplayHostView.fallbackBranch(
      state: .error("network timeout"),
      demosCount: 5,
      replayHadStarted: false,
      isCellular: false)
    #expect(result == .modelDownload)
  }

  @Test func errorAfterReplayStartedReturnsDemoHost() {
    // Inline retry affordance in PromoCard keeps playback alive.
    let result = DemoReplayHostView.fallbackBranch(
      state: .error("network timeout"),
      demosCount: 5,
      replayHadStarted: true,
      isCellular: false)
    #expect(result == .demoHost)
  }

  // MARK: - fallbackBranch: .ready

  @Test func readyReturnsDemoHost() {
    let result = DemoReplayHostView.fallbackBranch(
      state: .ready(modelPath: "x"),
      demosCount: 0,
      replayHadStarted: false,
      isCellular: false)
    #expect(result == .demoHost)
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
