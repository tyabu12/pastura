import Foundation
import OSLog
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
/// StoreKit 2 (`AppTransaction.shared`) is the primary signal rather than
/// `Bundle.main.appStoreReceiptURL`: the receipt URL is deprecated from iOS
/// 18.0 — our minimum — and the Release lane compiles with
/// `-warnings-as-errors`, so a deprecated call only fails the build in the
/// `#else` arm that Debug never compiles. The price is that the hint is
/// `async`: callers hold it in `@State` and resolve it from `.task`, and the
/// gated UI simply does not exist until the answer arrives (defaults to
/// `false`, i.e. the App Store shape).
///
/// **The receipt name is the fallback when StoreKit throws** (#1677): the
/// v1.3+885 TestFlight install failed `AppTransaction.shared` with
/// `SKInternalErrorDomain Code=13` (its own UserInfo saying
/// `client-environment-type=Sandbox`), which left the H7 gesture unattached
/// and the S5-3 cycle blocked. `sandboxReceipt` is what TestFlight, App
/// Review, and a locally-signed Release build carry; an App Store install
/// carries `receipt`, so the safe default survives. App Review resolves
/// `.sandbox` on the StoreKit path and `sandboxReceipt` on the fallback, so
/// the reveal gesture is reachable there either way — the opt-in flag plus
/// the S5-5 deletion, not the channel hint, are what keep the probe out of a
/// reviewer's hands. The deprecated API is read only inside ``receiptURL()``
/// (see its note), and only once StoreKit has already failed.
///
/// The `#if DEBUG` arm of ``resolveIsSandboxOrDebug()`` makes the StoreKit
/// branch unreachable from the unit suite, which only ever runs in a Debug
/// build — that is why the environment classification lives in the pure,
/// injectable ``isSandboxEnvironment(_:)`` / ``resolve(environment:receiptURL:)``
/// and is tested there.
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

  /// Pure decision behind ``resolveIsSandboxOrDebug()``'s Release arm: a
  /// StoreKit answer wins; when StoreKit gave none (`environment == nil`)
  /// the receipt file name decides — `sandboxReceipt` is the non-production
  /// shape, anything else (`receipt`, or no URL at all) the App Store one.
  static func resolve(environment: AppStore.Environment?, receiptURL: URL?) -> Bool {
    if let environment {
      return isSandboxEnvironment(environment)
    }
    return receiptURL?.lastPathComponent == "sandboxReceipt"
  }

  /// `true` for a Debug build, or for a Release build whose `AppTransaction`
  /// environment is a sandbox one — falling back to the receipt file name
  /// when StoreKit throws (type-level note). Never a sufficient gate on its
  /// own — pair it with an opt-in `FeatureFlags` key.
  ///
  /// Not tried on failure: `AppTransaction.refresh()` — it can present an
  /// App Store sign-in prompt, and this runs from `SettingsView`'s `.task`
  /// for every App Store user, not from a user-initiated action. Also not a
  /// signal: the absence of `embedded.mobileprovision`, which App Store and
  /// TestFlight installs share, so it cannot tell the two apart and would
  /// flip the default toward the unsafe side.
  static func resolveIsSandboxOrDebug() async -> Bool {
    #if DEBUG
      return true
    #else
      // An unverified transaction still names the environment it came from,
      // and this is a hint, not an entitlement check — so do not discard it.
      var environment: AppStore.Environment?
      // Read only on the failure path, and once: the deprecated KVC read stays
      // off every App Store user's success path, and the logged name is
      // provably the one the decision used.
      var receipt: URL?
      do {
        switch try await AppTransaction.shared {
        case .verified(let transaction), .unverified(let transaction, _):
          environment = transaction.environment
        }
      } catch {
        receipt = receiptURL()
        let receiptName = receipt?.lastPathComponent ?? "<none>"
        // `.info` so the next "the gesture does nothing" report can be read
        // off Console.app without spending another TestFlight build number.
        logger.info(
          "AppTransaction failed (\(String(describing: error), privacy: .public)); receipt name \(receiptName, privacy: .public)"
        )
      }
      return resolve(environment: environment, receiptURL: receipt)
    #endif
  }

  #if !DEBUG
    private static let logger = Logger(subsystem: "app.pastura.Pastura", category: "BuildChannel")

    /// The only reader of the deprecated `appStoreReceiptURL`, through KVC so
    /// the compiler never sees the deprecated reference — the Release lane
    /// builds with `-warnings-as-errors`, and neither `@available` shape
    /// confines the warning: `deprecated: 18.0` on this helper re-raises it
    /// at the call site, and a far-future version is not "deprecated" at the
    /// deployment target, so it suppresses nothing (measured 2026-09-05).
    /// No `fileExists` check on purpose: the URL names the environment whether
    /// or not the file has been written yet, and a missing file would
    /// otherwise read as App Store. The `responds(to:)` guard is the
    /// compile-time check KVC gave up: if a future SDK removes the property,
    /// this returns `nil` instead of raising `NSUnknownKeyException`, which
    /// Swift cannot catch.
    private static func receiptURL() -> URL? {
      let selector = NSSelectorFromString("appStoreReceiptURL")
      guard Bundle.main.responds(to: selector) else { return nil }
      return Bundle.main.value(forKey: "appStoreReceiptURL") as? URL
    }
  #endif
}
