import Testing

@testable import Pastura

/// Captures both the wall-clock duration and the eventual throw of a probed
/// `generate` / `generateStream` call so timing-sensitive cooperative-wait
/// assertions stay independent of the test's own `Task.sleep` durations.
private struct GenerateProbe: Sendable {
  let elapsed: Duration
  let error: (any Error)?
}

/// Warmup duration: lets spawned probe tasks reach `acquireGenerateGuard`'s
/// poll before the flag-clear window opens. Without it, a heavily-loaded CI
/// runner can delay Task scheduling past the 100 ms hold and the probe
/// would observe `flag == false` on its very first poll, defeating the
/// wait-exercise the test is supposed to perform.
private let probeWarmup: Duration = .milliseconds(20)

/// Issue #221 regression — `generate()` / `generateStream()` must cooperatively
/// wait at entry when a prior call's `generatingGuard` is still set, instead
/// of `precondition`-trapping on the back-to-back back-nav → restart path.
/// Sibling extension to keep `LlamaCppServiceTests.swift` under swiftlint's
/// 400-line `file_length` cap. See `.claude/rules/testing.md` "Splitting a
/// Suite Across Files" — DO NOT promote to a separate `@Suite` (would race the
/// parent suite on shared file-system paths).
extension LlamaCppServiceTests {

  // MARK: - generate cooperative wait (Issue #221)

  @Test func generateWaitsForInFlightGenerate() async throws {
    // Without the cooperative wait, `generate` throws `.notLoaded` immediately
    // (the test service has no model loaded). With it, `generate` blocks on
    // `awaitGenerateIdle` until the flag is cleared at the 100ms mark, then
    // proceeds to throw `.notLoaded`. `isCancelled` cannot distinguish these
    // two cases (the task isn't cancelled in either) — wall-clock elapsed
    // measured inside the Task body is the signal.
    let service = makeTestService()
    service.setGeneratingForTesting(true)

    let start = ContinuousClock.now
    let generateTask = Task<GenerateProbe, Never> {
      do {
        _ = try await service.generate(system: "sys", user: "usr")
        return GenerateProbe(elapsed: ContinuousClock.now - start, error: nil)
      } catch {
        return GenerateProbe(elapsed: ContinuousClock.now - start, error: error)
      }
    }

    try await Task.sleep(for: probeWarmup)
    try await Task.sleep(for: .milliseconds(100))
    service.setGeneratingForTesting(false)

    let probe = await generateTask.value
    #expect(probe.error as? LLMError == .notLoaded)
    #expect(
      probe.elapsed >= .milliseconds(80),
      "generate() must wait for the guard to clear (elapsed: \(probe.elapsed))")
  }

  @Test func generateStreamWaitsForInFlightGenerate() async throws {
    // Stream variant — the for-await loop cannot observe the `.notLoaded`
    // throw before the flag clears, since the wait sits at the entry of
    // `runStreamGeneration` (before any chunk could be produced).
    let service = makeTestService()
    service.setGeneratingForTesting(true)

    let start = ContinuousClock.now
    let drainTask = Task<GenerateProbe, Never> {
      do {
        for try await _ in service.generateStream(system: "sys", user: "usr") {}
        return GenerateProbe(elapsed: ContinuousClock.now - start, error: nil)
      } catch {
        return GenerateProbe(elapsed: ContinuousClock.now - start, error: error)
      }
    }

    try await Task.sleep(for: probeWarmup)
    try await Task.sleep(for: .milliseconds(100))
    service.setGeneratingForTesting(false)

    let probe = await drainTask.value
    #expect(probe.error as? LLMError == .notLoaded)
    #expect(
      probe.elapsed >= .milliseconds(80),
      "generateStream() must wait for the guard to clear (elapsed: \(probe.elapsed))")
  }

  @Test func multipleWaitersSerializeAfterFlagClear() async throws {
    // Issue #221 follow-up race (PR #236 field repro): when multiple
    // callers (e.g., LLMCaller's JSON parse retry firing back-to-back
    // generateStream calls + an overlapping unloadModel from back-nav
    // cleanup) all wait on the guard simultaneously, the flag-clear
    // event wakes them all. A non-atomic wait + separate claim would
    // let the first claimant trip every subsequent waiter on a
    // now-true flag (the original PR #236 crash). The atomic
    // `acquireGenerateGuard` wait-and-claim must serialize them: each
    // in turn observes the flag clear, claims, runs its body, and
    // releases via `defer`. Two waiters is enough to exercise the
    // race — a non-atomic implementation would crash one of them.
    let service = makeTestService()
    service.setGeneratingForTesting(true)

    let start = ContinuousClock.now
    let task1 = Task<GenerateProbe, Never> {
      do {
        _ = try await service.generate(system: "sys", user: "usr")
        return GenerateProbe(elapsed: ContinuousClock.now - start, error: nil)
      } catch {
        return GenerateProbe(elapsed: ContinuousClock.now - start, error: error)
      }
    }
    let task2 = Task<GenerateProbe, Never> {
      do {
        _ = try await service.generate(system: "sys", user: "usr")
        return GenerateProbe(elapsed: ContinuousClock.now - start, error: nil)
      } catch {
        return GenerateProbe(elapsed: ContinuousClock.now - start, error: error)
      }
    }

    // Both tasks must reach acquireGenerateGuard's poll before the
    // flag-clear window, otherwise the late starter would observe
    // flag=false on its first poll and not actually exercise the
    // multi-waiter race.
    try await Task.sleep(for: probeWarmup)
    try await Task.sleep(for: .milliseconds(100))
    service.setGeneratingForTesting(false)

    let probe1 = await task1.value
    let probe2 = await task2.value

    // Both must complete with .notLoaded — neither may crash on the
    // (formerly load-bearing) precondition.
    #expect(probe1.error as? LLMError == .notLoaded)
    #expect(probe2.error as? LLMError == .notLoaded)
    // Both must have waited for the synthetic in-flight period to clear.
    #expect(probe1.elapsed >= .milliseconds(80))
    #expect(probe2.elapsed >= .milliseconds(80))
  }

  @Test func generateDoesNotEarlyReturnOnTaskCancellation() async throws {
    // The wait at `generate` entry is intentionally NOT cancellable —
    // short-circuiting on `Task.cancel()` would let `unloadModel` free C
    // pointers that an about-to-resume generate is poised to dereference
    // (use-after-free). Mirror of `unloadModelDoesNotEarlyReturnOnTaskCancellation`.
    // We hold the flag for ~300ms with a cancel halfway through; the recorded
    // elapsed proves the wait ran the full duration.
    let service = makeTestService()
    service.setGeneratingForTesting(true)

    let start = ContinuousClock.now
    let generateTask = Task<GenerateProbe, Never> {
      do {
        _ = try await service.generate(system: "sys", user: "usr")
        return GenerateProbe(elapsed: ContinuousClock.now - start, error: nil)
      } catch {
        return GenerateProbe(elapsed: ContinuousClock.now - start, error: error)
      }
    }

    try await Task.sleep(for: .milliseconds(100))
    generateTask.cancel()
    try await Task.sleep(for: .milliseconds(200))
    service.setGeneratingForTesting(false)

    let probe = await generateTask.value
    #expect(probe.error as? LLMError == .notLoaded)
    #expect(
      probe.elapsed >= .milliseconds(280),
      "wait must not short-circuit on Task cancellation (elapsed: \(probe.elapsed))")
  }
}
