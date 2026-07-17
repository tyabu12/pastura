package com.pastura.engine

import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/**
 * Pins the ADR-023 §5.2 suspension-relay invariants on [SuspensionRelay].
 *
 * These are the ADR's named hazards, made executable. Each test states the
 * failure it prevents — a relay that hangs the simulation is not observable from
 * a "does it resume" happy-path test, so the ordering cases below are the point.
 *
 * Ported for the ADR-023 §6 Stage-2 gate slice (#501).
 */
@OptIn(ExperimentalCoroutinesApi::class)
class SuspensionRelayTests {

    // MARK: - Invariant 3: lost-wakeup safety

    @Test
    fun resumeBeforeParkIsLatchedNotLost() = runTest {
        // THE hazard the sticky deferred exists for. A fast background/foreground
        // can deliver the resume before Kotlin has even observed
        // TerminalStatus.Suspended and reached awaitResume. If the relay only
        // woke a waiter that was already parked, this would drop the signal and
        // the simulation would hang forever.
        val relay = SuspensionRelay()
        relay.arm()
        relay.notifyResumed() // arrives with nobody parked yet

        var resumed = false
        val job = launch {
            relay.awaitResume()
            resumed = true
        }
        advanceUntilIdle()
        assertTrue(resumed, "awaitResume must return immediately on a pre-latched resume")
        job.join()
    }

    @Test
    fun parkThenResumeWakesTheWaiter() {
        // The ordinary ordering, for completeness.
        runTest {
            val relay = SuspensionRelay()
            relay.arm()

            var resumed = false
            val job = launch {
                relay.awaitResume()
                resumed = true
            }
            advanceUntilIdle()
            assertFalse(resumed, "must still be parked before the resume signal")

            relay.notifyResumed()
            advanceUntilIdle()
            assertTrue(resumed)
            job.join()
        }
    }

    // MARK: - arm() placement — why it precedes the stream

    @Test
    fun unarmedResumeIsANoOpAndDoesNotLatchIntoTheNextCycle() {
        // Mirrors SuspendController.resume() on `.idle`: a resume with nothing
        // suspended must NOT latch. If it did, the next genuine suspension would
        // un-park instantly and burn a pointless re-issue against a still-
        // backgrounded GPU.
        runTest {
            val relay = SuspensionRelay()
            relay.notifyResumed() // nothing armed — must be dropped

            relay.arm()
            var resumed = false
            val job = launch {
                relay.awaitResume()
                resumed = true
            }
            advanceUntilIdle()
            assertFalse(resumed, "a stray pre-arm resume must not latch into this cycle")

            relay.notifyResumed()
            advanceUntilIdle()
            assertTrue(resumed)
            job.join()
        }
    }

    @Test
    fun awaitWithoutArmReturnsImmediately() {
        // Defensive: an unarmed await must not hang. Not a path LLMCaller takes
        // (it always arms first), but a hang here would be near-undiagnosable.
        runTest {
            val relay = SuspensionRelay()
            var done = false
            val job = launch {
                relay.awaitResume()
                done = true
            }
            advanceUntilIdle()
            assertTrue(done)
            job.join()
        }
    }

    // MARK: - Invariant 2: one deferred per suspension cycle

    @Test
    fun eachArmStartsAFreshCycleSoNSuspensionsAllPark() {
        // CompletableDeferred is single-shot. If arm() reused one, cycle 2 would
        // see an already-completed deferred and never park — a long inference
        // that backgrounds twice would spin re-issuing.
        runTest {
            val relay = SuspensionRelay()

            repeat(3) { cycle ->
                relay.arm()
                var resumed = false
                val job = launch {
                    relay.awaitResume()
                    resumed = true
                }
                advanceUntilIdle()
                assertFalse(resumed, "cycle $cycle must park on its own fresh deferred")

                relay.notifyResumed()
                advanceUntilIdle()
                assertTrue(resumed, "cycle $cycle must resume")
                job.join()
            }
        }
    }

    @Test
    fun staleResumeAfterACompletedCycleDoesNotLatchIntoTheNext() {
        // awaitResume disarms on the way out, so a late duplicate resume from the
        // adapter's cleanup path cannot leak into the following cycle.
        runTest {
            val relay = SuspensionRelay()
            relay.arm()
            val first = launch { relay.awaitResume() }
            relay.notifyResumed()
            advanceUntilIdle()
            first.join()

            relay.notifyResumed() // stale duplicate, cycle already finished

            relay.arm()
            var resumed = false
            val second = launch {
                relay.awaitResume()
                resumed = true
            }
            advanceUntilIdle()
            assertFalse(resumed, "a stale resume must not pre-latch the next cycle")

            relay.notifyResumed()
            advanceUntilIdle()
            assertTrue(resumed)
            second.join()
        }
    }

    // MARK: - Idempotence

    @Test
    fun repeatedResumeIsIdempotent() {
        // The adapter's cleanup paths may race a normal resume — Swift's
        // SuspendController documents the same idempotence.
        runTest {
            val relay = SuspensionRelay()
            relay.arm()
            var resumed = false
            val job = launch {
                relay.awaitResume()
                resumed = true
            }
            advanceUntilIdle()

            relay.notifyResumed()
            relay.notifyResumed()
            relay.notifyResumed()
            advanceUntilIdle()

            assertTrue(resumed)
            job.join()
        }
    }
}
