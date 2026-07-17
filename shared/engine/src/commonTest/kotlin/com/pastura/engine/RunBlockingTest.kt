package com.pastura.engine

import kotlinx.coroutines.CoroutineScope

/**
 * Runs [block] on **real threads**, blocking until it finishes.
 *
 * ## Why this exists rather than `kotlinx.coroutines.test.runTest`
 *
 * `runTest` drives coroutines through a virtual-time scheduler — which is exactly
 * right for [LLMCallerTests] and [SuspensionRelayTests], where the code under test
 * runs inside the test's own scope.
 *
 * It is wrong for [SimulationEngineTests]. [SimulationEngine.run] deliberately owns
 * its own `CoroutineScope(Dispatchers.Default)`: that is the ADR-023 §5.1 threading
 * clause ("`onEvent` fires from a Kotlin worker context; the adapter must not
 * assume MainActor"), and the run is therefore NOT under the test scheduler. Inside
 * `runTest`, a polling loop's `delay` would advance virtual time instantly while the
 * real engine had not progressed at all, so `withTimeout` would fire before the
 * first event — the test would be measuring the scheduler, not the engine.
 *
 * The alternative — injecting a dispatcher into `run()` — was rejected: a
 * `CoroutineContext` parameter on the **public** entry point would put a coroutine
 * type on the exported surface and trip `verifyEngineFrameworkSurface`, which is
 * precisely the Decision 2 violation that guard exists to catch. Testing the engine
 * as PR-C will actually link it is worth an `expect`/`actual`.
 *
 * `runBlocking` is not available in `commonMain`/`commonTest`, hence the
 * expect/actual pair over the jvm and native source sets.
 */
internal expect fun runBlockingTest(block: suspend CoroutineScope.() -> Unit)
