import SwiftUI

// §4.3's shadow recipe — the two-layer drop shadow shared by the app's cards.
// Split out of `DesignTokens.swift` for the same reason
// `DesignTokens+OccluderShadows.swift` was: that file sits near swiftlint's
// 400-line `file_length` cap, which the pre-commit hook runs under `--strict`.
// The `DesignTokens` filename prefix is load-bearing — `scripts/check_design_tokens_css.py`
// globs `Pastura/Pastura/Views/DesignTokens*.swift` and would silently stop
// mirroring these values against `docs/design/ds/tokens.css` if the file were
// renamed out of it.

// MARK: - §4.3 Shadow tokens

// `x` / `y` mirror SwiftUI's own `.shadow(color:radius:x:y:)` parameter names,
// so they stay one character. `DesignTokens.swift` carries the same file-level
// exemption for the same class of reason — short domain identifiers, though
// there they are `hexString`'s `r`/`g`/`b` and `Spacing.s`/`m`/`l` rather than
// framework parameter mirrors. The directive sits ahead of the doc comment
// rather than between it and the declaration, which would orphan it
// (`.claude/rules/build-traps.md`).
// swiftlint:disable identifier_name

/// A single shadow layer matching SwiftUI's `.shadow(color:radius:x:y:)` shape.
///
/// CSS source (`design-system.md` §4.3) uses a negative spread on the second
/// layer (`-12px`). SwiftUI's built-in `.shadow` has no spread parameter, so
/// the spread is dropped; the visual approximation is close enough for the
/// soft-shadow use case. If the exact spread matters for a specific surface,
/// reach for a custom `.background { ... }` mask — but do not add spread
/// handling to this token type without revisiting design-system.md §4.3 first.
struct PasturaShadow: Sendable, Equatable {
  let color: PasturaColorValue
  let radius: CGFloat
  let x: CGFloat
  let y: CGFloat
}

// swiftlint:enable identifier_name

/// Two-layer drop-shadow recipe from `design-system.md` §4.3 — the app's
/// general card elevation.
///
/// Apply by stacking both `.shadow(...)` modifiers on the same view:
/// ```
/// view
///   .shadow(
///     color: PasturaShadows.tight.color.color,
///     radius: PasturaShadows.tight.radius,
///     x: PasturaShadows.tight.x,
///     y: PasturaShadows.tight.y)
///   .shadow(
///     color: PasturaShadows.soft.color.color,
///     radius: PasturaShadows.soft.radius,
///     x: PasturaShadows.soft.x,
///     y: PasturaShadows.soft.y)
/// ```
///
/// ## Why the tint is a near-black and not moss
///
/// It was `rgba(90,100,60)` until #1378. A shadow's requirement is that its
/// tint be **darker than every ground it covers** — `a·C + (1−a)·ground`
/// cannot fall below `ground` when `C` is lighter than it, whatever `a` is —
/// and moss is lighter than every dark-mode surface in the palette, so all
/// four consumers rendered a green glow rather than a shadow. This is the
/// same conclusion `PasturaPalette/scrim` and ``PasturaOccluderShadows``
/// reached; the value is shared with them so the palette carries **one**
/// occluder near-black, not three.
///
/// A near-black cannot carry a moss cast at these alphas, so the light-mode
/// shadow is now neutral. Light *lightness* is preserved instead, to within one
/// sRGB step — the alphas were re-solved on the red channel over
/// `screenBackground` and then rounded (0.0269 → 0.03, 0.1344 → 0.13), which
/// moves light red by −0.75 and +1.07 respectively. The arithmetic
/// and the per-consumer measurements live in design-system §4.3 and ADR-028
/// § Amendment; do not restate them here.
///
/// The tints are written as `PasturaColorValue(hex:opacity:)` rather than
/// built from a bare token, because that is the shape
/// `check_design_tokens_css.py` converts to `rgba(...)` — it keeps the alphas,
/// the drift-prone half, inside the mirror gate.
enum PasturaShadows {
  /// Inner tight layer — `0 1px 2px rgba(11,12,10,.03)`.
  static let tight = PasturaShadow(
    color: PasturaColorValue(hex: 0x0B0C0A, opacity: 0.03),
    radius: 2, x: 0, y: 1)
  /// Outer soft layer — `0 12px 26px -12px rgba(11,12,10,.13)` (spread dropped).
  static let soft = PasturaShadow(
    color: PasturaColorValue(hex: 0x0B0C0A, opacity: 0.13),
    radius: 26, x: 0, y: 12)

  /// Every member, for the tests to iterate. A layer added above and not
  /// listed here is covered by nothing.
  static let all: [PasturaShadow] = [tight, soft]
}
