import Foundation
import Testing

/// Guards the App Store device-gating contract (#499).
///
/// `iphone-performance-gaming-tier` must be the SOLE
/// `UIRequiredDeviceCapabilities` entry:
/// - Combining it with `ipad-minimum-performance-m1` blocks iPhone
///   installs entirely (Apple Developer Forums thread 773898).
/// - Capability requirements can only be maintained or relaxed after
///   1.0 ships ("For app updates, you can only maintain or relax
///   capability requirements" — UIRequiredDeviceCapabilities docs),
///   so a wrong value here is a one-way door.
///
/// `Bundle.main` in unit tests resolves to the test-host Pastura.app,
/// so this asserts against the same Info.plist the App Store reads.
@Suite(.timeLimit(.minutes(1)))
struct DeviceRequirementsTests {
  @Test func gamingTierIsTheSoleRequiredDeviceCapability() {
    let capabilities =
      Bundle.main.object(
        forInfoDictionaryKey: "UIRequiredDeviceCapabilities") as? [String]
    #expect(capabilities == ["iphone-performance-gaming-tier"])
  }
}
