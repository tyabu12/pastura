import SwiftUI

/// Displays a phase type as a moss / ink-secondary capsule badge: a leading
/// `PhaseGlyph` SF Symbol + the localized phase display name.
///
/// Used inline within an `AgentOutputRow` name row, in the editor's
/// `PhaseBlockRow`, and standalone as a `phaseStarted` log entry in
/// `SimulationView`. The capsule shape + tag typography carries the
/// "this is a phase marker" semantic; color distinguishes LLM-driven
/// phases (moss, the only brand accent) from code-driven phases
/// (ink-secondary, muted neutral). Glyph vocabulary is the shared
/// `PhaseGlyph` SSOT (#860).
///
/// The text is the localized `PhaseDisplayName.label(for:)` — the shared
/// human-readable source of truth — never the snake_case `rawValue`
/// (#882: raw `speak_all` etc. must not surface in the UI).
struct PhaseTypeLabel: View {
  let phaseType: PhaseType

  var body: some View {
    HStack(spacing: 4) {
      // Phase glyph from the shared `PhaseGlyph` SSOT (#860) — the same
      // symbol vocabulary the gallery "What happens" steps use, so one
      // visual language reads across Sim and the Editor. Decorative:
      // the adjacent display-name Text carries the phase identity, so hide
      // the glyph from VoiceOver rather than announce the raw symbol name.
      Image(systemName: PhaseGlyph.symbolName(for: phaseType))
        .imageScale(.small)
        .accessibilityHidden(true)
      Text(PhaseDisplayName.label(for: phaseType))
    }
    .textStyle(Typography.tagPhase)
    .padding(.horizontal, 8)
    .padding(.vertical, 3)
    // Capsule fill at 15% opacity is load-bearing: without it the
    // label reads as inline text and loses its "badge" affordance
    // (critic Axis 5). Keep the capsule even if the tint palette
    // shifts further.
    .background(badgeFill.opacity(0.15), in: Capsule())
    .foregroundStyle(badgeText)
  }

  /// Text tint — each arm reads its family's `*OnWash` role token, never the
  /// token filling the capsule under it.
  ///
  /// **The two arms' figures use different grounds and are not comparable.** The
  /// ink numbers are the worst-case-per-appearance convention (`screenBackground`
  /// light / `nightBubble` dark) that `DesignTokensTests+InkOnWash` asserts; the
  /// moss numbers are inherited #1327 **per-site** figures on this capsule's own
  /// ground. Do not read one against the other as a before/after.
  ///
  /// §2.3 enumerates `moss` for fills / borders, so the readable foreground is a
  /// darker step — but not the `moss-dark` §2.3 lists for accent text: over this
  /// capsule's own `moss` @0.15 wash that measures only ≈4.11:1 in light, under
  /// the 4.5:1 bar at `tagPhase`'s 9.5pt. `moss-on-wash` takes it to ≈6.06:1
  /// (#1327).
  ///
  /// The code-driven arm is the **opposite asymmetry**, which is why it was
  /// fixed separately: `ink-secondary` on its own @0.15 wash is 5.350:1 in light
  /// but **4.501:1** in dark — on the bar, green by 0.001. `ink-on-wash` takes
  /// dark to 5.090:1 and leaves light identical, its two halves being
  /// byte-identical (#1408).
  ///
  /// Internal, not `private`, so `PhaseTypeLabelTokenTests` can pin which token
  /// each arm routes to. That pin is not optional bookkeeping: #1327 repointed
  /// this same accessor and the structural `PhaseTypeLabelTests` did not notice,
  /// which is how its doc comment went stale for two releases.
  var badgeText: Color {
    if phaseType.requiresLLM {
      Color.mossOnWash
    } else {
      Color.inkOnWash
    }
  }

  /// Capsule fill (rendered at 15% opacity). LLM phases use the lighter
  /// `moss` so the wash reads as a soft tint; if we used `moss-dark`
  /// here too, the 0.15 wash would skew olive-brown and clash with the
  /// readable text on top. Code phases fill with `ink-secondary`, which is
  /// where the label used to read from as well — #1408 moved the label to
  /// `ink-on-wash` and left the fill here, so the two are no longer one token.
  ///
  /// Internal for the same reason as ``badgeText`` — the pin covers both, so a
  /// future edit cannot repoint one and leave the other behind.
  var badgeFill: Color {
    if phaseType.requiresLLM {
      Color.moss
    } else {
      Color.inkSecondary
    }
  }
}
