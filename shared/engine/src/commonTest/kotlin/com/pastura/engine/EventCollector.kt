package com.pastura.engine

import com.pastura.models.SimulationEvent
import kotlin.concurrent.atomics.AtomicReference
import kotlin.concurrent.atomics.ExperimentalAtomicApi
import kotlinx.coroutines.withTimeout

/**
 * Collects events off the engine's worker thread.
 *
 * **Thread-safety is not optional here** — that is the ADR-023 §5.1 threading
 * clause: `onEvent` fires from a Kotlin worker context, while the test body
 * reads from `runBlockingTest`'s thread. An unsynchronized `MutableList` across
 * those two is a genuine data race: torn reads on the JVM, and undefined
 * behaviour on Kotlin/Native, where it can surface as a crash rather than a
 * wrong value.
 *
 * `Mutex.withLock` is not usable: [record] is called from the non-suspending
 * `onEvent` callback. `AtomicReference` over an immutable list gives lock-free,
 * allocation-per-event correctness — fine at test volumes, and it makes
 * [snapshot] trivially consistent (it reads one immutable value rather than
 * copying a mutating list).
 *
 * Lives at package scope rather than nested in one suite because
 * [SimulationEngineTests] and [EngineParityTests] both drive a real run.
 * Duplicating a concurrency primitive is how the two copies drift, and a drift
 * in this one would present as a flake on the K/N rung only.
 */
@OptIn(ExperimentalAtomicApi::class)
internal class Collector {
    private val ref = AtomicReference<List<SimulationEvent>>(emptyList())

    fun record(event: SimulationEvent) {
        while (true) {
            val current = ref.load()
            if (ref.compareAndSet(current, current + event)) return
        }
    }

    val isTerminal: Boolean
        get() = ref.load().lastOrNull()?.isTerminal == true

    fun snapshot(): List<SimulationEvent> = ref.load()
}

/** Suspends until [collector] has seen a terminal event, or the timeout fires. */
internal suspend fun awaitTerminal(collector: Collector, timeoutMillis: Long = 5_000) {
    withTimeout(timeoutMillis) {
        while (!collector.isTerminal) kotlinx.coroutines.delay(1)
    }
}

/** Suspends until [predicate] holds, or the timeout fires. */
internal suspend fun await(timeoutMillis: Long = 5_000, predicate: () -> Boolean) {
    withTimeout(timeoutMillis) {
        while (!predicate()) kotlinx.coroutines.delay(1)
    }
}
