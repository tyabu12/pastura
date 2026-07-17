package com.pastura.engine

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.runBlocking

/** See the `expect` declaration in commonTest for why this is not `runTest`. */
internal actual fun runBlockingTest(block: suspend CoroutineScope.() -> Unit) {
    runBlocking { block() }
}
