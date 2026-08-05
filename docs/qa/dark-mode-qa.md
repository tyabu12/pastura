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
| E. Occlusion layers | A shadow or scrim must be **darker than what it covers** — a paired alias inverts, and a *fixed* tint that is merely lighter than the ground brightens too. Since #1377 the lint rule reaches both shadow shapes, but it certifies only that the tint names a sanctioned family, never that the value is dark enough — `PasturaShadows` passed it throughout while being too light (#1378) — and it reaches the scrim shape not at all | §6 — the class that produced the fourth defect, and the seventh (#1373) |
| F. A **rendered state** with no ground behind it | An **absent** background falls through to the system colour. Light hides it (#FFFFFF vs #FCFAF4); dark does not (#000000 vs #1B1D17). Nothing greps for a missing modifier — and the question is a layout one ("does every branch have a ground behind it"), not a syntactic one, so no gate is available either | §2 — the whole class is swept as of #1354; **walk the loading / empty / error branch of a screen, not just its loaded state**. Presented sheets are out of class — see the note under the table |

Everything else is a paired token doing what it was designed to do. Look at it,
but do not go token-hunting — that is gate 1's closed work.

**Class F's edge at presented sheets is open, deliberately.** Six sheets set no
screen-level ground: `LicensesSheet`, `ScoreboardSheet`, `PhaseEditorSheet` and
`PersonaEditorSheet` sit on `List` / `Form`, which supplies its own grouped
background; `PersonaDetailSheet` and `ReportSheet` are plain `ScrollView`s and
fall through to the sheet's system surface. `ViewerPredictionSheet` sets
`Color.page` — so "a sheet inherits the system ground on purpose" is **not** an
established convention here, and the class edge was never decided. It is recorded
as unresolved rather than swept, because #1354 measured full screens and a
presented surface composites differently (§ Amendment 2026-08-05 (#1336)'s whole point).
Note a groundless sheet if one looks wrong on a dark device; do not file it as a
class-F regression.

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

## 2. The loaded-state walk (gate 4)

For each: does anything read as *broken* — invisible text, a light-mode slab, a
washed-out control — as opposed to merely *different*? The heading carried a
count until 2026-08-05 and was wrong by two before anyone added anything — the
list grows whenever a screen gains exposure, so it no longer states one.

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
- [ ] **Browse** — the Search tab root. #1354 moved its ground onto the
      container (`SharedScenariosListView`'s `.background(Color.screenBackground)`
      wraps the `Group`, not `scenarioList`), so the **loaded** state changed
      here too, not only the branches § 2b reaches. Then the catalog cards
      (**class E**): each `GalleryCatalogRow` carries a `PasturaShadows.tight`
      drop shadow and the `ScenarioArtTile` inside it carries a second — the
      family ADR-028 measured as *lighter* than the night ground and retinted in
      #1378, so this is the screen where two of the four fixed consumers live
      (four consumers, five layers — this screen holds two `.tight`). Lint
      was green on both throughout, before and after, which is the point: judge
      whether the cards read as lifted rather than haloed. Also the filter chips
      (`+CategoryChips` / `+LanguageChips`): selected is `inkOnAccent` on
      `mossDark`, unselected `Color.ink` on `bubbleBackground` behind a
      `Color.rule` hairline — and each card's inline `categoryChip` is a
      *different* pair (`mossDark` on `Color.selected`) wearing the same accent,
      so compare the two. An engine-incompatible card is the same surfaces at
      `incompatibleCardOpacity`; confirm it still reads as dimmed rather than as
      absent.
- [ ] **GalleryScenarioDetail** — reached by tapping a Browse card. Its ground
      moved onto the container too (`GalleryScenarioDetailView`), and it is the
      one screen in **both** of #1354's groups: a relocated loaded ground *and* a
      newly-exposed transient arm (the `ProgressView()` covering the network
      load). The action button — "Try this scenario" / "Update" / "Open local
      copy" — is `PasturaPrimaryButtonStyle`, one of the five restyled in the
      gate pass. The recommended-model section
      (`+RecommendedModel.swift`) is the densest surface: a `Color.warning`
      mismatch glyph over `inkSecondary` copy, and a `.bordered` switch button
      that takes the system tint rather than a Pastura token. Toolbar carries
      `PasturaToolbarButtonStyle(variant: .secondary)` beside `PasturaBackButton`.
- [ ] **Results** — list and detail, plus the delete flow's `danger` family.
      "List and detail" means the aggregate timeline and `ResultDetailView`;
      **there is a third arm** — the pushed per-scenario list (`ResultsView`'s
      `resultsList` under `scope.isPushedDetail`, a grouped list rather than the
      tab root's timeline), reached from a scenario's own results entry. It is
      the other loaded arm whose inner ground #1354 relocated, so walk it as
      well as the timeline. The
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
      (`screenBackground` text on a `mossInk` fill; both invert). Its card and
      button shadows read §4.3.1's occluder tint since #1373 — as, since #1378,
      does every other §4.3 shadow; the shadow check itself lives in §6.
      Reachable on the simulator only via
      `--capture-model-picker` (DEBUG) — otherwise this screen needs a real
      first install, which is how #1373 stayed invisible.

### 2b. The non-loaded branches (class F, #1354)

The walk above lands on each screen's **loaded** state, which is exactly the
state that was never broken — every one of these carried its ground already. The
defect lived in the branches a walk does not reach, so reach them deliberately.
Each must show the warm #1B1D17, not system black; compare against Home in the
same appearance, since alone a dark screen looks like a dark screen.

- [ ] **Past Results — empty.** The sharpest one: a tab root, what a fresh
      install sees, and it does not clear on its own. Needs a build with no past
      results (delete them via Settings → past results, or a fresh install).
- [ ] **Model Setup — the plain states.** Six route through one container, and
      `checking` is the first screen a fresh install renders. `plainProgress` is
      on screen for the whole multi-GB download; `wifiRequired` is reachable by
      starting a download on cellular and declining; `error` by killing the
      network mid-download.
- [ ] **Browse — gallery unreachable.** Turn the network off and open the Search
      tab: `loadingView` then the `Gallery Unavailable` empty state, which
      persists.
- [ ] **ScenarioDetail / GalleryScenarioDetail / Editor / Home — the transient
      arms.** Each shows a bare `ProgressView` before its load resolves. On a
      fast device this is brief; a scenario id that fails to load holds
      ScenarioDetail's **error** `ContentUnavailableView` open indefinitely,
      which is the one worth reaching.

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

The class with the weakest automated cover, and it has now produced three defects
rather than one — the scrim (#1284), three ad-hoc occluder sites (#1373), and
§4.3's own two layers (#1378). `shadow_color_occluder_family` — named
`shadow_color_paired_alias` until #1377 — used to catch a *paired alias* and
nothing else, blind to the shapes that were fixed-but-lighter. #1377 inverted it
to an allowlist, closing that gap: it reaches every `.shadow(color:` tint whose
value follows the label directly. **Two syntactic shapes stay out of reach** — an
intervening comment between `.shadow(` and `color:`, and the `ShapeStyle` form
`.shadow(.drop(color:))` — both measured at 0 violations, neither present in the
tree today. The scrim and both shadow families are guarded by
`SimulationScrimStyleTests`, `PasturaOccluderShadowsTests` and
`PasturaShadowsTests`, all against hand-maintained ground lists.

**A green lint run still says little about this class, and nothing about the
scrim.** It certifies only that a shadow tint *names* a sanctioned family, never
that the value is dark enough for what it covers — which is exactly what
`PasturaShadows` failed to be until #1378, while passing the lint throughout. The
scrim has no lint guard at all. Walk it.

- [ ] **Model-load scrim** — start a simulation and watch the wait overlay. The
      background behind the card must be **darker** than the surrounding UI, not
      lighter. This is the exact defect found post-QA: a paired alias made it
      brighten the screen in dark.
- [ ] **ModelPicker card and CTA shadows** — launch with
      `--capture-model-picker` (DEBUG). Neither may read as a glow. Fixed on the
      simulator in #1373 and measured there (#303527 → #1E2119 under the card);
      what a device adds is the judgement of whether the card still reads as
      *elevated* now that its shadow only darkens ~1.6 sRGB steps in dark — the
      surface and hairline are what carry it.
- [ ] **In-flight pill shadow** — same check, if the keep-running Setting is on.
      Walk it above **two different tab roots** (Home and Past Results, say).
      Every screen ground is `nightBackground`, so one is arguably enough; two
      costs nothing and catches a screen that lost its ground. The pill's tint
      also clears `nightBubble` and `nightPage`, but **do not go looking for
      those** — `nightPage` belongs to the viewer-prediction sheet, which is
      presented from `SimulationView`, where the pill is suppressed. That margin
      is arithmetic only and is asserted in the tests, not walkable here.
- [ ] **PromoCard's two-layer shadow (#1378)** — launch with `--capture-demo`
      (DEBUG), which routes to `ModelDownloadHostView` and mounts the card in
      the bottom safe area. It is the **only** `.soft` consumer, so it carries
      the whole visible part of the retint; the other three §4.3 sites are
      `.tight` alone, moving a fifth as far. Check both appearances: dark must show
      no green lift under the card, light must still read as a shadow now that
      it is neutral rather than moss. Signed off on the simulator at the retint;
      what a device adds is the same elevation judgement as the ModelPicker row
      above.
- [ ] **The three `.tight`-only §4.3 sites** — `GalleryCatalogRow` and its
      nested `ScenarioArtTile` badge (Browse tab), and the `ResultsView`
      timeline cards (Past Results). Their change is ≤ 1.1 sRGB steps in light
      and ≤ 3.4 in dark, confined to a 2 px halo at α 0.03. A **glance, not a
      measurement** — but on that argument, not on the magnitude being tiny:
      `PromoCard`'s `.soft`, which moves ~5× as far, was captured and signed off
      as removing a glow without costing elevation, and these move the same way
      by a fifth as much. `scripts/ui-tour.sh` reaches both screens but is
      largely blind to token changes: a zero pixel-diff there means "not
      exercised", not "unchanged".

## 7. Viewer-prediction sheet

`nightPage` is the darkest token in the palette and this sheet is its only
consumer — the one value ADR-028 chose against a platform convention rather than
with it. Answered on a device (ADR-028 § Amendment 2026-08-05 (#1336)): it reads **flush**
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

A **sixth** is that same class swept properly (#1354), and it is the one worth
carrying forward as method. Each of the three enumerations narrowed the predicate
without saying so: "this screen has no ground" found one site, "no ground at all"
found two, "the ground is on the loaded arm" found five more — and re-deriving
from the predicate the class was *actually* stated in, "a rendered state shows the
system colour", found two beyond that, one of them the first screen a fresh
install renders. **A list enumerated from where the fix already exists cannot see
a file that has none**; only re-deriving from the defect can. §2b walks the
branches this produced.

The six fixes post-date the pass that authorized closing the gates, so
they are the first thing to re-check on any repeat run: the splash composite, the
**occluder-shadow family** (#1373), the five restyled buttons, the scrim, the two
missing screen grounds, and the seven-site sweep of their non-loaded branches.
The occluder entry was "the ModelPicker shadows" until #1373 **superseded** that
2026-07-31 repair — it had left all three tints lighter than the ground — and
widened it to the in-flight pill. Re-check the current values, not that fix.

**One of those six has had its re-check** — § 2b walked 2026-08-05 on an
iPhone 16e (iOS 26.5, dark), nothing on system black. The other five are still
owed theirs. Three gaps inside even that one, worth knowing before you decide
this section is done. Three of #1354's seven sites are **not** covered by it —
Home, GalleryScenarioDetail and the editor host, whose new exposure is a
transient spinner a fast device does not hold open. At four screens the sweep
also *moved* the ground off the loaded sub-view onto the container, so their
loaded states changed too: Results, Browse, ScenarioDetail and — again —
GalleryScenarioDetail, which is in both groups. § 2 was not re-walked, and it
carried **no Browse and no GalleryScenarioDetail item** — the two that needed a
new entry rather than a repeat — and its `Results` item routed only to the
aggregate timeline and `ResultDetailView`, not to the `scope.isPushedDetail` list
that also lost its inner ground. #1376 wrote all three, but **writing them is not
walking them**: all four of those relocated loaded grounds, and the three
transient arms above, are still owed a device pass. And the pass that is
recorded was a walk, not a pixel sample — which is what missed the fifth defect
twice.

## While you are here: skim the dark review set

`scripts/ui-tour.sh --dark` is a simulator artifact and no part of this walk —
but note what found the fifth defect above, and do this while a device pass is
fresh. Coverage and caveats: `../design/screenshots/README.md` § "Dark set".

- [ ] Regenerate and skim once. File anything untracked that cites a
      `../design/design-system.md` anchor — worth doing on its own merits, and
      it is **re-arm condition 1** for the decision that `ui-refine` stays
      light-only (#1345); nothing else fires that.
