import Testing

@testable import Pastura

// `@MainActor` because `shouldGuardLeave` is a static on the default-MainActor
// `SimulationView`; the suite isolation lets a nonisolated caller reach it
// (`.claude/rules/swift-isolation.md` Pattern 5).
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct SimulationViewLeaveGuardTests {

  @Test func guardsWhenRunningNotPausedNotCompleted() {
    // The only state that risks a silent loss: an in-flight run the user hasn't
    // explicitly paused. Leaving it must be confirmed (#673).
    #expect(SimulationView.shouldGuardLeave(isRunning: true, isPaused: false, isCompleted: false))
  }

  @Test func noGuardWhenNotRunning() {
    #expect(!SimulationView.shouldGuardLeave(isRunning: false, isPaused: false, isCompleted: false))
  }

  @Test func noGuardWhenPaused() {
    // A paused run is already persisted as `.paused` — leaving loses nothing.
    #expect(!SimulationView.shouldGuardLeave(isRunning: true, isPaused: true, isCompleted: false))
  }

  @Test func noGuardWhenCompleted() {
    // A completed run has its terminal `.completed` row — nothing to confirm.
    #expect(!SimulationView.shouldGuardLeave(isRunning: true, isPaused: false, isCompleted: true))
  }

  // MARK: - Phase B opt-in leave routing (#682, ADR-017)

  @Test func leaveActionTruthTable() {
    // Not in flight → pop immediately regardless of the Setting.
    #expect(
      SimulationView.leaveAction(isGuarded: false, keepRunningEnabled: false) == .popImmediately)
    #expect(
      SimulationView.leaveAction(isGuarded: false, keepRunningEnabled: true) == .popImmediately)
    // In flight, Setting off → confirm dialog.
    #expect(SimulationView.leaveAction(isGuarded: true, keepRunningEnabled: false) == .showDialog)
    // In flight, Setting on → silent park (no dialog).
    #expect(
      SimulationView.leaveAction(isGuarded: true, keepRunningEnabled: true) == .silentKeepRunning)
  }

  @Test func disappearActionShortCircuitsHandledLeave() {
    // An explicit leave set `leaveHandled` → the trailing onDisappear ignores,
    // whatever the Setting / guard state. This is the critical double-fire guard.
    for keep in [true, false] {
      for guarded in [true, false] {
        #expect(
          SimulationView.disappearAction(
            leaveHandled: true, owns: true, keepRunningEnabled: keep, isGuarded: guarded) == .ignore
        )
      }
    }
  }

  @Test func disappearActionIgnoresUnownedRun() {
    #expect(
      SimulationView.disappearAction(
        leaveHandled: false, owns: false, keepRunningEnabled: true, isGuarded: true) == .ignore)
  }

  @Test func disappearActionParksOnlyWhenKeepRunningAndInFlight() {
    // Swipe-back, Setting on, in-flight → park.
    #expect(
      SimulationView.disappearAction(
        leaveHandled: false, owns: true, keepRunningEnabled: true, isGuarded: true) == .park)
    // Swipe-back, Setting on, NOT in-flight (paused/completed) → end, never park.
    #expect(
      SimulationView.disappearAction(
        leaveHandled: false, owns: true, keepRunningEnabled: true, isGuarded: false) == .end)
    // Swipe-back, Setting off, in-flight → end (today's cancel-on-disappear).
    #expect(
      SimulationView.disappearAction(
        leaveHandled: false, owns: true, keepRunningEnabled: false, isGuarded: true) == .end)
  }

  /// Each leave path yields **exactly one** terminal action — no kept run gets
  /// `end()`-ed, no `.paused` written twice (critic Axis 6). Modelled through
  /// the two pure deciders: explicit-leave paths set `leaveHandled` (verified by
  /// reading `confirmLeave` / `confirmLeaveKeepRunning`), so their trailing
  /// `onDisappear` resolves to `.ignore`; swipe-back paths leave it `false`.
  @Test func eachLeavePathHasExactlyOneTerminal() {
    // Back + Setting off + in-flight + "Pause and leave": dialog → confirmLeave
    // (terminal: pause, sets leaveHandled) → onDisappear ignores.
    #expect(SimulationView.leaveAction(isGuarded: true, keepRunningEnabled: false) == .showDialog)
    #expect(
      SimulationView.disappearAction(
        leaveHandled: true, owns: true, keepRunningEnabled: false, isGuarded: true) == .ignore,
      "Pause-and-leave's pop must not re-terminate (no double .paused)")

    // Back + Setting off + in-flight + "Leave & keep running": dialog →
    // confirmLeaveKeepRunning (terminal: park, sets leaveHandled) → ignore.
    // (Same disappearAction inputs as above — both dialog buttons set leaveHandled.)

    // Back + Setting on + in-flight: silentKeepRunning → confirmLeaveKeepRunning
    // (terminal: park, sets leaveHandled) → ignore.
    #expect(
      SimulationView.leaveAction(isGuarded: true, keepRunningEnabled: true) == .silentKeepRunning)
    #expect(
      SimulationView.disappearAction(
        leaveHandled: true, owns: true, keepRunningEnabled: true, isGuarded: true) == .ignore)

    // Swipe-back (no dialog) + Setting on + in-flight: terminal park.
    #expect(
      SimulationView.disappearAction(
        leaveHandled: false, owns: true, keepRunningEnabled: true, isGuarded: true) == .park)

    // Swipe-back + Setting off + in-flight: terminal end.
    #expect(
      SimulationView.disappearAction(
        leaveHandled: false, owns: true, keepRunningEnabled: false, isGuarded: true) == .end)
  }

  // MARK: - Premise reveal gate (#934, ADR-017 Phase B adopt path)

  @Test func premiseTypesOnFreshRunFirstReveal() {
    // Not a resume, reveal not yet begun → types at the playback speed.
    #expect(
      SimulationView.premiseCharsPerSecond(
        isResumeEntry: false, introRevealHasBegun: false, speedCharsPerSecond: 30) == 30)
  }

  @Test func premiseStaticOnceRevealHasBegun() {
    // The VM latch survives an adopt re-projection, so a returning parked run
    // renders the premise static instead of re-typing (#934).
    #expect(
      SimulationView.premiseCharsPerSecond(
        isResumeEntry: false, introRevealHasBegun: true, speedCharsPerSecond: 30) == nil)
  }

  @Test func premiseStaticOnResumeEntry() {
    // The checkpoint `.resume` path never plays the reveal beat, regardless of
    // the latch.
    #expect(
      SimulationView.premiseCharsPerSecond(
        isResumeEntry: true, introRevealHasBegun: false, speedCharsPerSecond: 30) == nil)
  }

  @Test func premiseStaticAtInstantSpeed() {
    // `.instant` passes `nil` cps → static even on a fresh first reveal.
    #expect(
      SimulationView.premiseCharsPerSecond(
        isResumeEntry: false, introRevealHasBegun: false, speedCharsPerSecond: nil) == nil)
  }
}
