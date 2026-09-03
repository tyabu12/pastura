import Foundation
import Testing

@testable import Pastura

extension GallerySeedYAMLTests {

  /// The highest `min_engine_version` a **gallery** scenario may declare
  /// without a curator re-reading ADR-020 §8 item-4 / §12.
  ///
  /// A gallery entry whose declared floor exceeds `EngineSchemaVersion` on an
  /// **older installed app** greys out (ADR-020 D4) and, on Try, hits the
  /// `.updateRequired` alert (D5). The App Store deep-link on both surfaces
  /// landed 2026-09-02 (#1648, ADR-020 §12), which discharged the original
  /// obligation and raised this from `1` to `2`. It stays a **literal,
  /// deliberately decoupled from `EngineSchemaVersion.current`** — whatever
  /// that constant currently is, tying this to it would auto-raise the cap on
  /// the next bump and turn the tripwire into a no-op. Each further raise is a
  /// deliberate edit: the deep-link protects only builds that carry it, so
  /// before declaring a higher floor confirm which installed builds would grey
  /// the row and whether they have the link (ADR-020 §12's table by tag is the
  /// template). (Deliberately not restated as a number in prose: an earlier
  /// parenthetical said "= 2" and went stale across three bumps.)
  static let maxGalleryFloorWithoutDeepLink = 2

  /// Tripwire enforcing ADR-020 §8 item-4 / §12: **no gallery scenario may
  /// declare `min_engine_version` above ``maxGalleryFloorWithoutDeepLink``
  /// without a curator raising that constant on purpose.**
  ///
  /// This is the mechanical companion to the ADR's prose obligation: the first
  /// curation PR that raises a floor past the constant must touch this test,
  /// which forces its author to read the obligation. The deep-link itself has
  /// landed (§12); what the tripwire now guards is the *rollout* question —
  /// which installed builds would grey the row, and whether they have it.
  /// Green today — every current `gallery.json` entry decodes `nil` (see
  /// `GalleryScenario.minEngineVersion`); the first floor-2 entry is #1662.
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
        An older installed app would grey this row (ADR-020 D4/D5). Before \
        raising maxGalleryFloorWithoutDeepLink, confirm which installed builds \
        grey it and whether they carry the App Store deep-link (ADR-020 §12, \
        #1648) — then raise the constant in the same PR.
        """)
    }
  }
}
