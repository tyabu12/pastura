import SwiftUI

// The §2.9 dark half of the palette — every `night*` raw token **except §2.5's**,
// which moved to `DesignTokens+AvatarPalette.swift` with its light half when
// slice 4 landed. The qualifier is here because this header used to claim "in one
// file", and someone looking for `nightAvatarBodyAlice` needs telling.
//
// Split out of `DesignTokens+ExtendedPalette.swift` when ADR-028 gate 1's
// slice 2 landed (#1313). The split axis is "the night data leaves the day
// file", chosen so the §2.9 family stays whole: slice 1 was talked out of a
// split on the grounds that it would fragment that family, and splitting by
// section (§2.6-2.7 here, §2.4/§2.12 there) would have done exactly that.
// Arithmetic behind it: at ~4.4 net lines per token, the remaining gate-1
// slices put `DesignTokens+ExtendedPalette.swift` near 470 lines, past
// swiftlint's 400-line `file_length` cap.
//
// **Keep the `DesignTokens` filename prefix.** `check_design_tokens_css.py`
// globs `Pastura/Pastura/Views/DesignTokens*.swift`, and this file is where
// most `night*` hex literals live (§2.5's are in the avatar file, which keeps
// the prefix for the same reason) — rename either out of that glob and the
// `tokens.css` mirror gate goes blind with no signal.
//
// **This file is effectively full** (a few lines under the 400-line cap), and
// gate 1 closing means §2.9 takes no further tokens — an addition needs a split
// first, chosen by what it touches, since "a completed section moves out whole"
// stops discriminating once every section is complete.
//
// Every token here is the dark half of a `PasturaDynamicPalette` pair
// (`DesignTokens+DynamicPalette.swift`), reached through the repointed light
// `Color.*` alias rather than through `Color.night*`. Dark never actually
// renders while `Info.plist` pins `UIUserInterfaceStyle` to Light.

extension PasturaPalette {

  // MARK: §2.9 Dark Mode (night pasture)
  //
  // Day tones translated to a "night pasture" variant — moss brightened,
  // cream replaced by warm dark surfaces. These are **wired**: every token
  // below is the dark half of a `PasturaDynamicPalette` pair, reached through
  // the repointed light `Color.*` alias rather than through `Color.night*`.
  // Dark still never renders, because `Info.plist` pins the app to light — but
  // the reason has changed as of slice 4: **no light token owes gate 1 a dark
  // value any more** (ADR-028 § Rollout gate 1, met). What the lock now waits on
  // is gates 4 and 5 — real-device dark QA across the screens, and the dark
  // share-card path — neither of which any test or measurement can stand in for.

  /// Outermost background under dark mode.
  static let nightBackground = PasturaColorValue(hex: 0x1B1D17)
  /// Speech bubble fill under dark mode.
  static let nightBubble = PasturaColorValue(hex: 0x2C2F28)
  /// Whisper (密談) speech bubble fill under dark mode — a touch mossier
  /// than `nightBubble` so the hushed variant stays legible on the dark
  /// surface. Dark counterpart of `whisperBubble` (#908 PR2).
  static let nightWhisperBubble = PasturaColorValue(hex: 0x2F3626)
  /// Primary body text under dark mode.
  static let nightInk = PasturaColorValue(hex: 0xE8E5D8)
  /// Subtext / section labels under dark mode.
  static let nightInkSecondary = PasturaColorValue(hex: 0xB0AC9C)
  /// Meta info / footnotes under dark mode.
  static let nightMuted = PasturaColorValue(hex: 0x7A7768)
  /// Rule / divider lines under dark mode.
  static let nightRule = PasturaColorValue(hex: 0x353830)
  /// Brand accent under dark mode (brighter to survive the dark surface).
  static let nightMoss = PasturaColorValue(hex: 0xA8B888)

  // MARK: §2.9 Dark counterparts of the §2.6 alert family
  //
  // `*Soft` and `*Ink` INVERT their roles here. Light's pale-fill-plus-dark-text
  // becomes dark-fill-plus-pale-text, so these are NOT the light values run
  // through the base hues' lightness transform — that would put a glaring pale
  // card on a dark surface, against §1's calm voice. Each Ink is placed by
  // target contrast rather than by transform, landing 7.7-8.4:1 over its own
  // Soft. The four Soft fills sit at 1.02-1.08 against `nightBubble`, so hue
  // alone carries the temperature.
  //
  // Design record and the rendered sign-off: `docs/design/ds/colors-states-dark.html`.

  /// Neutral notification under dark mode.
  static let nightInfo = PasturaColorValue(hex: 0x97ABC4)
  /// Dark tinted fill paired with `nightInfo`.
  static let nightInfoSoft = PasturaColorValue(hex: 0x252D37)
  /// High-contrast text over `nightInfoSoft` (7.90:1).
  static let nightInfoInk = PasturaColorValue(hex: 0xB3C5DB)

  /// Positive completion under dark mode.
  static let nightSuccess = PasturaColorValue(hex: 0x95B189)
  /// Dark tinted fill paired with `nightSuccess`.
  ///
  /// Near-identical to `nightWhisperBubble` (contrast 1.003). That is a
  /// faithful mapping, not a collision to fix: light's `successSoft` and
  /// `whisperBubble` are equally close (1.026), and a toast never shares a
  /// surface with a 密談 bubble.
  static let nightSuccessSoft = PasturaColorValue(hex: 0x2A3725)
  /// High-contrast text over `nightSuccessSoft` (8.37:1).
  static let nightSuccessInk = PasturaColorValue(hex: 0xBFDBB3)

  /// Caution / awaiting confirmation under dark mode.
  ///
  /// Deliberately NOT the value a faithful luminance mapping gives (#DBBF8A,
  /// 9.58:1). Preserving luminance order inverts *perceptual* order: in light,
  /// `warning` is the quietest of the four bases against its own ground
  /// (2.23:1, where the others are 3.18-3.42), and mapping luminance faithfully
  /// would make it the loudest in dark. 8.74:1 narrows that gap toward the
  /// other three (6.85-7.24:1) while keeping amber legibly amber.
  static let nightWarning = PasturaColorValue(hex: 0xD4B67E)
  /// Dark tinted fill paired with `nightWarning`.
  static let nightWarningSoft = PasturaColorValue(hex: 0x383124)
  /// High-contrast text over `nightWarningSoft` (8.33:1).
  static let nightWarningInk = PasturaColorValue(hex: 0xE0CEAE)

  /// Destructive / irrevocable action under dark mode. A muted salmon — the
  /// §2.6 rule that red never shouts holds in both appearances.
  static let nightDanger = PasturaColorValue(hex: 0xCE9790)
  /// Dark tinted fill paired with `nightDanger`.
  static let nightDangerSoft = PasturaColorValue(hex: 0x382624)
  /// High-contrast text over `nightDangerSoft` (7.69:1).
  static let nightDangerInk = PasturaColorValue(hex: 0xE0B4AE)

  // MARK: §2.9 Dark counterparts of the §2.7 interactive states
  //
  // The moss tints re-base onto `nightMoss` and raise alpha ~1.33x: a 6% wash
  // of a light moss over #1B1D17 is imperceptible.

  /// Hover-state moss tint under dark mode, rgba(168, 184, 136, 0.08).
  static let nightHover = PasturaColorValue(
    red: 168.0 / 255.0, green: 184.0 / 255.0, blue: 136.0 / 255.0, opacity: 0.08)
  /// Pressed-state moss tint under dark mode, rgba(168, 184, 136, 0.16).
  static let nightPressed = PasturaColorValue(
    red: 168.0 / 255.0, green: 184.0 / 255.0, blue: 136.0 / 255.0, opacity: 0.16)
  /// Selected-state moss tint under dark mode, rgba(168, 184, 136, 0.24).
  static let nightSelected = PasturaColorValue(
    red: 168.0 / 255.0, green: 184.0 / 255.0, blue: 136.0 / 255.0, opacity: 0.24)
  /// Focus-ring stroke under dark mode. Same hex as `nightMoss`, kept as its
  /// own semantic anchor exactly as `focusRing` re-states `moss` in light.
  static let nightFocusRing = PasturaColorValue(hex: 0xA8B888)
  /// Disabled-state text color under dark mode (drained night ink).
  static let nightDisabledText = PasturaColorValue(hex: 0x605F54)
  /// Disabled-state surface fill under dark mode.
  ///
  /// Sinks BELOW `nightBubble` (1.151) rather than rising above it: in dark,
  /// "lighter" already means "raised" — that is what the state washes above do
  /// — so an inert surface has to go the other way. Light's `disabledBackground`
  /// is visible against both the card and the ground (1.235 / 1.183); this
  /// holds the same property (1.151 / 1.086).
  static let nightDisabledBackground = PasturaColorValue(hex: 0x222420)

  // MARK: §2.9 Dark counterparts of the §2.4 meta-contrast presets
  //
  // **The L1→L4 ladder runs the other way here.** In light a higher preset is
  // DARKER, gaining contrast against the pale ground; in dark the same emphasis
  // is BRIGHTER. So this is not the light ladder transformed per token — it is
  // a ladder redesigned against the dark ground, which is what ADR-028's
  // Amendment 2026-07-29 (the #1282 one — two headings share that date) means
  // by naming it the one item no formula covers.
  //
  // Ground: **`nightPromoBackground`**, the real render surface, since slice 4
  // paired `promoBackground`. It was designed against `nightBubble` as a
  // provisional stand-in, under the assumption that the real value would land in
  // #2A2D26-#2F3229 — an assumption, never an asserted range, and it landed just
  // outside. `nightMetaLadderStaysMonotonicAgainstTheCardSurface` carried a
  // tripwire on `promoBackground`'s absence from the pair registry precisely so
  // that pairing it would force a re-measurement; it fired, the ladder was
  // re-measured against the real ground and holds. Figures and the discharged
  // tripwire: `DesignTokensTests+NightMeta`. A band check would have passed by
  // construction — the ladder stays monotone at both ends of that band — which
  // is why slice 2 checked the registry instead.
  //
  // Design record and the rendered sign-off:
  // `docs/design/ds/colors-meta-header-dark.html`.

  /// Meta text, preset L1 (quietest) under dark mode — 3.33:1 on `nightBubble`,
  /// mirroring light's 3.32:1 on `promoBackground`.
  static let nightMetaBaseL1 = PasturaColorValue(hex: 0x7E7F6B)
  /// Emphasis within preset L1 under dark mode (5.67:1, light's ratio exactly).
  static let nightMetaStrongL1 = PasturaColorValue(hex: 0xA0AC88)
  /// Lit progress dot, preset L1 under dark mode.
  ///
  /// Same hex as `nightMoss` — and so also as `nightFocusRing` — exactly as
  /// light's `metaDotOnL1` re-states `moss` and `focusRing` (#8A9A6C). The
  /// three-way coincidence is carried across deliberately, not stumbled into.
  static let nightMetaDotOnL1 = PasturaColorValue(hex: 0xA8B888)

  /// Meta text, preset L2 under dark mode (5.08:1, light's ratio exactly).
  static let nightMetaBaseL2 = PasturaColorValue(hex: 0x9DA08C)
  /// Emphasis within preset L2 under dark mode (9.60:1 vs light's 9.59:1).
  static let nightMetaStrongL2 = PasturaColorValue(hex: 0xD5DBCB)
  /// Lit progress dot, preset L2 under dark mode.
  static let nightMetaDotOnL2 = PasturaColorValue(hex: 0xB7C49C)

  /// Meta text, preset L3 (the documented default) under dark mode — 8.16:1,
  /// mirroring light's 8.19:1. The only preset with app consumers.
  static let nightMetaBaseL3 = PasturaColorValue(hex: 0xC7CABC)
  /// Emphasis within preset L3 under dark mode.
  ///
  /// Ceiling-bound: light is 13.11:1, but `nightBubble` caps at 13.60:1 for
  /// pure white, so that ratio cannot be reproduced with any headroom. Light's
  /// value IS `ink` (#2D2E26), so the dark answer is `nightInk` — the
  /// ceiling-compressed value coincided with the existing pair's, so nothing
  /// was invented. Same value as `nightMetaBaseL4`, as in light.
  static let nightMetaStrongL3 = PasturaColorValue(hex: 0xE8E5D8)
  /// Lit progress dot, preset L3 under dark mode.
  static let nightMetaDotOnL3 = PasturaColorValue(hex: 0xC3CEAE)

  /// Meta text, preset L4 (loudest) under dark mode. Ceiling-bound onto
  /// `nightInk` for the reason given on `nightMetaStrongL3`; light's
  /// `metaBaseL4` is likewise `ink`, so "L4 reads as loud as body text"
  /// survives the appearance flip.
  static let nightMetaBaseL4 = PasturaColorValue(hex: 0xE8E5D8)
  /// Emphasis within preset L4 under dark mode — the top of the ladder, and the
  /// only token here placed above `nightInk` (11.89:1). A warm off-white, not
  /// pure white; light ships #1A1B15, near-black rather than pure black, so the
  /// asymmetry would be the anomaly. §1's "no pure white" guidance is about
  /// surfaces (§2.2), not foregrounds.
  static let nightMetaStrongL4 = PasturaColorValue(hex: 0xF1F0E8)
  /// Lit progress dot, preset L4 under dark mode.
  static let nightMetaDotOnL4 = PasturaColorValue(hex: 0xD5DDC6)

  // MARK: §2.9 Dark counterparts of the §2.12 GameHeader slots
  //
  // Ground here is `nightBackground`, not `nightBubble`: `GameHeader` sits on a
  // frosted `screenBackground`, which is already paired to it.
  //
  // Only TWO of the three slots appear. `headerMetaSubdued` is **fixed in both
  // appearances** — solving its own light contrast (4.04:1) on this ground
  // returns its own light value (measured 4.03:1), because a mid-lightness tone
  // reads the same against a pale ground and a dark one. ADR-028 gate 1 admits
  // a recorded fixed decision as an equal alternative to a designed value; see
  // `design-system.md` §2.12 for the measurement and why the alternative
  // (mirroring the "midpoint of metaBaseL1/L2" note) was rejected.

  /// GameHeader meta-row middle-dot separator under dark mode (1.76:1, light's
  /// ratio exactly). Stays STRONGER than `nightRule` (1.43:1), mirroring the
  /// light relation where `headerRule` is darker than the general-purpose
  /// `rule` so it reads as a typographic separator rather than a layout divider.
  static let nightHeaderRule = PasturaColorValue(hex: 0x474535)
  /// GameHeader meta-row phase-name foreground under dark mode (8.18:1 vs
  /// light's 8.22:1).
  ///
  /// Light's value is the same hex as `metaBaseL3` (#4A4E3D); the dark values
  /// **diverge** (#B2B6A2 vs #C7CABC) because the two render on different
  /// grounds. That is §2.12's "evolves independently of §2.4, do not merge"
  /// claim coming true rather than a drift to fix.
  static let nightHeaderMetaInk = PasturaColorValue(hex: 0xB2B6A2)

  // MARK: §2.9 Dark counterparts of the §2.1 surfaces
  //
  // Two treatments, opposite in direction. `nightPage` **sinks**, holding light's
  // 1.099 step below the body ground — light's `page` is the dim one (the
  // workbench under the app) and dark keeps it dim. `nightPromoBackground` is a
  // **card-tier** surface and follows the card, holding light's 1.047 below
  // `bubbleBackground`; light's near-identical 1.003 against `screenBackground`
  // is an artifact of light's compressed top end, not the design relation, and
  // reading it as one would leave the dark card flush with the dark ground.
  //
  // Two things the arithmetic does not settle. `nightPage` at HSL L=6.7% is the
  // palette's darkest token and its one consumer is `ViewerPredictionSheet`'s
  // fill, where iOS convention says a sheet *rises* — a **device-QA item**
  // (ADR-028 gate 4). And `nightPromoBackground` is the ground slice 2 designed
  // §2.4 against as a stand-in, landing just outside the band it assumed; the
  // re-measurement is in `DesignTokensTests+NightMeta`, where the tripwire
  // forced it. Full derivation: ADR-028 § Amendment for slice 4.

  /// Outside the app surface (workbench) under dark mode — sinks below
  /// `nightBackground`, mirroring light's `page` sitting below `screenBackground`.
  static let nightPage = PasturaColorValue(hex: 0x11130F)
  /// Promo / banner background under dark mode. The real §2.4 render ground.
  static let nightPromoBackground = PasturaColorValue(hex: 0x282C24)
  /// Promo / banner border under dark mode.
  ///
  /// Holds light's 1.204 against its own card but **inverts direction** — light's
  /// border is darker than the card, this one is lighter. The precedent is the
  /// original eight's own `rule` -> `nightRule` (light 1.324 *below* the ground,
  /// dark 1.425 *above* it), and the reason is measurable: a border holding 1.204
  /// on the dark side of its card lands at Y=0.0113 against a ground at 0.0117,
  /// a ratio of 1.01 — it would dissolve into the ground behind it exactly where
  /// the card edge needs to read.
  static let nightPromoBorder = PasturaColorValue(hex: 0x35392F)

  // MARK: §2.9 Dark counterpart of the §2.2 on-accent foreground
  //
  // Light's `inkOnAccent` is pure white on a mid accent; dark's is a near-ground
  // tone on a bright one. The flip is not a judgement call — it is what Material
  // 3 does when `primary` moves tone 40 -> 80 and `on-primary` follows tone
  // 100 -> 20, the move `moss` -> `nightMoss` makes. Within that band the value
  // is placed to clear **WCAG AAA (1.4.6, 7:1 normal text)** on the fill that
  // carries on-accent *text*, because the smallest consumers are 9pt / 9.5pt mono
  // labels: **7.117 on `nightMossDark`** clears it. On base `nightMoss` it is
  // 6.395 — above the 4.5:1 AA bar and above 1.4.11's 3:1 shape bar, but **not**
  // AAA. That asymmetry is deliberate and mirrors light's: `mossDark` is the fill
  // for text, `moss` the fill for shapes.
  //
  // **Same hex as `nightBubble` — a consequence, not the reason.** Light carries
  // the same coincidence (both #FFFFFF), but slice 3's rule licenses carrying one
  // only when both tokens keep the same *job*, and a foreground and a surface do
  // not. The AAA target picks the value; the equality is pinned by a test. Read
  // in the other order it would imply `nightBubble` drags this along. It does not.

  /// Foreground for text / glyphs on an accent fill under dark mode.
  static let nightInkOnAccent = PasturaColorValue(hex: 0x2C2F28)

  // MARK: §2.9 Dark counterparts of the §2.3 moss accent
  //
  // **The family compresses, and it inverts.** `nightMoss` was placed by arm 1
  // (hue held, HSL lightness +11, saturation +7) and therefore sits at 7.999
  // against `nightBackground`, where light's `moss` sits at only 2.908 against
  // its own ground. Every sibling has to be consistent with *that anchor*, not
  // with light's ratios — so `mossDark`, which is light's emphatic step and
  // must stay emphatic, is necessarily ABOVE `nightMoss` and therefore
  // necessarily above 8:1 (measured 8.902, against light's 4.538). This is the
  // §2.3 instance of the ceiling slice 2 found in §2.4.
  //
  // Two consequences that look like defects and are not: the moss -> mossDark
  // step narrows from 1.561 to **1.113** (the two never sit adjacent, and the
  // functional requirement the step serves — an on-accent label clearing AAA on
  // `mossDark` and the non-text bar on `moss` — holds), and `mossDark` reads
  // louder against its ground than light's does. The second is the trade slice 2
  // took for the progress dot: function over perceptual-weight parity.
  //
  // Arm 3 (target-contrast placement) is **degenerate for a ladder step whose
  // direction inverts** — solving `mossDark`'s own 4.538 on the night ground
  // returns a value BELOW `nightMoss`, making the emphatic step the quiet one.
  // So `nightMossDark` holds its proportional HSL lightness position between
  // `moss` and `mossInk` (0.400), the anchor-on-`nightMoss`-and-invert move
  // slice 2 used for the dot ladder. Arm 3 IS right for the other two, whose
  // jobs are legibility and quietness against a ground rather than ladder
  // membership.

  /// DL progress dot (lit), accent links under dark mode — the emphatic step,
  /// which is ABOVE `nightMoss` here where light's is below `moss`.
  static let nightMossDark = PasturaColorValue(hex: 0xB3C197)
  /// Dog outline, completion title under dark mode. Arm 3: holds light's 10.190
  /// against the body ground (measured 10.187).
  ///
  /// One relation falls out for free rather than being designed: `ModelPickerView`'s
  /// CTA is a `mossInk` fill carrying a `screenBackground` label, and
  /// `screenBackground` is already paired — so in dark it becomes
  /// `nightBackground` on this token, at 10.187 against light's 10.190. Both
  /// sides hold their ratio against their own appearance's extreme, so the
  /// button's label contrast survives the flip without anyone placing it.
  ///
  /// Near-identical in luminance to `nightMetaBaseL3` (#C7CABC, contrast 1.002)
  /// and **not** to be merged with it. Arithmetic coincidence: the card sits
  /// 1.251 above the ground, so "8.16 on the card" and "10.19 on the ground"
  /// land at the same luminance. The two differ in chroma (HSL saturation 20 vs
  /// 11.7) and render on different grounds; light's pair is a clear 1.240 apart.
  static let nightMossInk = PasturaColorValue(hex: 0xC6CBB1)
  /// THINKING left-rule, gentle dividers under dark mode.
  ///
  /// Direction inverted and magnitude preserved against the ground (light 1.559,
  /// dark 1.566) — and the magnitude belongs to its **line/border** job, which is
  /// 7 of its 10 callsites (`ChatBubble`'s 1.5pt rule, `ResultsView`'s timeline
  /// rail, and `strokeBorder`s in `HomePausedCard`, `HomeCompactScenarioRow`,
  /// `ResultDetailView+ResumeBanner` and `ScenarioArtTile` twice). The other
  /// three are a tinted fill under `mossDark` text
  /// (`ContradictionBadge`, `PredictionOutcomeBadge`,
  /// `HighlightCandidatesSection`), which lands at 5.685 against light's 2.911 —
  /// a §2.6-shaped Soft/Ink pair, and like those it gains contrast in dark
  /// rather than holding it. It stays the quietest badge of the five in both
  /// appearances, which is the relation that matters and is asserted.
  ///
  /// **Hue moved to the moss family (80.9°), not held at light's 47.7°.** A pale
  /// cream-moss is cream *because* it is pale; at 5% luminance the same hue
  /// reads as amber and would collide in meaning with `nightWarningSoft`
  /// (#383124, hue 39°). Slice 3's chroma lesson, applied downward.
  static let nightMossSoft = PasturaColorValue(hex: 0x384029)

  // MARK: §2.9 Dark counterparts of the §2.8 link / action tokens
  //
  // All three by arm 3, each holding its own light ratio against the body ground
  // (4.618 / 5.378 / 6.345 -> 4.631 / 5.378 / 6.340). Links render on
  // `screenBackground` (`SettingsView`'s external-link rows) and on `page`
  // (`ViewerPredictionSheet`'s Skip), both of which are paired, so the ground is
  // the appearance's own body surface in each case.
  //
  // **Not the "~7:1 band"** ADR-028's #1282 Amendment attached to `link` while
  // predicting this slice. That band was slice 1's *Ink-over-Soft* placement
  // (7.7-8.4:1 over a tinted fill), a different relation; slice 2 then refined
  // arm 3 to "solve for the light ratio", which is what is done here. Recorded
  // because the Amendment's sentence reads like a target for these tokens.
  //
  // Light's ordering is not intuitive and is carried across unchanged:
  // `linkVisited` (5.378) has MORE contrast than `link` (4.618), because it is a
  // desaturated brown rather than a green — hue, not luminance, is what makes it
  // read as spent. Preserving each ratio preserves that, oddity included.

  /// Link in its default (unvisited) state under dark mode.
  static let nightLink = PasturaColorValue(hex: 0x699054)
  /// Link after being followed at least once in this session, under dark mode.
  static let nightLinkVisited = PasturaColorValue(hex: 0x9B9075)
  /// Link while hovered (or on iPadOS pointer hover), under dark mode.
  static let nightLinkHover = PasturaColorValue(hex: 0x7FAA62)

  // §2.9's §2.5 counterparts left with their light halves for
  // `DesignTokens+AvatarPalette.swift` — see this file's header.
}
