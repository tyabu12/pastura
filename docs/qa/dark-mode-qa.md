# Dark Mode QA Walkthrough

Manual QA for the dark appearance. Written for ADR-028 gates 4 and 5 (the
two the ADR could not discharge from a desk), and kept as the re-runnable
walkthrough for any later change to the token pairs, the asset catalog, or a
fixed-appearance export.

**The simulator is not load-bearing here.** `.claude/rules/swiftui-traps.md`
rules it out for iOS 26 visual work, and `ImageRenderer` does not inherit the
ambient environment, so no automated test observes the share card at all
(ADR-009 rules out the snapshot test that would be the alternative). Run this
on a device, set to Dark in Settings → Display & Brightness.

Since #1284 the app carries no `UIUserInterfaceStyle` key, so no setup is
needed beyond the device appearance. (Before that, this walkthrough required
temporarily deleting the key — if you are ever bisecting to a commit that
still has it, that is why dark does not appear.)

## What is actually at risk

67 tokens invert. The token system is not where breakage shows up — these four
classes are:

| Class | Why it can break | Where |
|---|---|---|
| A. Deliberately fixed tokens | `headerMetaSubdued` does not invert (gate 1's second branch: recorded fixed in both appearances) but sits beside two that do | `GameHeader.swift` meta row — Simulation and Demo replay |
| B. Materials | `.ultraThinMaterial` / `.regularMaterial` / `glassEffect` re-render themselves, independently of every token underneath | 11 sites, §2 |
| C. Fixed-appearance exports | The share card and avatar palettes bypass the alias system and take `colorScheme` explicitly | `HighlightShareCard`, `SheepAvatarPalette`, `StoryShareSheet` |
| D. Non-SwiftUI surfaces | Launch screen, splash and the UIKit nav-bar appearance proxy sit outside the token mechanism | §4 |

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
      scoreboard sheet, four material capsules/overlays.
- [ ] **Results** — list and detail, plus the delete flow's `danger` family.
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

| Screen | file:line |
|---|---|
| Simulation | `SimulationView.swift:919, 959, 1152, 1494` |
| Simulation / Demo replay | `GameHeader.swift:202` |
| ScenarioDetail | `ScenarioDetailActionBar.swift:143` (glass) / `:145` (fallback) |
| Demo replay | `ModelDownloadHostView+ControlBar.swift:46`, `DLCompleteOverlay.swift:41` |
| ModelSelection | `ModelPickerView.swift:202, 232` |
| Editor | `ScenarioEditorView.swift:193` |
| Any tab (overlay) | `InFlightSimulationIndicator.swift:80` |

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

## Record of the gate-4 / gate-5 pass

The pass that closed both gates covered every screen above and found three
defects, all fixed in the same PR: the launch ground had no dark variant (and
the splash would have flashed cream), five `.borderedProminent` buttons measured
≈2.13:1 in dark, and three shadows inverted into pale halos. Everything else
passed on first look.

Three surfaces changed *after* that pass and are the first thing to re-check on
any repeat run: the splash composite, the ModelPicker shadows, and the five
restyled buttons.
