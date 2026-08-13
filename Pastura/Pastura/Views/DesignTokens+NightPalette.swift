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
// **Gate 1 closing means §2.9 takes no further tokens.** After the §2.6/§2.7 move
// to `DesignTokens+NightStatePalette.swift` this file sits at 325 lines, so it has
// room again — the constraint is the closed gate, not the line count. Should an
// addition ever be warranted, split by what it touches ("a completed section moves
// out whole" stops discriminating once every section is).
//
// Every token here is the dark half of a `PasturaDynamicPalette` pair
// (`DesignTokens+DynamicPalette.swift`), reached through the repointed light
// `Color.*` alias rather than through `Color.night*`. Dark now renders on any
// device set to that appearance, since `Info.plist`'s `UIUserInterfaceStyle`
// lock was removed (ADR-028 gates 4/5).

extension PasturaPalette {

  // MARK: §2.9 Dark Mode (night pasture)
  //
  // Day tones translated to a "night pasture" variant — moss brightened,
  // cream replaced by warm dark surfaces. These are **wired**: every token
  // below is the dark half of a `PasturaDynamicPalette` pair, reached through
  // the repointed light `Color.*` alias rather than through `Color.night*`.
  // Dark now renders on any device set to that appearance: `Info.plist`'s
  // `UIUserInterfaceStyle` lock is gone, and by slice 4 **no light token owed
  // gate 1 a dark value any more** (ADR-028 § Rollout gate 1, met). What
  // remained for the lock to wait on was gates 4 and 5 — real-device dark QA
  // across the screens, and the dark share-card path — and both are now met.

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

  // §2.6's alert family and §2.7's interactive states moved to
  // `DesignTokens+NightStatePalette.swift` during slice 4's review — see that
  // file's header for why.

  // MARK: §2.9 Dark counterparts of the §2.4 meta-contrast presets
  //
  // **The L1→L4 ladder runs the other way here**: in light a higher preset is
  // DARKER, gaining contrast against the pale ground; in dark the same emphasis is
  // BRIGHTER. Not the light ladder transformed per token but redesigned against the
  // dark ground — ADR-028's Amendment 2026-07-29 (#1282) names it the one item no
  // formula covers.
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
  // **The per-token ratios below are stand-in-era and left that way deliberately**
  // — they record what each value was *designed* to mirror against `nightBubble`,
  // which is why they read "light's ratio exactly". Against the real card each is
  // higher (L1 base 3.33 -> 3.48, L3 base 8.16 -> 8.54, white ceiling 13.60 ->
  // 14.23) and the mirror-of-light framing holds only against the stand-in. The
  // re-measurement establishes **monotonicity** with L3 above 4.5, not preserved
  // ratios. Live figures: `DesignTokensTests+NightMeta`.
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
  // Two things the arithmetic could not settle on its own. `nightPage` at HSL
  // L=6.7% is the palette's darkest token and its one consumer is `ViewerPredictionSheet`'s
  // fill, where iOS convention says a sheet *rises*. Settled on a device: the
  // sinking does not reach the screen, because the presentation dims the
  // backdrop and not the sheet — 1.099 below the ground by design, 1.031 above
  // its own backdrop when rendered. The arithmetic was comparing the wrong two
  // surfaces, which is the reusable half (ADR-028 § Amendment 2026-08-05 (#1336)).
  // And `nightPromoBackground` is the ground slice 2 designed §2.4 against as
  // a stand-in, landing just outside the band it assumed; the
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
  // Dark's on-accent foreground is a near-ground tone, **not white** — the flip
  // mirrors Material 3's on-primary tone 100 -> 20 as primary goes 40 -> 80, which
  // is the move `moss` -> `nightMoss` makes. Placed to clear **WCAG AAA (7:1)** on
  // `nightMossDark` (7.117), the fill that carries on-accent *text*, because the
  // smallest consumers are 9pt / 9.5pt mono labels. On base `nightMoss` it is
  // 6.395 — clears AA and 1.4.11's 3:1 shape bar, **not** AAA — mirroring light's
  // text-on-`mossDark` / shapes-on-`moss` split. Full record and the refused
  // alternative: `design-system.md` §2.2 and ADR-028 § Amendment for slice 4.
  //
  // **Same hex as `nightBubble` — a consequence, not the reason.** Slice 3's rule
  // licenses carrying a coincidence only when both tokens keep the same *job*, and
  // a foreground and a surface do not. The AAA target picks the value; the equality
  // is pinned by a test, not relied upon.

  /// Foreground for text / glyphs on an accent fill under dark mode.
  static let nightInkOnAccent = PasturaColorValue(hex: 0x2C2F28)

  // MARK: §2.9 Dark counterpart of the §2.2 on-wash foreground
  //
  // The half the `inkOnWash` pair exists for — its light half is `inkSecondary`
  // copied verbatim, so this token is where the two separate. **The direction is
  // the opposite of #1327's**: there moss label text failed in *light* and dark
  // passed, here the ink self-wash fails in *dark*. Which is why `mossOnWash`
  // could not simply be extended over these sites.

  /// Neutral text on a translucent ink-family wash under dark mode.
  ///
  /// Arm 3: measured over the four shipped self-washes (composited on
  /// `nightBubble`, the worst-case ground for light-on-dark and the convention
  /// `DesignTokensTests+MossOnWash.swift` established) it lands **4.991–5.397**,
  /// clearing the 4.5:1 text bar on all of them. Under `nightInkSecondary` today
  /// the same four give 4.413 / 4.501 / 4.501 / 4.773 — two under the bar, two
  /// *on* it, and `ResultsView`'s `paused` pill the only one with real margin.
  ///
  /// **There is no impossibility proof here, unlike `mossOnWash`.** `nightInk`
  /// reaches 7.955–8.602 on these same washes and would clear the bar easily, so
  /// the justification is **role**, per design-system §8: the token replacing a
  /// foreground comes from the family that owns the ground, and `nightInk` is the
  /// body-text rung while these badges are documented as deliberately quieter.
  /// That claim is executed by `DesignTokensTests+InkOnWash`, not just written
  /// here — otherwise a later reader "simplifies" to `nightInk` silently.
  ///
  /// Two more levers were rejected on measurement, derivations in ADR-028
  /// § Amendment 2026-08-13 (#1408): lowering the dark wash alpha (cheap, but it
  /// buys back the marginless state this change exists to leave, and the 15%
  /// fill is load-bearing) and retuning `nightInkSecondary` itself (93
  /// `Color.inkSecondary` lines across 43 files, four of them self-washes).
  ///
  /// Placed by the §2.2 proportional-L relation, **precedent rather than an
  /// independent control** (the same caveat `nightMossOnWash` carries): HSL L
  /// 69.61, 0.198 of the way from `nightInkSecondary`'s 65.10 toward `nightInk`'s
  /// 87.84. What has teeth is the measurement above.
  static let nightInkOnWash = PasturaColorValue(hex: 0xBAB7A9)

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
  /// and **not** to be merged with it. Arithmetic coincidence — figures and the
  /// derivation live once, in
  /// `DesignTokensTests+NightRemainder`'s `nightMossInkConverges…` doc comment, so
  /// that a correction cannot land in one copy and miss the other (it did, once).
  /// The short version: the two differ in chroma (HSL saturation 20 vs 11.7) and
  /// render on different grounds; light's pair is a clear 1.240 apart.
  static let nightMossInk = PasturaColorValue(hex: 0xC6CBB1)
  /// THINKING left-rule, gentle dividers under dark mode.
  ///
  /// Direction inverted and magnitude preserved against the ground (light 1.559,
  /// dark 1.566) — and the magnitude belongs to its **line/border** job, which is
  /// 7 of its 10 callsites (`ChatBubble`'s 1.5pt rule, `ResultsView`'s timeline
  /// rail, and `strokeBorder`s in `HomePausedCard`, `HomeCompactScenarioRow`,
  /// `ResultDetailView+ResumeBanner` and `ScenarioArtTile` twice). The other
  /// three are a tinted fill under `mossInk` text
  /// (`ContradictionBadge`, `PredictionOutcomeBadge`,
  /// `HighlightCandidatesSection`) — a §2.6-shaped Soft/Ink pair, and like those
  /// it gains contrast in dark rather than holding it: 6.505 against light's
  /// 6.537, both asserted over the 4.5:1 bar by `DesignTokensTests+MossSoftGround`
  /// (#1407). Its position *relative* to the other four is not asserted and is
  /// not a relation to lean on — it falls outside their band on opposite sides
  /// per appearance (above light's 5.389–5.976, below dark's 7.689–8.374).
  ///
  /// **Hue moved to the moss family (80.9°), not held at light's 47.7°.** A pale
  /// cream-moss is cream *because* it is pale; at 5% luminance the same hue
  /// reads as amber and would collide in meaning with `nightWarningSoft`
  /// (#383124, hue 39°). Slice 3's chroma lesson, applied downward.
  static let nightMossSoft = PasturaColorValue(hex: 0x384029)
  /// Accent text on a translucent moss wash under dark mode.
  ///
  /// Arm 3: measured over the seven shipped washes it lands 4.70–6.03, clearing
  /// the 4.5:1 text bar on all of them (composited on `nightBubble`, the harder
  /// of the two grounds for light-on-dark — the same worst-case convention
  /// `DesignTokensTests+MossOnWash.swift` asserts). The thinnest is the gallery
  /// category chip, whose `nightSelected` re-bases alpha 0.18 -> 0.24 and so
  /// lightens the ground — 4.70 there, against 4.39 for `mossDark` today, which
  /// makes the chip the one site already failing in dark before this token.
  ///
  /// Placed by the §2.3 proportional-L relation, which is **precedent, not an
  /// independent control**: `mossOnWash` sits 0.700 of the way from `moss` to
  /// `mossInk`, and applying that fraction to the night ladder gives HSL L
  /// 70.98. `nightMossDark` agreeing at 0.400 with `mossDark` does not
  /// corroborate it — ADR-028 § Amendment 2026-07-30 (#1325) *placed*
  /// `nightMossDark` by holding exactly that position, so the agreement is
  /// construction. What has teeth is the measurement above. See ADR-028
  /// § Amendment 2026-08-08 (#1327).
  static let nightMossOnWash = PasturaColorValue(hex: 0xBDC6A4)

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
