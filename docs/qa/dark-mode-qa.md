# Dark Mode QA Walkthrough

Manual QA for the dark appearance. Written for ADR-028 gates 4 and 5 (the
two the ADR could not discharge from a desk), and kept as the re-runnable
walkthrough for any later change to the token pairs, the asset catalog, or a
fixed-appearance export.

**The simulator is not load-bearing here.** `.claude/rules/swiftui-traps.md`
rules it out for iOS 26 visual work, and `ImageRenderer` does not inherit the
ambient environment, so no automated test observes the *rendered* share card at all
(ADR-009 rules out the snapshot test that would be the alternative). Run this
on a device, set to Dark in Settings → Display & Brightness.

Since #1284 the app carries no `UIUserInterfaceStyle` key, so no setup is
needed beyond the device appearance. (Before that, this walkthrough required
temporarily deleting the key — if you are ever bisecting to a commit that
still has it, that is why dark does not appear.)

## What is actually at risk

67 pairs invert. The token system is not where breakage shows up — these six
classes are:

| Class | Why it can break | Where |
|---|---|---|
| A. Deliberately fixed tokens | `headerMetaSubdued` does not invert (gate 1's second branch: recorded fixed in both appearances) but sits beside two that do | `GameHeader.swift` meta row — Simulation and Demo replay (§2) |
| B. Materials | `.ultraThinMaterial` / `.regularMaterial` / `glassEffect` re-render themselves, independently of every token underneath | 11 surfaces (12 call lines — the action bar has two OS branches), §3 |
| C. Fixed-appearance exports | The share card and avatar palettes bypass the alias system and take `colorScheme` explicitly | `HighlightShareCard`, `SheepAvatarPalette`, `StoryShareSheet` (§4) |
| D. Non-SwiftUI surfaces | Launch screen, splash and the UIKit nav-bar appearance proxy sit outside the token mechanism | §1 and §5 |
| E. Occlusion layers | A shadow or scrim must be **darker than what it covers**; a paired alias inverts and brightens instead. No lint rule reaches the scrim shape | §6 — the class that produced the fourth defect |
| F. A screen with no ground at all | An **absent** background falls through to the system colour. Light hides it (#FFFFFF vs #FCFAF4); dark does not (#000000 vs #1B1D17). Nothing greps for a missing modifier | §2 — Simulation and ResultDetail fixed in #1336; the loading / empty / error arms of five *other* roots are still system-coloured, deferred to #1354 — do not re-report |

Everything else is a paired token doing what it was designed to do. Look at it,
but do not go token-hunting — that is gate 1's closed work.

## 1. Launch → splash (class D)

The static launch screen and the SwiftUI splash must agree at the handoff, or
the transition flashes. `launchScreenBackground` and
`LaunchAnimationConfig.backgroundColor` are paired to the same two values and
`DesignTokensTests+AssetCatalog` asserts that in both directions — but the
*composite* is a visual question no test covers.

- [ ] Cold launch (force-quit first). The cream icon tile should read as a card
      on the `#2C2F28` ground, with no light flash between the static screen and
      the splash.
- [ ] Warm launch (background briefly, return). `WarmSplashView` uses the same
      ground.
- [ ] The sky / pasture layers (`LaunchIconSky`, `LaunchIconPasture`) are
      light-grounded tiles by design — confirm they still read as one mark.

## 2. Six-screen walk (gate 4)

For each: does anything read as *broken* — invisible text, a light-mode slab, a
washed-out control — as opposed to merely *different*?

- [ ] **Home** — cards, `ActiveModelChip` (including its warning / danger states
      if reachable), scenario rows. Avatars invert through
      `SheepAvatarPalette.resolved(colorScheme:)`, not through a token alias.
- [ ] **ScenarioDetail** — the bottom `ScenarioDetailActionBar`: `glassEffect` on
      iOS 26, `.regularMaterial` below. The most likely failure on this screen.
- [ ] **Demo replay** (model-download host) — chat stream, the `GameHeader` meta
      row (**class A**), `PromoCard`, and the `DLCompleteOverlay`. `DogMark`'s
      body is deliberately white; confirm it still reads as one mark against the
      inverted `promoBackground`.
- [ ] **Simulation** — bubbles, the `GameHeader` meta row (**class A**), the
      scoreboard sheet, four material capsules/overlays. Also the **ground**
      (**class F**): it must be the warm #1B1D17, not system black. Compare it
      against Home in the same appearance — side by side the difference is
      obvious, alone it is not. Then look at the **header and control-bar
      frosted strips**: each is a `screenBackground.opacity(0.78)` tint with
      `.ultraThinMaterial` above it, and the material is what lifts the result
      clear of the tint (in dark the tint alone is the ground, so it would be
      invisible). Raising the ground from black narrowed their step against the
      chat stream — measured ≈#2C2E2A over #1B1D17, ≈1.39 → ≈1.25. Delineation
      now rests on the material and the 1pt hairline; confirm the bars still
      read as bars.
- [ ] **Results** — list and detail, plus the delete flow's `danger` family. The
      **detail** screen is the second class-F site: its ground must be #1B1D17
      too, same comparison against Home. Its **resume banner** is the surface
      that ground change touched — `moss.opacity(0.08)` over it, so its step
      narrowed ~16% (the opaque `nightMossSoft` stroke still carries the edge).
      It renders only for a `.failed` resumable run, which incidental QA never
      hits: use the `#if DEBUG` "Force .failed" menu item to reach it.
- [ ] **Settings** — the `link` tint, the "Active" model badge
      (`inkOnAccent` on `mossDark`, ≈7.12:1 in dark), past results, orphaned-model
      rows.
- [ ] **Editor** — the warning / danger / success banner family
      (`ScenarioEditorView+Banners.swift`), the densest alert-family surface.
- [ ] **ModelPicker + download progress** — the sticky CTA reverses roles
      (`screenBackground` text on a `mossInk` fill; both invert), and its card
      glow and button shadow are deliberately *fixed* in both appearances.

## 3. Material sites

Not separate navigation — just look when the screen is already open.

Re-derive rather than trust the line numbers below — they drift on every edit
to these files:

```bash
grep -rn 'ultraThinMaterial\|regularMaterial\|glassEffect' Pastura/Pastura/Views --include='*.swift'
```

| Screen | Sites |
|---|---|
| Simulation | `SimulationView.swift` ×4 (a capsule, the loading card, two overlays) |
| Simulation / Demo replay | `GameHeader.swift` ×1 |
| ScenarioDetail | `ScenarioDetailActionBar.swift` ×1 — `glassEffect` on iOS 26, `.regularMaterial` below; one surface, two branches |
| Demo replay | `ModelDownloadHostView+ControlBar.swift` ×1, `DLCompleteOverlay.swift` ×1 |
| ModelSelection | `ModelPickerView.swift` ×1 (sticky CTA backing) |
| Editor | `ScenarioEditorView.swift` ×1 |
| Any tab (overlay) | `InFlightSimulationIndicator.swift` ×1 |

The in-flight pill needs the keep-running Setting on to appear. If it is off,
record that it was not exercised rather than marking it passed.

## 4. Dark share card (gate 5)

- [ ] Share a highlight from Results detail. The generated image must be the
      **dark** card — a light one means the explicit `colorScheme` is not
      reaching the renderer.
- [ ] Check the sheep avatar inside the card. Pairing §2.5 un-pinned it one
      level below `HighlightCardPalette` (#1319), so it is the likeliest wrong
      piece.
- [ ] Exercise the **Instagram Stories** path — it hands solid gradient colours
      through `PasturaColorValue.hexString`, a different code path.
- [ ] Exercise the **X** destination — its `xBlack` fill and white glyph are
      brand-locked and must NOT invert.

## 5. Non-token surfaces

- [ ] **Nav-bar titles** — `PasturaAppDelegate` bakes `UIColor(Color.ink)` into
      `UINavigationBar.appearance()` once at cold launch. The round-trip
      preserves the dynamic provider (asserted by
      `DesignTokensTests+AssetCatalog`), but an appearance proxy set at launch
      is the shape that can freeze to the launch-time trait. Open a large title,
      background the app, switch the system appearance, return — the title must
      follow.
- [ ] **System chrome outside `RootTabView`** — the first-run flow, database
      recovery and the init-failure screen fall back to `AccentColor` rather than
      `RootTabView`'s `.tint(Color.moss)`. Since #1284 that colorset is paired,
      so they should read `nightMoss`, not light moss.

## 6. Occlusion layers (class E)

The class that produced the fourth defect, and the one with the weakest
automated cover: `shadow_color_paired_alias` reaches `shadow(color:)` only, and
the scrim is guarded by `SimulationScrimStyleTests` rather than by lint.

- [ ] **Model-load scrim** — start a simulation and watch the wait overlay. The
      background behind the card must be **darker** than the surrounding UI, not
      lighter. This is the exact defect found post-QA: a paired alias made it
      brighten the screen in dark.
- [ ] **ModelPicker card glow and CTA shadow** — both fixed in both appearances;
      confirm neither reads as a pale halo.
- [ ] **In-flight pill shadow** — same check, if the keep-running Setting is on.

## 7. Viewer-prediction sheet

`nightPage` is the darkest token in the palette and this sheet is its only
consumer — the one value ADR-028 chose against a platform convention rather than
with it. Answered on a device (ADR-028 § Amendment 2026-08-05): it reads **flush**
with its dimmed backdrop, carried by the grabber, the corner radius and its own
candidate cards rather than by a step in lightness. Not a hole. Re-check it
whenever §2.1, the sheet, or the Simulation ground changes — the margin is 1.031,
so it is the first surface a dimming change would flatten.

Getting it on screen is the hard part. It presents **once per run**, at the first
vote phase. Set the device to **dark** for this walkthrough — the sheet itself
presents in either appearance — and four in-app preconditions must then hold. Two of
them, 2 and 3, silently spend the run's one opportunity if they fail, because the
latch is set before their guards. 1 returns before the latch, and 4 is not a guard at
that site at all — it governs whether the latch was reset for this run:

1. Settings → viewer-prediction toggle **on** (defaults on).
2. The simulation screen stays **foreground-visible** — parking it (ADR-017
   Phase B) or backgrounding latches `hasAttemptedPrediction` for that run.
3. At least **two** non-eliminated agents.
4. A **fresh run**, not a resume.

- [ ] **Fastest route: 先取りゲーム** (`target_score_race.yaml`) — it *starts*
      `speak_all → vote`, so the sheet appears once three agents have spoken.
      Any preset with a vote phase works; `prisoners_dilemma` (ja and en) is the
      only bundled scenario without one. It auto-skips after 15 s and carries
      `.interactiveDismissDisabled()`, so **screenshot it on appearance and judge
      from the image** rather than deciding in 15 seconds.

## Record of the gate-4 / gate-5 pass

The pass that closed both gates covered every screen above and found three
defects: the launch ground had no dark variant (and the splash would have
flashed cream), five `.borderedProminent` buttons measured ≈2.13:1 in dark, and
three shadows inverted into pale halos. Everything else passed on first look.

Re-QA of those three fixes then found a **fourth** — the model-load scrim,
§6 — which is why that class has its own section: the sweep that found the
shadows keyed on `shadow(color:)`, the syntax, and could not have found a scrim.

A **fifth** arrived later still, from the § 7 run: the Simulation screen had no
ground at all (class F, #1336), and enumerating the class rather than the instance
found `ResultDetailView` in the same state. Note what found it — not the walk,
which had covered Simulation twice, but *measuring a screenshot's pixels*. Every
earlier defect announced itself as wrong-looking; this one looked like a dark
screen.

The five fixes post-date the pass that authorized closing the gates, so
they are the first thing to re-check on any repeat run: the splash composite, the
ModelPicker shadows, the five restyled buttons, the scrim, and the two missing
screen grounds.

## While you are here: skim the dark review set

`scripts/ui-tour.sh --dark` is a simulator artifact and no part of this walk —
but note what found the fifth defect above, and do this while a device pass is
fresh. Coverage and caveats: `../design/screenshots/README.md` § "Dark set".

- [ ] Regenerate and skim once. File anything untracked that cites a
      `../design/design-system.md` anchor — worth doing on its own merits, and
      it is **re-arm condition 1** for the decision that `ui-refine` stays
      light-only (#1345); nothing else fires that.
