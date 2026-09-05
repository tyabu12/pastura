import Foundation
import StoreKit

/// Which distribution channel the running build most likely came from.
///
/// **This is a channel *hint*, not a TestFlight assertion.** A `.sandbox`
/// `AppTransaction` environment is what a TestFlight build sees — and equally
/// what **App Review** and a locally-signed Release build see. So
/// ``resolveIsSandboxOrDebug()`` must never be the only gate on a destructive
/// or embarrassing diagnostic: pair it with an explicit opt-in `FeatureFlags`
/// key (the ADR-023 §6 S5-3 H7 crash probe gates on the resolved hint `&&
/// FeatureFlags.h7CrashProbeEnabled` for exactly this reason). The pair
/// narrows *accidental* discovery — the reveal gesture flips the opt-in
/// itself, so it is not defence in depth against a reviewer who taps the
/// version row five times; the probe's deletion before the next App Store
/// submission (ADR-023 §6 S5-5) is what closes that.
///
/// StoreKit 2 (`AppTransaction.shared`) rather than
/// `Bundle.main.appStoreReceiptURL`: the receipt URL is deprecated from iOS
/// 18.0 — our minimum — and the Release lane compiles with
/// `-warnings-as-errors`, so the deprecated call only fails the build in the
/// `#else` arm that Debug never compiles. The price is that the hint is
/// `async`: callers hold it in `@State` and resolve it from `.task`, and the
/// gated UI simply does not exist until the answer arrives (defaults to
/// `false`, i.e. the App Store shape).
///
/// The `#if DEBUG` arm of ``resolveIsSandboxOrDebug()`` makes the StoreKit
/// branch unreachable from the unit suite, which only ever runs in a Debug
/// build — that is why the environment classification lives in the pure,
/// injectable ``isSandboxEnvironment(_:)`` and is tested there.
nonisolated enum BuildChannel {
  /// Whether `environment` is a **non-production** App Store environment —
  /// `.sandbox` is what a TestFlight build, an App Review install, and a
  /// locally-signed Release build all report; `.xcode` is a Release build run
  /// from Xcode against a local StoreKit configuration. Pure so it can be
  /// tested without a Release build; see the type-level note for why the
  /// answer is a hint, not an assertion.
  static func isSandboxEnvironment(_ environment: AppStore.Environment) -> Bool {
    environment == .sandbox || environment == .xcode
  }

  /// `true` for a Debug build, or for a Release build whose `AppTransaction`
  /// environment is a sandbox one. Never a sufficient gate on its own — pair
  /// it with an opt-in `FeatureFlags` key (type-level note).
  ///
  /// Any StoreKit failure (no transaction, verification error, offline
  /// first launch) resolves to `false`: the safe default is the App Store
  /// shape, where the gated diagnostics do not exist.
  static func resolveIsSandboxOrDebug() async -> Bool {
    #if DEBUG
      return true
    #else
      guard let result = try? await AppTransaction.shared else { return false }
      // An unverified transaction still names the environment it came from,
      // and this is a hint, not an entitlement check — so do not discard it.
      switch result {
      case .verified(let transaction), .unverified(let transaction, _):
        return isSandboxEnvironment(transaction.environment)
      }
    #endif
  }
}
