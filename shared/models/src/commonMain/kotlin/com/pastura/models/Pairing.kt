package com.pastura.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * A pair of agents matched for a phase interaction (e.g., `choose` with
 * round-robin pairing).
 *
 * Kotlin port of `Pastura/Pastura/Models/Pairing.swift` (Issue #220 W1
 * 2nd pilot — exercises Optional null-vs-omit serialization semantics per
 * critic Axis 5, surfacing one of the H2 canonicalizer-design questions
 * for W2 ahead of the bulk port).
 *
 * **Mutability divergence from Swift original:** Swift has `var action1`
 * / `var action2` so `ChooseHandler` can mutate after LLM inference. The
 * Kotlin data class uses `val` for all properties — mutation in Kotlin
 * idiom is via `.copy(action1 = ...)`, not in-place. W2 canonicalizer
 * design must account for this: Engine port (W3+) will need a different
 * mutation strategy (immutable + reassign vs in-place), to be captured in
 * Tier 4 observations.
 *
 * **Scope of this pilot:** Kotlin-side JSON encode/decode roundtrip + null
 * field emission canary only. Full Swift↔Kotlin canonicalizer (H2) is W2/W3.
 *
 * @property agent1  The name of the first agent in the pair.
 * @property agent2  The name of the second agent in the pair.
 * @property action1 Action chosen by the first agent; null before inference.
 * @property action2 Action chosen by the second agent; null before inference.
 */
@Serializable
public data class Pairing(
    val agent1: String,
    val agent2: String,
    val action1: String? = null,
    val action2: String? = null,
)

/**
 * Strategy for generating agent pairings in phases that require matchups.
 *
 * Kotlin port of `Pastura/Pastura/Models/Pairing.swift:31` enum. Added in
 * W1 (alongside [Pairing]) per code-reviewer warning #3 — exercises the
 * raw-value-string-enum serialization surface that W2 canonicalizer must
 * reconcile (Kotlin `@SerialName` vs Swift's `String` raw-value `Codable`
 * default). Cheap to surface now; expensive to discover at W2 bulk port.
 */
@Serializable
public enum class PairingStrategy {
    /** Each agent plays against every other agent exactly once per round. */
    @SerialName("round_robin")
    ROUND_ROBIN,
}
