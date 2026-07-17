package com.pastura.engine

import kotlin.concurrent.Volatile
import kotlinx.coroutines.CompletableDeferred

/**
 * The Kotlin half of the ADR-023 §5.2 suspension relay: parks an inference that
 * a platform suspend cut off, until the platform signals resume.
 *
 * **Why this type exists instead of a ported `SuspendController`.** Swift's
 * `SuspendController` (`Pastura/Pastura/LLM/SuspendController.swift`) **never
 * crosses the boundary** (ADR-023 Decision 3) — it stays owned by the Swift
 * adapter, which polls it inside the llama.cpp generate loop. Its ownership
 * relocates to the Swift side (§5.2 invariant 4), so Kotlin does not port it. It
 * ports only the *waiting* half, and receives the resume edge as a plain signal
 * via [RunHandle.notifyLLMResumed].
 *
 * **This is NOT a 1:1 port, and the difference is load-bearing.**
 * `SuspendController` is a three-state machine (`idle` -> `suspended` ->
 * `resumed`) driven by an explicit `requestSuspend()`. Kotlin has no such call:
 * the suspend edge arrives as [TerminalStatus.Suspended] from the backend, i.e.
 * only *after* the inference was already cut off. So the states do not map, and
 * this type instead uses an explicit [arm] / [awaitResume] protocol that closes
 * the same races. See the invariants below.
 *
 * ## Protocol (LLMCaller drives it)
 *
 * ```
 * relay.arm()                                  // BEFORE issuing the stream
 * val status = issueStream(...)                // may end Suspended
 * if (status is TerminalStatus.Suspended) {
 *     relay.awaitResume()                      // parks until the platform resumes
 *     continue                                 // re-issue; NOT a retry (invariant 1)
 * }
 * ```
 *
 * **[arm] must precede the stream, not the [awaitResume].** This is the whole
 * design. A resume can land at any point after the backend suspends — including
 * *before* Kotlin has observed [TerminalStatus.Suspended] and reached
 * [awaitResume]. Arming first means the deferred already exists across that
 * entire window, so a resume in it completes the deferred and [awaitResume]
 * returns immediately instead of parking forever. Arming inside [awaitResume]
 * would reintroduce exactly the lost wakeup this closes.
 *
 * ## The four §5.2 invariants
 *
 * 1. **Suspend re-issues stay OFF the retry budget.** Enforced by the caller —
 *    [LLMCaller] `continue`s without touching its attempt counter. This type
 *    carries no counter at all, which is what makes that structurally true.
 * 2. **One deferred per suspension cycle.** [CompletableDeferred] is single-shot,
 *    so [arm] allocates a fresh one per attempt rather than reusing.
 * 3. **Lost-wakeup safety is a design constraint, not luck.** It holds because
 *    the deferred completes *sticky*: a resume that lands before the park is not
 *    dropped, it is recorded. **Do not refactor either side to a rendezvous
 *    primitive (e.g. a `Channel`) without re-proving this** — a rendezvous send
 *    with no receiver would suspend or drop, and the relay would hang.
 * 4. **Controller ownership relocates to Swift.** Nothing here is exported;
 *    [RunHandle.notifyLLMResumed] is the only path in.
 *
 * ## Threading
 *
 * [notifyResumed] is called from the platform on an arbitrary thread; [arm] and
 * [awaitResume] are called from the runner's coroutine. Single-waiter, mirroring
 * `SuspendController`'s documented "1 generate = 1 waiter" contract — concurrent
 * [awaitResume] callers are a programming error and not defended against here.
 *
 * Ported for the ADR-023 §6 Stage-2 gate slice (#501).
 */
internal class SuspensionRelay {

    /**
     * The in-flight cycle's deferred, or `null` when no attempt is armed.
     *
     * `null` makes [notifyResumed] a true no-op, matching `SuspendController.resume()`
     * on `.idle` — a resume with nothing suspended must not latch, or the *next*
     * genuine suspension would un-park immediately and burn a pointless re-issue.
     *
     * `@Volatile` for cross-thread visibility: written by the runner coroutine,
     * read by the platform thread calling [notifyResumed]. Reference writes are
     * single-writer, so no atomic swap is needed — only visibility.
     */
    @Volatile
    private var pending: CompletableDeferred<Unit>? = null

    /**
     * Arm a fresh suspension cycle. Call immediately **before** issuing a stream,
     * so a resume racing the suspend observation is recorded rather than lost.
     *
     * Discards any previous cycle's deferred — by the single-waiter contract the
     * prior cycle has already finished awaiting.
     */
    fun arm() {
        pending = CompletableDeferred()
    }

    /**
     * Park until the platform signals resume, or return immediately if it already
     * did (the sticky latch) or if no cycle is armed.
     */
    suspend fun awaitResume() {
        // Read once: `pending` can be nulled by the disarm below on the next cycle.
        val deferred = pending ?: return
        deferred.await()
        // Disarm so a later stray resume is a no-op rather than latching into the
        // next cycle. Safe: single-waiter means nobody else is awaiting this.
        pending = null
    }

    /**
     * Signal that the platform's suspend cycle ended.
     *
     * Idempotent, and a no-op when nothing is armed — both required by the Swift
     * adapter's cleanup paths, which may fire a resume that races normal
     * completion.
     */
    fun notifyResumed() {
        // `complete` is atomic and idempotent; a second call returns false.
        pending?.complete(Unit)
    }
}
