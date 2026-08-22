//
// The two arms #1448 batch 4 added, split out of
// `DesignTokensTests+MutedTranscript` at SwiftLint's 400-line `file_length`
// cap (`.claude/rules/testing.md` § "Splitting a Suite Across Files") — an
// extension of the same suite, never a second `@Suite`.
//
// Neither arm belongs to that file's subject. `+MutedTranscript` pins the
// three-digit figures `docs/**` prints and is anchored by
// `scripts/check-measurement-transcripts.py` on `FIXTURE_PATH` / `OPAQUE_DECL`
// / `WASH_DECL`; these two transcribe nothing and are reached by none of those
// anchors. They assert the *routing rules* design-system §8 gained in batch 4:
// the side condition on the direction argument, and the after-figure for a site
// whose ground is a §2.7 state overlay.

import SwiftUI
import Testing

@testable import Pastura

extension DesignTokensTests {

  // MARK: - Direction-argument negative control (#1448 batch 4)

  /// design-system §8's direction-argument side condition cites this arm **by
  /// name**. "The replacement is darker in light, so contrast rises" is
  /// guaranteed only while the ground is lighter than `muted` itself; this is
  /// the counterexample §8 points at. Note where the ground sits: darker than
  /// `muted` but **lighter than `inkSecondary`** — the inversion begins in the
  /// band *between* the two foregrounds, not below both, which is why "my
  /// ground is not as dark as the replacement" is the wrong safety test. The
  /// figures live only here, as comparisons, never transcribed into the docs.
  ///
  /// No shipped site reaches it today. The nearest is the ledger row
  /// `SimulationView` · loading-scrim subtitle: §5 records `.regularMaterial`,
  /// but that sits over `SimulationScrimStyle.fill` (a near-black), making it
  /// the one shipped surface plausibly inside the band. It is **retained**, so
  /// nothing repoints there now; a later batch must measure instead.
  @Test func directionArgumentInvertsOnAGroundDarkerThanMuted() {
    let midDarkGround = PasturaColorValue(hex: 0x666666)

    // Negative case: `muted` contrasts MORE than the replacement would here,
    // since it sits farther from a dark ground than `inkSecondary` does.
    let mutedOnMidDark = contrastRatio(PasturaPalette.muted, midDarkGround)
    let inkSecondaryOnMidDark = contrastRatio(PasturaPalette.inkSecondary, midDarkGround)
    #expect(
      mutedOnMidDark > inkSecondaryOnMidDark,
      "expected the direction argument to invert on a ground darker than muted")

    // Companion positive case: on `screenBackground` — lighter than `muted`,
    // like every ground §3.1 measures — the ordering is the other way round.
    let mutedOnScreen = contrastRatio(PasturaPalette.muted, PasturaPalette.screenBackground)
    let inkSecondaryOnScreen = contrastRatio(
      PasturaPalette.inkSecondary, PasturaPalette.screenBackground)
    #expect(
      inkSecondaryOnScreen > mutedOnScreen,
      "expected the direction argument to hold on screenBackground")
  }

  // MARK: - ModelRow after-figure, measured through the overlay (#1448 batch 4)

  /// design-system §8's finding for `ModelRow`: the selected-state background
  /// is `moss@0.06` (light) / `nightMoss@0.06` (dark), which is §2.7's
  /// `hover` value applied as a state overlay rather than a §2.3 wash — the
  /// overlay comes and goes with `isSelected`, so it does not own the row's
  /// ground. Routing stays neutral (`inkSecondary`), but the ratio must still
  /// be measured **through** the overlay rather than against the bare card,
  /// since a selected row really does composite `moss@0.06` on top.
  ///
  /// The composite parameters mirror ``mutedMossWashGrounds``' two `ModelRow`
  /// entries — that pair is the **before** figure (`muted` on this overlay),
  /// this arm the **after** — and their presence is asserted below rather than
  /// cited, since the parameters are re-typed rather than derived.
  ///
  /// Only the composited case is asserted against the bar; the unselected row
  /// is the bare card, already covered by the opaque-ground pins. That is
  /// redundant *only because* the composited ground is the harder one, which
  /// is a claim rather than a given — so it too is asserted here. Were a
  /// future alpha or token change to invert it, this arm would redden instead
  /// of silently guarding the easier case.
  @Test func inkSecondaryClearsTheBarUnderTheSelectionOverlay() {
    let lightGround = composite(
      PasturaPalette.moss, over: PasturaPalette.bubbleBackground, alpha: 0.06)
    let light = contrastRatio(PasturaPalette.inkSecondary, lightGround)
    #expect(light >= Self.contentTextBar, "light selected ModelRow: \(light)")

    let darkGround = composite(
      PasturaPalette.nightMoss, over: PasturaPalette.nightBubble, alpha: 0.06)
    let dark = contrastRatio(PasturaPalette.nightInkSecondary, darkGround)
    #expect(dark >= Self.contentTextBar, "dark selected ModelRow: \(dark)")

    // The before-figures this arm is the after of. Asserted rather than cited:
    // the composite parameters above are re-typed from `mutedMossWashGrounds`,
    // so an alpha or token edit there would silently decouple the pair while
    // both arms stayed green.
    let beforeRows = Set(DesignTokensTests.mutedMossWashGrounds.map(\.name))
    #expect(beforeRows.contains("light ModelRow moss@0.06 over bubbleBackground"))
    #expect(beforeRows.contains("dark ModelRow nightMoss@0.06 over nightBubble"))

    // The redundancy argument above, made executable: the overlay has to be
    // the tighter ground, or asserting it alone would guard the easier case.
    let lightBare = contrastRatio(PasturaPalette.inkSecondary, PasturaPalette.bubbleBackground)
    #expect(light < lightBare, "light: the overlay ground stopped being the tighter one")

    let darkBare = contrastRatio(PasturaPalette.nightInkSecondary, PasturaPalette.nightBubble)
    #expect(dark < darkBare, "dark: the overlay ground stopped being the tighter one")
  }
}
