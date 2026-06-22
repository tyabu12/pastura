import SwiftUI

/// Layout + timing tokens for the `.languageMismatch` drift toast rendered
/// by ``SimulationView`` (`languageDriftToast`).
///
/// These constants are extracted from the View so
/// `LanguageDriftToastLayoutTests` can act as a **change-detector
/// tripwire**. The toast's rendered appearance is code-review-gated only
/// (ADR-009 decision 3 — frame / animation-timing bugs are out of scope
/// for automated tests, and the DEBUG-only manual trigger that let a
/// human *see* the toast was removed in #455). The tripwire does NOT
/// verify rendered appearance; it fails when a token drifts silently in a
/// refactor, forcing the editor to consciously confirm a code-review-gated
/// visual / timing change. See issue #456 / ADR-009 § Amendment 2026-06-23.
///
/// `font` is deliberately NOT a token here: `SwiftUI.Font` is not
/// `Equatable`, so it cannot back a value-mirror assertion. The toast's
/// `.font(.caption)` stays inline in the View, code-review-gated alongside
/// the other rendered-appearance concerns.
enum LanguageDriftToastLayout {
  /// Overlay anchor — the toast sits over the chat-stream area at the top,
  /// NOT inside `GameHeader`'s frosted strip.
  static let overlayAlignment: Alignment = .top

  /// Auto-dismiss delay. Long enough for a glance, short enough that a
  /// drift burst doesn't keep the toast pinned.
  static let autoDismissSeconds: Double = 4

  /// Horizontal inset of the capsule's text content.
  static let contentHorizontalPadding: CGFloat = 12

  /// Vertical inset of the capsule's text content.
  static let contentVerticalPadding: CGFloat = 8

  /// Gap between the toast capsule and the top safe-area edge.
  static let topInset: CGFloat = 8

  /// Horizontal margin from the screen edges.
  static let edgeHorizontalPadding: CGFloat = 16
}
