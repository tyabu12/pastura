package com.pastura.engine

/**
 * The ADR-023 §6 S5-3 H7 probe: an intentional uncaught Kotlin exception fired
 * from a Settings diagnostics row on TestFlight builds so the K/N dSYM
 * symbolication path can be verified (ADR-004 §9.2 H7).
 *
 * `@Throws` must NOT be added to [crash]. The probe's mechanism is the
 * Kotlin/Native rule that an exception leaving a non-`@Throws` exported
 * function terminates the process; annotating it turns the Swift call into a
 * catchable `throws` and silently disables the probe. `.claude/rules/kmp-interop.md`
 * Pattern 5 carves this function out for that reason.
 *
 * Sunset: deleted in ADR-023 §6 S5-5 together with its Swift callers
 * (`App/KMP/H7CrashTrigger.swift`, `Views/Settings/SettingsView+Diagnostics.swift`,
 * `FeatureFlags.h7CrashProbeEnabled`).
 */
object H7CrashProbe {
    /**
     * Throws an uncaught [IllegalStateException] carrying [reason]. Never
     * returns normally; declared as `Unit` (not `Nothing`) so the exported
     * Obj-C selector is a plain `- (void)crashReason:` that Swift can call
     * from a `-> Never` wrapper. See the type-level KDoc for the `@Throws`
     * prohibition and the sunset.
     */
    fun crash(reason: String) {
        throwCrash(reason)
    }

    // Routed through a separate frame so a second Kotlin frame can appear in
    // the crash symbolication when the optimizer keeps it (not guaranteed:
    // release builds may inline this away).
    private fun throwCrash(reason: String): Nothing {
        throw IllegalStateException("H7 intentional crash: $reason")
    }
}
