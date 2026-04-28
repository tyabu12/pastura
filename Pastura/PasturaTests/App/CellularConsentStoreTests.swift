import Foundation
import Testing

@testable import Pastura

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct CellularConsentStoreTests {

  /// Creates an in-memory `UserDefaults` suite scoped to a fresh suite name
  /// per test, so persistence tests do not bleed into each other or into
  /// the standard defaults database.
  private static func makeIsolatedDefaults() -> UserDefaults {
    let suiteName = "test.pastura.cellular.\(UUID().uuidString)"
    return UserDefaults(suiteName: suiteName)!
  }

  @Test("UserDefaults-backed store defaults to no consent")
  func userDefaultsDefaultsToFalse() {
    let store = UserDefaultsCellularConsentStore(defaults: Self.makeIsolatedDefaults())
    #expect(store.hasCellularConsent == false)
  }

  @Test("UserDefaults-backed store persists consent across instances")
  func userDefaultsPersistsConsent() {
    let defaults = Self.makeIsolatedDefaults()
    let first = UserDefaultsCellularConsentStore(defaults: defaults)
    first.hasCellularConsent = true
    let second = UserDefaultsCellularConsentStore(defaults: defaults)
    #expect(second.hasCellularConsent == true)
  }

  @Test("UserDefaults-backed store can clear consent")
  func userDefaultsCanClearConsent() {
    let store = UserDefaultsCellularConsentStore(defaults: Self.makeIsolatedDefaults())
    store.hasCellularConsent = true
    store.hasCellularConsent = false
    #expect(store.hasCellularConsent == false)
  }

  @Test("MockCellularConsentStore exposes synchronously-settable consent")
  func mockExposesSyncConsent() {
    let mock = MockCellularConsentStore()
    #expect(mock.hasCellularConsent == false)
    mock.hasCellularConsent = true
    #expect(mock.hasCellularConsent == true)
  }
}
