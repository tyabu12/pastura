import Foundation
import Testing

@testable import Pastura

// The pure predicates behind `DesignTokensTests+NightRemainder.swift`'s slice-4
// guards. Each has a matched control **in that file**, which is the whole reason
// they are functions rather than inline expressions: a predicate inlined into its
// success case cannot be handed a broken input.
//
// Split out of `DesignTokensTests+NightRemainder.swift` during slice 4's review,
// on the same grounds as `DesignTokens+NightStatePalette.swift`: that file stood
// at 399 lines against swiftlint's 400-line `file_length` cap (default, and
// `--strict` in the pre-commit hook makes it an error, not a warning), so the
// review's own finding — an on-accent control that needed ~15 more lines — could
// not land without either trimming rationale or moving structure. Trimming
// rationale to satisfy a line count is the wrong trade, so the structure moved.
//
// The axis is predicates-vs-tests rather than per-section, because the addition
// touched a predicate's control coverage rather than a section: ADR-028's
// "split by what the addition touches" applied to a test file. Note this is NOT
// the value-vs-invariant axis slice 3 declined for the *source* files — there the
// invariant file was shared across sections, whereas here every predicate serves
// the one sibling.
//
// **File-scope, so each helper needs its own explicit `@MainActor`.** These read
// MainActor-isolated `PasturaPalette` statics from a nonisolated test module —
// `.claude/rules/swift-isolation.md` § Pattern 5 "Cross-module corollary". The
// parent suite's `@MainActor` does not reach file-scope functions.
//
// Reaches `relativeLuminance` / `contrastRatio` at the foot of
// `DesignTokensTests+NightPalette.swift`.

/// True when every token is strictly brighter than the one before it.
@MainActor
func isStrictlyBrightening(_ tokens: [PasturaColorValue]) -> Bool {
  zip(tokens, tokens.dropFirst()).allSatisfy { relativeLuminance($0) < relativeLuminance($1) }
}

/// True when an on-accent foreground clears WCAG's text bar (4.5:1) over the
/// emphatic fill AND the 1.4.11 non-text bar (3:1) over the base fill. Both bars
/// together are the contract §2.3 documents; either alone would pass a value
/// that fails in half the app.
///
/// Both clauses have their own control, because a single control that fails both
/// is no evidence that either is separately enforced:
/// `onAccentForegroundControlRejectsHoldingWhiteInDark` fails the 4.5 clause (and
/// the 3.0 one with it), and
/// `onAccentForegroundControlRejectsAValueThatClearsOnlyTheEmphaticBar` fails the
/// 3.0 clause **alone** — delete `&& contrastRatio(foreground, baseFill) >= 3.0`
/// and only the second reddens.
@MainActor
func onAccentForegroundClearsItsBars(
  foreground: PasturaColorValue, emphaticFill: PasturaColorValue, baseFill: PasturaColorValue
) -> Bool {
  contrastRatio(foreground, emphaticFill) >= 4.5 && contrastRatio(foreground, baseFill) >= 3.0
}

/// True when a hairline sits **lighter** than the surface it is drawn on and is
/// separable from both that surface and the ground behind it.
///
/// The direction clause is not decoration: `contrastRatio` is symmetric, so the
/// two separability clauses alone also admit a line *darker* than both — which
/// would pass a test whose name promises inversion.
/// `quietLineControlRejectsALineDarkerThanBothAtAdequateSeparation` constructs one
/// and is the only evidence that direction is enforced.
///
/// **The `ground` clause cannot currently bind, and that is a property of the
/// topology rather than of the values.** `contrastRatio` is monotone in Y, so once
/// `line` is lighter than `surface` and the ground is *below* the surface —
/// `nightBackground` sits under both `nightPromoBackground` and `nightBubble` — then
/// `cr(line, ground) >= cr(line, surface) >= 1.1` is entailed. Every shipped call
/// site has that sunken-ground shape. The clause is kept rather than deleted
/// because it becomes load-bearing the moment a hairline is drawn on a surface that
/// sits *below* its ground (a line on `nightPage` under `nightBackground`, say),
/// and a future call site of that shape would otherwise lose the check silently.
/// It is documented as inert-by-topology so nobody mistakes it for a guard that has
/// been exercised.
///
/// **The `surface` separability clause, unlike the `ground` one, *can* bind and
/// now has its own control.** Given the direction clause the window is
/// `Y_surface < Y_line < 1.1 * Y_surface + 0.005`, which for `nightBubble` spans
/// seven 8-bit greys rather than none — the first draft of this note claimed it was
/// narrower than one step and was simply wrong.
/// `quietLineControlRejectsALineTooCloseToItsSurface` sits mid-window at `#323232`
/// (1.061 against the surface, 1.327 against the ground), so it fails the surface
/// clause **alone** and reddens if that clause is deleted.
///
/// The 1.1 bar is a floor, not a derived threshold. It sits **below** the quietest
/// shipped hairline (`nightRule` against `nightBubble`, 1.139) with a deliberate
/// margin so no existing token rests on the boundary — which means it rejects a
/// line *substantially* quieter than anything shipped, not a marginally quieter
/// one: a new line in [1.100, 1.139) still passes. Do not tighten it to 1.139
/// (`nightRule` would sit exactly on it) or loosen it further.
@MainActor
func lineSeparatesSurfaceFromGround(
  line: PasturaColorValue, surface: PasturaColorValue, ground: PasturaColorValue
) -> Bool {
  relativeLuminance(line) > relativeLuminance(surface)
    && contrastRatio(line, surface) >= 1.1 && contrastRatio(line, ground) >= 1.1
}

/// Max minus min sRGB channel — a chroma proxy that needs no colour-space
/// conversion. Used only to discriminate a moss token from a neutral one at the
/// same luminance.
@MainActor
func channelSpread(_ token: PasturaColorValue) -> Double {
  max(token.red, max(token.green, token.blue)) - min(token.red, min(token.green, token.blue))
}
