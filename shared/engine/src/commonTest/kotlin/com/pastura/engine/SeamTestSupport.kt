package com.pastura.engine

import kotlin.concurrent.atomics.AtomicReference
import kotlin.concurrent.atomics.ExperimentalAtomicApi
import kotlin.concurrent.atomics.fetchAndUpdate
import kotlin.concurrent.atomics.update

// Test doubles for the ADR-023 §4 LanguageDetector / EngineLogger injection
// seams. At package scope, not nested in one suite, for Collector's reason:
// EngineLoggerSeamTests, LLMCallerLanguageAdherenceTests and
// SimulationEngineSeamInjectionTests all need these, and three copies of a
// primitive whose whole point is cross-thread safety would drift — and the
// drift would present as a flake on the Kotlin/Native rung only.

/**
 * Thread-safe spy [EngineLogger] recording every line it is handed.
 *
 * **The atomic is load-bearing for the same reason [Collector]'s is**: a run
 * started from [SimulationEngine] logs from its `Dispatchers.Default` worker
 * context while the test body reads from `runBlockingTest`'s thread, and on
 * Kotlin/Native an unsynchronized list across that edge is undefined behaviour
 * rather than a stale read. Suites that drive [LLMCaller] directly on one
 * thread pay only an allocation per line for it.
 */
@OptIn(ExperimentalAtomicApi::class)
internal class SpyEngineLogger : EngineLogger {
    data class Entry(
        val level: EngineLogLevel,
        val category: String,
        val message: String,
        val privacy: EngineLogPrivacy,
    )

    private val ref = AtomicReference<List<Entry>>(emptyList())

    override fun log(level: EngineLogLevel, category: String, message: String, privacy: EngineLogPrivacy) {
        ref.update { it + Entry(level, category, message, privacy) }
    }

    val entries: List<Entry> get() = ref.load()

    /** Rendered messages emitted on the `StreamingDiag` channel, in order. */
    fun diagLines(): List<String> = entries.filter { it.category == "StreamingDiag" }.map { it.message }
}

/**
 * [LanguageDetector] whose verdicts are a queue drained one entry per call,
 * returning `null` once empty. Mirrors Swift's `StubLanguageDetector`.
 *
 * Atomic for the same cross-thread reason as [SpyEngineLogger] — under a
 * through-runner test the calls themselves land on the worker context.
 */
@OptIn(ExperimentalAtomicApi::class)
internal class SequencedDetector(verdicts: List<String?>) : LanguageDetector {
    private val queue = AtomicReference(verdicts)

    override fun detect(text: String): String? =
        queue.fetchAndUpdate { it.drop(1) }.firstOrNull()
}
