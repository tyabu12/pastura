package com.pastura.engine

/**
 * Source of raw 64-bit randomness for every draw the Engine makes.
 *
 * The seam exists for ADR-023 Stage 4 (issue #501, S3b): the Swift engine
 * carries an identical protocol (`Pastura/Pastura/Engine/RandomSource.swift`),
 * so a cross-language parity fixture can hand both engines the same seeded
 * stream and expect the same `assign random_one` / `event_inject` outcomes.
 * Handlers never call the stdlib ranged draws (`Random.nextInt(n)`,
 * `List.random()`, `Random.nextDouble()`) — those reduce the raw bits with
 * platform-specific algorithms that disagree with Swift's even on the same
 * seed. They call [index] / [unit] instead, whose reductions are spelled out
 * here and mirrored bit-for-bit in the Swift file.
 *
 * Draw *order* is part of the parity contract: handlers run sequentially within
 * a run, so two engines given the same seed consume the same stream in the same
 * order.
 *
 * **A Swift conformer must be declared `nonisolated`.** K/N exports this as an
 * unannotated Obj-C protocol and a Stage-5 adapter's [nextUInt64] is called from
 * the Engine's `Dispatchers.Default` context, so a default-MainActor
 * conformance compiles clean and traps at runtime — the [LLMBackend] /
 * [EngineLogger] precedent, `.claude/rules/swift-isolation.md` Pattern 7.
 */
public interface RandomSource {
    /** The next 64 raw bits of the stream, uniformly distributed. */
    public fun nextUInt64(): ULong
}

/**
 * A uniform index in `0 until below`, reduced as `nextUInt64() % below`.
 *
 * Modulo bias is accepted on purpose: the reduction must be identical on both
 * engines, and its statistical quality is irrelevant to the choices it drives
 * (which topic, which wolf, which event).
 *
 * Precondition: `below > 0`. Every caller draws from a pool it has already
 * proven non-empty (`AssignHandler` guards `topics` / `active`,
 * `EventInjectHandler` resets `remaining` before drawing), so a zero here is a
 * handler bug, not a runtime condition to absorb. Kotlin throws; Swift traps on
 * `% 0` — the contract is the same either way.
 */
public fun RandomSource.index(below: Int): Int {
    require(below > 0) { "RandomSource.index(below:) requires a non-empty pool" }
    return (nextUInt64() % below.toULong()).toInt()
}

/**
 * A uniform [Double] in `[0, 1)`, built from the top 53 bits so the value is
 * exact and identical to Swift's `Double(bits >> 11) * 0x1.0p-53`.
 *
 * `1L shl 53` is a power of two, so the reciprocal is exact and the
 * multiplication is a single correctly-rounded step on both engines — a `pow`
 * call would not be guaranteed to be.
 */
public fun RandomSource.unit(): Double =
    (nextUInt64() shr 11).toLong().toDouble() * (1.0 / (1L shl 53).toDouble())

/**
 * The production [RandomSource]: the platform's default generator, so injecting
 * the seam changes nothing about shipped behaviour.
 */
public class SystemRandomSource : RandomSource {
    override fun nextUInt64(): ULong = kotlin.random.Random.Default.nextLong().toULong()
}

/**
 * SplitMix64 (Steele, Lea & Flood 2014; Vigna's reference constants), the
 * seeded [RandomSource] parity fixtures use.
 *
 * Chosen for being a dozen lines with no lookup table, so the Swift twin is
 * trivially the same code — `RandomSourceTests` pins both to shared
 * known-answer vectors.
 *
 * @param seed The stream's seed; the same seed yields the same sequence on both
 *   engines.
 */
public class SplitMix64RandomSource(seed: ULong) : RandomSource {
    // A plain `var` with no lock: draws are sequential within a run (the parity
    // precondition stated on RandomSource), so the state is never contended.
    // The Swift twin's `Mutex` exists only to make the class honestly
    // `Sendable`, not because concurrent draws are expected.
    private var state: ULong = seed

    override fun nextUInt64(): ULong {
        state += 0x9E3779B97F4A7C15uL
        var mixed = state
        mixed = (mixed xor (mixed shr 30)) * 0xBF58476D1CE4E5B9uL
        mixed = (mixed xor (mixed shr 27)) * 0x94D049BB133111EBuL
        return mixed xor (mixed shr 31)
    }
}
