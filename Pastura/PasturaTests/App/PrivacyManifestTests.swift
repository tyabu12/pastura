import Foundation
import Testing

/// Guards the App Store privacy-manifest contract (#879).
///
/// Change-detector: pins the bundled `PrivacyInfo.xcprivacy` to the exact
/// required-reason API set the app actually uses. A failure is NOT
/// necessarily a bug — it means either (a) a new required-reason API was
/// adopted in code without a manifest declaration (which would otherwise
/// surface only as ITMS-91053 at App Store Connect upload, long after the
/// PR merged), or (b) the manifest changed — confirm the change passed
/// review, then update the expected values here.
///
/// Reads the **bundled** manifest (`Bundle.main` resolves to the test-host
/// Pastura.app, same as `DeviceRequirementsTests`) rather than the source
/// file, so it validates the shipped artifact: a manifest that falls out of
/// the app bundle is itself the ITMS-91053 condition, and fails loudly here
/// via the missing-resource path.
@Suite(.timeLimit(.minutes(1)))
struct PrivacyManifestTests {
  /// The bundled manifest as a plist dictionary. Throws (loud failure)
  /// when the resource is absent from the app bundle or not a plist dict.
  private static func loadManifest() throws -> [String: Any] {
    let url = try #require(
      Bundle.main.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"),
      "PrivacyInfo.xcprivacy missing from the app bundle — this is the ITMS-91053 condition"
    )
    let data = try Data(contentsOf: url)
    let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
    return try #require(plist as? [String: Any], "manifest root is not a dictionary")
  }

  @Test func declaresNoTrackingAndNoCollectedData() throws {
    let manifest = try Self.loadManifest()
    // The ASC-side "Data Not Collected" nutrition-label answers (manual
    // gate, tracked in #233) rest on these two staying empty/false; the
    // manifest file itself is owned by ADR-005 §9.2 row #2 (#149).
    #expect(manifest["NSPrivacyTracking"] as? Bool == false)
    let collected = try #require(manifest["NSPrivacyCollectedDataTypes"] as? [Any])
    #expect(collected.isEmpty)
  }

  @Test func accessedAPIDeclarationsMatchUsage() throws {
    let manifest = try Self.loadManifest()
    let entries = try #require(
      manifest["NSPrivacyAccessedAPITypes"] as? [[String: Any]])

    var declared: [String: Set<String>] = [:]
    for entry in entries {
      let category = try #require(entry["NSPrivacyAccessedAPIType"] as? String)
      let reasons = try #require(entry["NSPrivacyAccessedAPITypeReasons"] as? [String])
      #expect(declared[category] == nil, "duplicate category \(category)")
      declared[category] = Set(reasons)
    }

    // Exact set of required-reason APIs the app uses today:
    // - UserDefaults (CA92.1): app-scoped preferences access.
    // - FileTimestamp (C617.1): timestamps of app-container files.
    // - DiskSpace (E174.1): `ModelManager.availableStorageBytes()` probes
    //   `volumeAvailableCapacityForImportantUsage` to warn before a
    //   multi-GB model download (85F4.1 deliberately NOT claimed — the
    //   low-storage sheet shows only the model's file size, never the
    //   probed capacity).
    #expect(
      declared == [
        "NSPrivacyAccessedAPICategoryUserDefaults": ["CA92.1"],
        "NSPrivacyAccessedAPICategoryFileTimestamp": ["C617.1"],
        "NSPrivacyAccessedAPICategoryDiskSpace": ["E174.1"]
      ])
  }
}
