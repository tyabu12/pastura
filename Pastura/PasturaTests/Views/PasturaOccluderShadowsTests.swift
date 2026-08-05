import SwiftUI
import Testing

@testable import Pastura

/// Guards `PasturaOccluderShadows` (§4.3's occlusion-shadow family) against
/// two independent failure modes.
///
/// Arm 1 (`tintIsDarkerThanEveryGroundTheFamilyCanCover`) states the actual
/// requirement the family exists to hold: the tint must be darker, per
/// channel, than every ground it can composite over — `a·C + (1−a)·ground`
/// can only fall below `ground` when `C` is below it, independent of `a`, so
/// the assertion belongs on the tint, not on any composite.
///
/// **Both lists it iterates are hand-maintained**, and they fail differently.
/// The entries come from `PasturaOccluderShadows.all`, so a new member that is
/// added to the enum but not to `all` is covered by nothing and this suite stays
/// green — that is the likelier drift. The ground list is the milder one: a
/// future `night*` token darker than #0B0C0A would not be picked up here. Only
/// `nightBackground` is a binding ground for the current members; `nightBubble`
/// and `nightPage` are asserted as deliberate margin, not because a member sits
/// on them.
///
/// Arm 2 (`geometryMatchesCodeReviewGatedValues`) is a change-detector, not a
/// correctness check: these values are code-review-gated only (no test
/// renders them — see `swiftui-traps.md` § "An occlusion layer ... must not
/// read a paired `Color.*` alias"), so a failure here is not a bug. It means
/// the token drifted, typically in an unrelated refactor — confirm the
/// change passed review, then update the expected value.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct PasturaOccluderShadowsTests {

  private var entries: [PasturaShadow] { PasturaOccluderShadows.all }

  private var grounds: [PasturaColorValue] {
    [
      PasturaPalette.screenBackground,
      PasturaPalette.nightBackground,
      PasturaPalette.nightBubble,
      PasturaPalette.nightPage
    ]
  }

  @Test func tintIsDarkerThanEveryGroundTheFamilyCanCover() {
    #expect(entries.count == 3, "A member was added without extending `all`.")
    for entry in entries {
      for ground in grounds {
        #expect(entry.color.red < ground.red)
        #expect(entry.color.green < ground.green)
        #expect(entry.color.blue < ground.blue)
      }
    }
  }

  /// The family's whole design rests on it being the *scrim's* tint — one
  /// occluder near-black in the palette, not two. That relationship is asserted
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
    let card = PasturaOccluderShadows.modelPickerCard
    #expect(card.color.opacity == 0.1)
    #expect(card.radius == 14)
    #expect(card.x == 0)
    #expect(card.y == 12)

    let cta = PasturaOccluderShadows.modelPickerCTA
    #expect(cta.color.opacity == 0.36)
    #expect(cta.radius == 8)
    #expect(cta.x == 0)
    #expect(cta.y == 6)

    let pill = PasturaOccluderShadows.inFlightPill
    #expect(pill.color.opacity == 0.1)
    #expect(pill.radius == 8)
    #expect(pill.x == 0)
    #expect(pill.y == 2)
  }
}
