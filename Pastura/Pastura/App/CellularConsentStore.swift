import Foundation

/// Persists the user's one-time consent to download large model files over
/// cellular. Read at gate-time inside ``ModelManager.startDownload`` to
/// decide whether to fire the cellular confirmation modal (#191).
///
/// `@MainActor` because both reads and writes happen from the UI flow —
/// reads on the gate path (MainActor `ModelManager.startDownload`),
/// writes from the modal accept handler.
@MainActor
public protocol CellularConsentStoring: AnyObject {
  var hasCellularConsent: Bool { get set }
}

/// Production store backed by `UserDefaults` under the key
/// `com.pastura.hasCellularDownloadConsent`. Consent is persistent —
/// once granted, the cellular modal does not re-fire on subsequent
/// downloads. (Future revocation surface — e.g. a Settings toggle —
/// would clear this key.)
@MainActor
public final class UserDefaultsCellularConsentStore: CellularConsentStoring {

  /// UserDefaults key for the persisted consent flag. Namespaced under
  /// `com.pastura.` to coexist with other per-user toggles.
  public static let consentKey = "com.pastura.hasCellularDownloadConsent"

  private let defaults: UserDefaults

  public init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  public var hasCellularConsent: Bool {
    get { defaults.bool(forKey: Self.consentKey) }
    set { defaults.set(newValue, forKey: Self.consentKey) }
  }
}

/// Test double — directly-settable `hasCellularConsent` with no
/// persistence side effects. Used by `ModelManagerTests+CellularGate.swift`
/// to drive the gate state synchronously.
@MainActor
public final class MockCellularConsentStore: CellularConsentStoring {
  public var hasCellularConsent: Bool

  public init(hasCellularConsent: Bool = false) {
    self.hasCellularConsent = hasCellularConsent
  }
}
