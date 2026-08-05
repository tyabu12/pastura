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
// exemption for the same reason; the directive sits ahead of the doc comment
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

/// Two-layer moss-tinted shadow recipe from `design-system.md` §4.3.
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
enum PasturaShadows {
  /// Inner tight layer — `0 1px 2px rgba(90,100,60,.04)`.
  static let tight = PasturaShadow(
    color: PasturaColorValue(
      red: 90.0 / 255.0, green: 100.0 / 255.0, blue: 60.0 / 255.0, opacity: 0.04),
    radius: 2, x: 0, y: 1)
  /// Outer soft layer — `0 12px 26px -12px rgba(90,100,60,.2)` (spread dropped).
  static let soft = PasturaShadow(
    color: PasturaColorValue(
      red: 90.0 / 255.0, green: 100.0 / 255.0, blue: 60.0 / 255.0, opacity: 0.2),
    radius: 26, x: 0, y: 12)
}
