import Foundation

/// Which distribution channel the running build most likely came from.
///
/// **This is a channel *hint*, not a TestFlight assertion.** A `sandboxReceipt`
/// filename is what a TestFlight build sees — and equally what **App Review**
/// and a locally-signed Release build see. So ``isSandboxOrDebug`` must never
/// be the only gate on a destructive or embarrassing diagnostic: pair it with
/// an explicit opt-in `FeatureFlags` key (the ADR-023 §6 S5-3 H7 crash probe
/// gates on `BuildChannel.isSandboxOrDebug && FeatureFlags.h7CrashProbeEnabled`
/// for exactly this reason). The pair narrows *accidental* discovery — the
/// reveal gesture flips the opt-in itself, so it is not defence in depth
/// against a reviewer who taps the version row five times; the probe's
/// deletion before the next App Store submission (ADR-023 §6 S5-5) is what
/// closes that.
///
/// The `#if DEBUG` arm of ``isSandboxOrDebug`` makes the receipt branch
/// unreachable from the unit suite, which only ever runs in a Debug build —
/// that is why the receipt classification lives in the pure, injectable
/// ``isSandboxReceipt(_:)`` and is tested there.
nonisolated enum BuildChannel {
  /// Whether `receiptURL` names a **sandbox** App Store receipt — the receipt
  /// a TestFlight build, an App Review install, and a locally-signed Release
  /// build all carry. Pure so it can be tested without a Release build; see
  /// the type-level note for why the answer is a hint, not an assertion.
  static func isSandboxReceipt(_ receiptURL: URL?) -> Bool {
    receiptURL?.lastPathComponent == "sandboxReceipt"
  }

  /// `true` for a Debug build, or for a Release build whose App Store receipt
  /// is a sandbox one. Never a sufficient gate on its own — pair it with an
  /// opt-in `FeatureFlags` key (type-level note).
  static var isSandboxOrDebug: Bool {
    #if DEBUG
      return true
    #else
      return isSandboxReceipt(Bundle.main.appStoreReceiptURL)
    #endif
  }
}
