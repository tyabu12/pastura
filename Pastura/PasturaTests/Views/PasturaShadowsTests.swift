import SwiftUI
import Testing

@testable import Pastura

/// Guards `PasturaShadows` (§4.3's general card-elevation recipe) with three
/// arms: the two failure modes its sibling `PasturaOccluderShadowsTests` names,
/// plus the shared-tint invariant (arm 2, documented at its own declaration).
/// The two families now share a tint and a requirement, and differ only in
/// geometry.
///
/// Arm 1 (`tintIsDarkerThanEveryGroundItCanCover`) states the requirement the
/// #1378 retint exists to hold: the tint must be darker, per channel, than
/// every ground it can composite over. `a·C + (1−a)·ground` can only fall
/// below `ground` when `C` is below it, independent of `a`, so the assertion
/// belongs on the tint rather than on any composite. The moss tint this
/// replaced failed exactly here.
///
/// **The ground list is hand-maintained**, so a future `night*` token darker
/// than #0B0C0A would not be picked up. Its membership, with the overlap stated
/// rather than left to arithmetic: `screenBackground` / `nightBackground` are
/// the binding grounds for **all four** consumers — `ResultsView`'s timeline
/// card and `GalleryCatalogRow` are `bubbleBackground` cards, but a radius-2 /
/// y-1 shadow falls *outside* the card onto the screen ground, so their own
/// fill is not what they composite over. `nightBubble` covers the **one**
/// genuinely nested case, `ScenarioArtTile`'s badge overhanging onto the row
/// card, and is margin for the rest. The art tile's own `moss`-wash fill is
/// *lighter* than `nightBubble` on every channel, so a tint below `nightBubble`
/// is below the wash a fortiori and needs no separate entry — which is just as
/// well, since a composite cannot be written as a palette-token reference.
/// `nightPage` is asserted as deliberate margin, reachable by no consumer.
///
/// Arm 3 (`geometryMatchesCodeReviewGatedValues`) is a change-detector, not a
/// correctness check: these values are code-review-gated only (no test renders
/// them — ADR-009), so a failure is not a bug. It means the token drifted,
/// typically in an unrelated refactor — confirm the change passed review, then
/// update the expected value. It replaces the `softShadowIsMossTinted` /
/// `tightShadowIsMossTinted` pair that lived in `DesignTokensTests`, whose
/// names asserted the opposite of the shipped value once the tint changed.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct PasturaShadowsTests {

  private var entries: [PasturaShadow] { PasturaShadows.all }

  private var grounds: [PasturaColorValue] {
    [
      PasturaPalette.screenBackground,
      PasturaPalette.nightBackground,
      PasturaPalette.nightBubble,
      PasturaPalette.nightPage
    ]
  }

  @Test func tintIsDarkerThanEveryGroundItCanCover() {
    // Fires when `all` changes, which is the *correct* edit — bump it and
    // confirm the new layer was meant to join the recipe. It cannot catch the
    // omission `PasturaShadows.all`'s own doc comment warns about (an enum
    // member added and not listed there): `entries` IS `all`, so that case
    // leaves the count at 2 and passes.
    #expect(entries.count == 2, "`all` changed — bump this pin deliberately.")
    for entry in entries {
      for ground in grounds {
        #expect(entry.color.red < ground.red)
        #expect(entry.color.green < ground.green)
        #expect(entry.color.blue < ground.blue)
      }
    }
  }

  /// Both families reuse the scrim's tint so the palette carries **one**
  /// occluder near-black rather than three. That relationship is asserted
  /// nowhere else: the hex is written literally at each entry, because
  /// referencing `PasturaPalette.scrim` would break the `hex:opacity:` shape
  /// `check_design_tokens_css.py` matches on.
  @Test func tintIsTheScrimTint() {
    for entry in entries {
      #expect(entry.color.red == PasturaPalette.scrim.red)
      #expect(entry.color.green == PasturaPalette.scrim.green)
      #expect(entry.color.blue == PasturaPalette.scrim.blue)
    }
  }

  @Test func geometryMatchesCodeReviewGatedValues() {
    let tight = PasturaShadows.tight
    #expect(tight.color.opacity == 0.03)
    #expect(tight.radius == 2)
    #expect(tight.x == 0)
    #expect(tight.y == 1)

    let soft = PasturaShadows.soft
    #expect(soft.color.opacity == 0.13)
    #expect(soft.radius == 26)
    #expect(soft.x == 0)
    #expect(soft.y == 12)
  }
}
