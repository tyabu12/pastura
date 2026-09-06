import PasturaSharedEngine

/// Fires the ADR-023 §6 S5-3 H7 probe: an **intentional** uncaught Kotlin
/// exception, raised from the Settings "Diagnostics" row so a real TestFlight
/// crash report can prove the Kotlin/Native dSYM symbolication path works
/// (ADR-004 §9.2 H7).
///
/// This was the first `App/KMP/` symbol reachable from the app's run path;
/// since S5-4 (#1681) the rest of this directory is reached behind
/// `FeatureFlags.sharedEngineEnabled`. It is a diagnostics-only path, gated twice at
/// its single call site: `BuildChannel.resolveIsSandboxOrDebug()` (channel hint) **and**
/// `FeatureFlags.h7CrashProbeEnabled` (explicit opt-in), because the channel
/// hint alone also fires under App Review.
///
/// The trailing `fatalError` is the **detector for a disabled probe**: if a
/// `@Throws` annotation is ever added to `H7CrashProbe.crash` on the Kotlin
/// side, the exception becomes a catchable Swift error, the call returns
/// normally, and the probe silently stops testing anything. Crashing loudly
/// there keeps the failure visible instead — though it crashes without a
/// Kotlin frame, which is itself the signal.
///
/// Sunset: deleted in ADR-023 §6 S5-5 together with the Kotlin
/// `H7CrashProbe`, the Settings row, and `FeatureFlags.h7CrashProbeEnabled`.
nonisolated enum H7CrashTrigger {
  /// Terminates the process through the K/N uncaught-exception path. Never
  /// returns.
  ///
  /// The Kotlin type is spelled fully qualified per `kmp-interop.md`
  /// Pattern 1b. No Swift twin named `H7CrashProbe` exists today, but the
  /// qualification is written anyway: a later same-named Swift type would
  /// otherwise shadow the import silently.
  static func fire() -> Never {
    PasturaSharedEngine.H7CrashProbe.shared.crash(reason: "Settings diagnostics row")
    fatalError(
      "H7CrashProbe.crash returned — the K/N uncaught-exception path did not "
        + "terminate the process; was @Throws added?")
  }
}
