import SwiftUI

// Extended palette tokens that arrived after the §2.1–§2.5 base palette.
// Lives in an extension so `DesignTokens.swift` stays under swiftlint's
// 400-line `file_length` cap. Source of truth in
// `docs/design/design-system.md` §2.6 onward — plus one §2.2 token
// (`inkOnAccent`) parked here for that same headroom; see the first MARK.
//
// Some tokens here are not consumed yet (time-of-day, chart) — they are
// documented and defined ahead of need so future screens can pull from a single
// canonical palette without inventing one-off hex literals.
//
// The §2.9 dark-mode tokens used to live here; they now have their own file,
// `DesignTokens+NightPalette.swift` — see its header for the split axis and
// for why the `DesignTokens` filename prefix is load-bearing.

extension PasturaPalette {

  // MARK: §2.2 Ink — on-accent foreground
  //
  // Documented under §2.2 rather than §2.6+, unlike everything else in this
  // file. It is here because this extension is where `swiftui-traps.md`'s
  // token workflow puts a new raw token, not because §2.2 was full.

  /// Foreground for text / glyphs sitting **on an accent fill** (`moss`,
  /// `mossDark`). §2.3 sanctions white-on-accent in light, which is distinct
  /// from §1's "avoid pure white surfaces" guidance — that one concerns
  /// backgrounds.
  ///
  /// **Resolved (ADR-028 gate 1)**: paired, not `nightMoss` darkened. Dark
  /// value `nightInkOnAccent` #2C2F28 — a near-ground tone, not white
  /// (Material 3 flips on-primary tone 100 → 20 when primary goes 40 → 80).
  /// Darkening `nightMoss` instead would have invalidated three shipped
  /// slices anchored on its current RGB: §2.7's four washes are built on it,
  /// §2.4's dot ladder is anchored on it, and §2.5's body window reads its
  /// 8.00:1 against `nightBackground` as a ceiling. Over `mossDark`,
  /// `nightInkOnAccent` measures ≈7.12:1 (AAA); over base `moss`, ≈6.40:1.
  ///
  /// Scope: `mossDark` is the only fill where the pair clears AA for **text**
  /// in both appearances (light ≈4.74:1, dark ≈7.12:1). On base `moss` it is
  /// ≈3.03:1 in light / ≈6.40:1 in dark — light clears WCAG 1.4.11's 3:1
  /// non-text bar for glyphs and shapes (`CheckBadge`, the share-tab symbols)
  /// but not the 4.5:1 text bar, so text on an accent belongs on `mossDark`.
  static let inkOnAccent = PasturaColorValue(hex: 0xFFFFFF)

  // MARK: §2.6 Alert Family — 4-step temperature scale
  //
  // Each level has three variants:
  // - base: the core hue, suitable for icons / strong text.
  // - *Soft: lightly tinted background fill (cards, toasts, badges).
  // - *Ink: high-contrast text color over the soft background.
  //
  // Pastoral-tone discipline: a "Cancel" button is **not** rendered with
  // `danger`. Cancel stays neutral — `inkSecondary` text + `rule` border
  // — to preserve the calm, non-alarming voice. Reserve `danger` for the
  // primary button of a destructive confirmation dialog (where iOS
  // permits custom styling) and for actually-destructive states.

  /// Neutral notification — "新しいデモが届きました" kind of moments.
  static let info = PasturaColorValue(hex: 0x7B8FA8)
  /// Soft background fill paired with `info`.
  static let infoSoft = PasturaColorValue(hex: 0xE8EDF2)
  /// High-contrast text color over `infoSoft`.
  static let infoInk = PasturaColorValue(hex: 0x4A5A6F)

  /// Positive completion — DL completed, save succeeded.
  static let success = PasturaColorValue(hex: 0x7A9270)
  static let successSoft = PasturaColorValue(hex: 0xE5ECDF)
  static let successInk = PasturaColorValue(hex: 0x4D5F44)

  /// Caution / awaiting confirmation — "DLが一時停止されました".
  static let warning = PasturaColorValue(hex: 0xC7A566)
  static let warningSoft = PasturaColorValue(hex: 0xF2EAD3)
  static let warningInk = PasturaColorValue(hex: 0x6F5C2D)

  /// Full-bleed occlusion scrim — the dimming layer behind a blocking
  /// overlay (`SimulationView.loadingScrim`). Opacity is part of the token, so
  /// the callsite reads it whole.
  ///
  /// **Fixed in both appearances, and deliberately has no `Color.*` alias** —
  /// same family as ``PasturaShadows``. An occluder's requirement is not "match
  /// the appearance" but "be darker than whatever it covers", and a paired
  /// alias inverts: `Color.ink` resolved `nightInk` and composited *lighter*
  /// than the night ground, so the scrim brightened the screen instead of
  /// dimming it (#1284). A fixed value only satisfies the requirement when it
  /// sits below every ground, which is why this is near-black rather than
  /// `ink` — `ink` #2D2E26 over `nightBackground` #1B1D17 composites to
  /// #22241D, *lighter* than its ground, and over `nightBubble` it moves one
  /// channel by one step. Warm near-black rather than #000000 to stay in the
  /// palette's register; §2.2's "not pure black" concerns text, not occluders.
  ///
  /// Being alias-less puts it outside ADR-028 gate 1's predicate, which reads
  /// the `Color` extension. Recorded here and in ADR-028 as fixed-in-both, the
  /// same answer gate 1's second branch accepts.
  static let scrim = PasturaColorValue(hex: 0x0B0C0A, opacity: 0.4)

  /// Destructive / irrevocable action — primary button of a confirmation
  /// dialog ("会話を削除しますか？"). Not for plain Cancel buttons.
  static let danger = PasturaColorValue(hex: 0xB57870)
  static let dangerSoft = PasturaColorValue(hex: 0xEDD9D4)
  static let dangerInk = PasturaColorValue(hex: 0x6F4540)

  // MARK: §2.7 Interactive States
  //
  // Tap-feedback overlays for actionable surfaces. The hover/pressed/
  // selected tints carry their own alpha so they composite over any
  // underlying surface. Disabled states have explicit text + bg colors
  // because the right answer there is "drain saturation," not "mix
  // alpha."

  /// Hover-state moss tint, rgba(138, 154, 108, 0.06).
  static let hover = PasturaColorValue(
    red: 138.0 / 255.0, green: 154.0 / 255.0, blue: 108.0 / 255.0, opacity: 0.06)
  /// Pressed-state moss tint, rgba(138, 154, 108, 0.12).
  static let pressed = PasturaColorValue(
    red: 138.0 / 255.0, green: 154.0 / 255.0, blue: 108.0 / 255.0, opacity: 0.12)
  /// Selected-state moss tint, rgba(138, 154, 108, 0.18).
  static let selected = PasturaColorValue(
    red: 138.0 / 255.0, green: 154.0 / 255.0, blue: 108.0 / 255.0, opacity: 0.18)
  /// Focus-ring stroke (apply with 2pt outline + 2pt offset). Same hex
  /// as `moss`, but a distinct semantic anchor so a future shift in
  /// brand color doesn't accidentally redefine focus appearance.
  static let focusRing = PasturaColorValue(hex: 0x8A9A6C)
  /// Disabled-state text color (drained ink).
  static let disabledText = PasturaColorValue(hex: 0xB5B0A2)
  /// Disabled-state surface fill.
  static let disabledBackground = PasturaColorValue(hex: 0xECE7DA)

  // MARK: §2.8 Link / Action
  //
  // `link` has 5 live consumers today (`SettingsView.swift:317,336` `.tint`;
  // `SettingsView+Feedback.swift:79,82`; `ViewerPredictionSheet.swift:110`) —
  // not reserved. `linkVisited` / `linkHover` genuinely have zero consumers;
  // defined so the first hover/visited state to land doesn't invent a
  // one-off blue. All three are paired (ADR-028): dark halves `nightLink` /
  // `nightLinkVisited` / `nightLinkHover`.

  /// Link in its default (unvisited) state.
  static let link = PasturaColorValue(hex: 0x5D7A4D)
  /// Link after being followed at least once in this session.
  static let linkVisited = PasturaColorValue(hex: 0x6F6753)
  /// Link while hovered (or on iPadOS pointer hover).
  static let linkHover = PasturaColorValue(hex: 0x4A6438)

  // MARK: §2.10 Time-of-Day (decorative ambient)
  //
  // Reserved for ambient surface tints — header bands, hero gradients,
  // decorative drop shadows that hint at "the pasture at this hour."
  // `noon` and `night` overlap structurally with `screenBackground`
  // and `nightBackground` but carry distinct intent (ambient vs.
  // structural surface), so they live as their own tokens.

  /// Morning-mist warmth.
  static let dawn = PasturaColorValue(hex: 0xF4E5CD)
  /// Crisp midday — same hex as `screenBackground`.
  static let noon = PasturaColorValue(hex: 0xFCFAF4)
  /// Sunset / evening warmth.
  static let dusk = PasturaColorValue(hex: 0xE5D4C2)
  /// Deep night — same hex as `nightBackground`.
  static let night = PasturaColorValue(hex: 0x1B1D17)

  // MARK: §2.11 Chart (4-color minimum set)
  //
  // Reserved for future data visualization. Each entry is a
  // hex-equivalent alias of an existing token so adopting charts
  // doesn't enlarge the visual language. Charts are discouraged in
  // Pastura's current vocabulary; if more than 4 categories arrive,
  // revisit the visualization choice rather than expanding the palette.

  /// Chart category 1 — same hex as `moss`.
  static let chart1 = PasturaColorValue(hex: 0x8A9A6C)
  /// Chart category 2 — same hex as `warning`.
  static let chart2 = PasturaColorValue(hex: 0xC7A566)
  /// Chart category 3 — same hex as `info`.
  static let chart3 = PasturaColorValue(hex: 0x7B8FA8)
  /// Chart category 4 — same hex as `danger`.
  static let chart4 = PasturaColorValue(hex: 0xB57870)

  // MARK: §2.12 Header Slots — GameHeader (Demo / Sim shared)
  //
  // Role-anchored tokens for the GameHeader 2-row layout (`title` row +
  // `meta` row). Named after their slot rather than depth-tone preset so a
  // future change in chat-stream's L1..L4 family scale (§2.4) does not
  // ripple into header-bar styling. Hex values overlap with the L-family
  // by coincidence — `headerMetaInk` is the same hex as `metaBaseL3` —
  // but the semantic role (header phase-name vs DL-progress meta) is
  // distinct, so do NOT collapse to a single token.

  /// GameHeader meta-row middle-dot separator (`·`). Lighter than
  /// general-purpose `rule` (#E0DBCE) so it reads as a typographic
  /// separator inside one mono line, not as a layout divider.
  static let headerRule = PasturaColorValue(hex: 0xC2C0AE)
  /// GameHeader meta-row phase-name foreground. Same hex as `metaBaseL3`
  /// (#4A4E3D) but role-anchored to the header slot.
  static let headerMetaInk = PasturaColorValue(hex: 0x4A4E3D)
  /// GameHeader meta-row subdued foreground (tok/s right side). Sits
  /// between `muted` and `metaBaseL2` in lightness; chosen so the
  /// inference-rate value reads as secondary information without
  /// collapsing into the meta-row separator.
  ///
  /// **Fixed in both appearances — do not pair it.** Read
  /// `DesignTokens+NightPalette.swift`'s §2.12 MARK before changing this value:
  /// the lightness note above is a derivation record for the light value, and
  /// mirroring it into dark is the specific mistake that decision rejected.
  /// Guarded by `headerMetaSubduedReadsTheSameOnBothGrounds`.
  static let headerMetaSubdued = PasturaColorValue(hex: 0x7B7D68)
}
