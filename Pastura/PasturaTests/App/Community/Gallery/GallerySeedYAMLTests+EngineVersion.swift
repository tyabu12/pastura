import Foundation
import Testing

@testable import Pastura

extension GallerySeedYAMLTests {

  /// The highest `min_engine_version` a **gallery** scenario may declare
  /// while ADR-020 §8 item-4's deep-link sequencing obligation is still
  /// undischarged.
  ///
  /// A gallery entry whose declared floor exceeds `EngineSchemaVersion` on an
  /// **older installed app** greys out (ADR-020 D4) and, on Try, hits the
  /// `.updateRequired` alert (D5). Until the App Store deep-link — or an
  /// explicit forward-guidance path — lands on that badge/alert, such a row
  /// **dead-ends with no way forward** (the exact failure D5 exists to
  /// prevent; the App Store ID is not yet minted). The safe floor every
  /// installed app can still run is therefore the pre-`no_repeat` baseline:
  /// `1`. This is a **literal, deliberately decoupled from
  /// `EngineSchemaVersion.current`** (= 2) — tying it to `current` would
  /// auto-raise it on the next bump and silently defeat this tripwire.
  static let maxGalleryFloorWithoutDeepLink = 1

  /// Tripwire enforcing ADR-020 §8 item-4: **no gallery scenario may declare
  /// `min_engine_version` above ``maxGalleryFloorWithoutDeepLink`` until the
  /// deep-link/forward-guidance obligation is discharged.**
  ///
  /// This is the mechanical companion to the ADR's prose obligation
  /// ("revisit before any gallery scenario declares `min_engine_version: 2`"):
  /// the first curation PR that raises a floor must touch this test, which
  /// forces its author to read the obligation and land the deep-link first.
  /// Green today — every current `gallery.json` entry decodes `nil` (see
  /// `GalleryScenario.minEngineVersion`).
  ///
  /// **Bounded scope (does NOT cover the D2 path).** There are two greying
  /// paths in ADR-020: D3 (a **declared** `min_engine_version`, checked here)
  /// and D2 (a phase kind in `phases` unknown to an older app's
  /// `PhaseType.allCases`, auto-greyed with **no declared floor**). A gallery
  /// entry that adopts a *new* `PhaseType` greys via D2 on older apps yet
  /// declares no floor, so this tripwire stays **green** for it. Mechanically
  /// catching the D2 path needs the deferred D3a versioned-capability manifest
  /// (ADR-020 §7) — out of scope here. In the interim that path is gated only
  /// by the v2-maintainer-checklist item-2 curator discipline (a new-phase
  /// adopter is expected to raise `min_engine_version` manually), which the
  /// ADR does not mechanically guarantee. Do not read this test's green as
  /// "the deep-link obligation is fully guarded" — it guards only the declared
  /// floor.
  @Test func noGalleryScenarioDeclaresFloorAboveDeepLinkBaseline() throws {
    let galleryDir = Self.repoRoot().appendingPathComponent("docs/gallery")
    let indexURL = galleryDir.appendingPathComponent("gallery.json")
    let indexData = try Data(contentsOf: indexURL)
    let index = try JSONDecoder().decode(GalleryIndex.self, from: indexData)

    #expect(!index.scenarios.isEmpty, "gallery.json has no scenarios")

    for entry in index.scenarios {
      guard let floor = entry.minEngineVersion else { continue }
      #expect(
        floor <= Self.maxGalleryFloorWithoutDeepLink,
        """
        gallery.json entry id=\(entry.id) declares min_engine_version=\(floor), \
        above the deep-link baseline \(Self.maxGalleryFloorWithoutDeepLink). \
        An older installed app would grey this row (ADR-020 D4/D5) with no way \
        forward. Land the App Store deep-link (or explicit forward-guidance) on \
        the "Update app" badge / "Update required" alert FIRST (ADR-020 §8 \
        item-4, issue #976), then raise maxGalleryFloorWithoutDeepLink.
        """)
    }
  }
}
