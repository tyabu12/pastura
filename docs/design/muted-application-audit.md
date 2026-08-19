# `muted` application audit (#1448)

Ledger for the app-wide sweep of `Color.muted`, design-system §8's deliberately
sub-AA "quietude" tier. Companion to [design-system.md](design-system.md) §8 and
to [ADR-028](../decisions/ADR-028.md) § "Amendment 2026-08-13 — the quietude tier
is ground-relative (#1427)", which scoped this sweep and fixed its two worked
examples in `PredictionOutcomeBadge`.

**This file is the sweep's ledger, not its rule.** §8 remains normative; what is
recorded here is the per-site *application* of §8 across the population, plus the
adjudications that were judgement calls. The sweep runs in batches — batch 1 is
the only one applied so far, and every remaining row still ships as written.

## 1. Population

Measured on `9a40565a` (pre-batch-1):

```sh
grep -rn "Color\.muted" Pastura/Pastura --include="*.swift"
```

98 lines · 3 doc-comment mentions · **95 code sites across 43 files**, all under
`Views/`. 7 of the 95 are inside `#Preview` blocks and never ship, leaving **88
shipped sites**.

**Two denominators, and they differ by one.** 44 files carry the *spelling*;
43 carry a *code site*, because `ActiveModelChipPresenter.swift`'s only
occurrence is a doc comment. Every file figure in this document counts code-site
files, so that the subtraction below works.

The narrowed root above keeps `DerivedData` out, which is the failure a bare
`grep -rn` over `Pastura/` hits. It does **not** achieve what
`.claude/rules/knowledge-layering.md` § Detection is actually about — repo
*trackedness* — so an untracked scratch `.swift` under `Views/` would enter the
census and redden `MutedSweepLedgerTests`, which walks the filesystem rather
than the index. Reach for `git ls-files -z | xargs -0 grep -nH` when that
matters. Watch the
sibling `+Feature.swift` split: cross-check against
`find Pastura/Pastura/Views -name '*.swift'` (CLAUDE.md § Scope & Completeness
Discipline).

Batch 1 removed eight occurrences and emptied three files, so the population as
it ships today is **90 lines · 3 doc-comment mentions · 87 code sites across 40
files**. `MutedSweepLedgerTests` pins the per-file breakdown — §8.

### 1.1 One rendering site outside the `Color.muted` spelling

The population above is defined by a *spelling*, and one site reaches the same
token without it: `HighlightShareCard`'s header draws `model.modelName` with
`palette.muted`, a `HighlightCardPalette` slot built from `PasturaPalette.muted`
/ `PasturaPalette.nightMuted`. The raw read is required rather than a lapse —
the card is a fixed-appearance `ImageRenderer` export, where a trait-resolving
alias would collapse its `light` and `dark` families into one
(`.claude/rules/swiftui-traps.md` § "`ImageRenderer` does not inherit the
ambient environment").

**Its ground is composited, and a first pass here got that wrong** by reading it
off the palette slot instead of the view — the same mistake §3.2 records for
`ActiveModelChip`. The card is a `ZStack` of `palette.background` under a moss
radial "light leak" (`moss@0.14` light / `nightMoss@0.10` dark, 240×240 offset
into the top-right), and the model-name line runs far enough right to enter it.
The leak's alpha varies across the glyph run, so the honest figure is the bound
at maximum leak: **2.932 / 3.140**, against 3.329 / 3.779 on the bare
background. This is a fourth composited ground; it is listed in §3.2.

**Domain first: §2's five classes were written for in-app screens, and an
exported image is not one.** Its viewer has none of the app's context, cannot
tap through to anything, and cannot obtain the information elsewhere — so §2's
sanctioned shapes, which are all justified by in-app recoverability, do not
transfer by form alone. Judged against what an export can be held to instead —
is this a thing the recipient must read to understand the artifact? — the model
name is provenance *about* the quote rather than part of it, and the card's own
primary content (`utterance`, `thought`) is at `ink` / `inkSecondary`.
**Verdict: S**, on that reasoning rather than on the caption analogy.

It is deliberately left out of the counts above and out of §5, both of which
remain the `Color.muted` census — folding it in would restate every figure to
record one sanctioned site.

`MutedSweepLedgerTests.rawPaletteReadsStayWithinTheRecordedSet` pins the
out-of-spelling set instead, so a *new* consumer of this shape cannot enter by
the route §1's grep is blind to.

**Line numbers in §5 are advisory, valid at `9a40565a`.** Rows are anchored by
file + symbol because inserting a why-comment shifts every later line in the same
file — including rows this sweep has not touched. Re-anchor by symbol, not by
line, when picking up a later batch.

## 2. What §8 actually exempts, and the test this sweep applies

§8's exemption is stated for «一覧キャプション・脚注・アンビエントなラベル» and
forbids «判読が要る情報をこのティアに置かないこと» — information whose *legibility
is required*.

**"Unique on this screen" is necessary but nowhere near sufficient**, and reading
it as sufficient is the trap this sweep had to climb out of. A first-pass triage
using that bar classified 41 of the 88 shipped sites as must-read — including
`HomeCompactScenarioRow.caption`, which renders `provenance · N agents · N rounds`,
**verbatim the example §8 itself names as sanctioned**. Almost every caption is
unique somewhere.

A site is a **misapplication** when the `muted` text is the sole statement of one
of these five:

| | Class | Why legibility is required |
|---|---|---|
| **A1** | A blocked or unavailable state, and its reason | The user cannot otherwise learn why a control does nothing |
| **A2** | An instruction required to proceed | The flow does not advance without it |
| **A3** | A number or identifier the user acts on | Storage size, file size, device support, the filename a delete removes, a standing the user is reading the screen to compare |
| **A4** | A degraded or failed outcome | ADR-021 D5 requires the transcript to stay self-explanatory *at the gap*; a gap narrated illegibly is not narrated |
| **A5** | The primary output the screen exists to show | §2.2 assigns `muted` to «メタ情報・脚注». A vote tally is not metadata *about* the simulation — it is the simulation. **Read "screen" as the transcript component, not its host**: a component carrying primary output keeps it wherever it is mounted, so the DL-time demo rows qualify even though that screen exists to download a model |

**Sanctioned even when unique on screen**: list captions, timestamps, counts of a
list's own contents, section headers, separators (`vs`, `·`), rank ordinals in an
already-ordered list, transient progress narration, footnote disclaimers,
branding eyebrows, and the label on a disclosure affordance (as opposed to the
content it discloses).

**Non-text uses are out of §8's scope.** §8 is a text bar. Glyph fills, capsule
washes, strokes, and status dots fall under WCAG 1.4.11's 3:1 non-text bar
instead. They are recorded in §5 for completeness and are **not** swept here.

### 2.1 Controls, both directions

A narrowing test that only ever exonerates is not a test. Both controls are
recorded because either one flipping means the test above is wrong, not that a
site changed.

- **Permissive control — must be exonerated.** `HomeCompactScenarioRow.caption`
  (`provenance · N agents · N rounds`, on `screenBackground` at 3.329 — §8's own
  calibration point). It is §8's named example. **Verdict: sanctioned.** A test
  that catches this one has widened past §8's text.
- **Restrictive control — must be caught.** The eliminated-player rows in
  `ScoreboardSheet` and `SimulationResultCard`, which #1448 named as the
  first-look candidates. **Verdict: misapplication (A3)** for the name and the
  score in both, and the narrowing does *not* rescue them. A test that exonerates
  these has narrowed past §8's own «判読が要る情報».

**The recalibration is a reclassification, not mainly a narrowing** — 41 of 88
under the uniqueness bar against 35 under the test above, six fewer. Reading it
as "the bar was lowered by six" would miss what happened. It moves sites in both
directions: it exonerates the shapes §8 names (list captions, timestamps, counts
of a list's own contents, ordinals, separators) and, through **A5**, it catches
primary simulation output that the uniqueness bar had split inconsistently
between rows of the same transcript. Both controls in §2.1 hold, which is the
claim worth making; the count is nearly unchanged and is not evidence of
anything.

## 3. Grounds

### 3.1 The twelve opaque grounds

Pinned by `DesignTokensTests+MutedAsContent`; §8 carries the same span. `muted`
runs **2.136–4.152** across them, against §8's single stated calibration of
≈3.3:1 on `screenBackground`.

| Light ground | ratio | Dark ground | ratio |
|---|---|---|---|
| `screenBackground` | 3.329 ← §8's calibration point | `nightBackground` | 3.779 |
| `bubbleBackground` | 3.475 | `nightBubble` | 3.021 |
| `promoBackground` | 3.319 | `nightPromoBackground` | 3.161 |
| `page` | 3.030 | `nightPage` | 4.152 ← dark's best |
| `whisperBubble` | 2.953 | `nightWhisperBubble` | 2.783 |
| `mossSoft` | **2.136** ← worst | `nightMossSoft` | 2.413 |

These figures are computed by the fixture and pinned there as
`opaqueGroundPins`, which the fixture compares against what it recomputes.
`scripts/check-measurement-transcripts.py` holds this table equal to those pins
— edit the table alone and it goes red (#1488). §8 **of this ledger** has the
procedure; the two `§8`s in the paragraph above are design-system.md's.

### 3.2 Composited grounds — measured, and separately from the twelve

Translucent washes the app paints under `muted` text. sRGB alpha-composite, then
the same WCAG formula the fixture uses.

Now **measured by the fixture itself** — `DesignTokensTests+MutedAsContent`'s
three wash arrays compute every figure below at test time, so the table is a
transcript rather than a second source. An earlier revision of this section was
neither, and was wrong three ways; the record is at ADR-028 § Amendment
2026-08-15. **Compose ratios with the fixture's own `composite` /
`contrastRatio`**, per `swiftui-traps.md` § "Adding a `Color` design token".

| Site | Wash over ground | light | dark |
|---|---|---|---|
| `ResultsView.pillBackground(.pending)` | `muted@0.14` — a **self-wash** — over `screenBackground` / `nightBackground` | 2.895 | 3.239 |
| `ActiveModelChip` capsule | `mossDark@0.10` over `screenBackground` / `nightBackground` | 2.953 | 3.098 |
| `ModelRow` selected | `moss@0.06` over `bubbleBackground` / `nightBubble` | 3.287 | **2.693** |
| `ReportSheet` meta chip | `rule@0.45` over an unknown ground — see below | 2.300–3.018 | 2.520–3.503 |
| `HighlightShareCard` model name | `moss@0.14` / `nightMoss@0.10` light leak over the card background — bound at maximum leak | 2.932 | 3.140 |

These figures are computed by the fixture and pinned there as `washRowPins`.
`scripts/check-measurement-transcripts.py` holds this table equal to those pins,
and holds ADR-028 § Amendment 2026-08-15's four-row copy to them as well
(#1488). Until then the transcript claim above this table was only a claim: the
fixture's arms were all inequalities, orderings and counts, so no ratio was
named anywhere for a table to be a transcript *of*.

Corrections beyond the arithmetic, all from reading the sites rather than the
table:

- **`ActiveModelChip` is not on the card ground.** It is a `HomeView`
  `ToolbarItem` under `.toolbarBackground(.hidden,)`, so it reads against
  Home's `screenBackground`. Its dark figure moves 2.434 → 3.098, which retires
  it as this section's notable low.
- **`ModelPickerView` / `ModelRow`'s `moss@0.08`–`moss@0.12` accents are not
  `muted` grounds at all** and are dropped. The `moss@0.08` disc is the
  decorative avatar backing and the `moss@0.12` chip draws `mossOnWash`;
  neither carries `muted` text. Only the row's own `moss@0.06` selection
  background does.
- **`ReportSheet`'s ground is not a Pastura token.** The sheet sets no
  background (§3.3), so the single figure the old table gave was computed
  against a `screenBackground` it never names. The range above is instead
  `rule@0.45` over **every** opaque ground, worst at `mossSoft` 2.300 / 
  `nightMossSoft` 2.520, plus pure white and pure black as **brackets**. Sub-AA
  at both extremes holds over every opaque ground, this one included. The twelve
  alone would not license "whatever the sheet resolves to" — the system surface
  is not one of them — and why bracketing closes that is derived at
  `mutedRuleWashGrounds`' doc comment, beside the four `mutedRuleWashBrackets`
  entries it licenses.

**These are unmeasured, not a new worst case** — and that conclusion survived
the re-measurement, which is the one thing here worth carrying forward. The new
low among the site-grounded rows is `ModelRow` dark at 2.693, and the widest
`rule` bound reaches 2.300; both still sit above the 2.136 `mossSoft` floor, so
the twelve-ground span continues to bound the token.
`compositedGroundsStayAboveTheOpaqueWorstCase` pins exactly that ordering, so
it fails rather than quietly becoming false. What the section establishes is
narrower and is exactly #1448's part (b): **§8's exemption was never measured
here, so it cannot be cited here** — the ratio being "in range" is not the same
as the ground being covered.

### 3.3 Grounds that are not computable at all

`.ultraThinMaterial` and `.regularMaterial` composite whatever is behind them at
render time, so no static ratio exists. Four sites sit on one:
`DLCompleteOverlay`, `SimulationView`'s loading scrim, and two
`IdleFriendlyProgressView` call sites (both non-text). `SimulationView`'s scrim
subtitle is the one of those that is **text on `muted`**, and it is the reason
`DesignTokensTests+MutedAsContent`'s wash arrays stop at three: a material has
no ground to composite against, so the omission is a recorded exclusion rather
than a gap. The fixture says so at the arrays.

**A translucent ground over a translucent ground is a fourth kind**, and §3.2's
three washes do not cover it. `GameHeaderStatus`'s `foreground` draws `muted`
over a `muted@0.14` self-wash sitting on `screenBackground@0.78` — the header
wash is itself alpha over whatever the scroll position puts behind it, so the
base is as unknown as a material's. Recorded here rather than in §3.2, and owned
by batch 4 with the other composited questions. It is listed in §5 with its
ratio column reading *unmeasurable*, which is what pointed at the gap: §3.2
enumerated the measurable washes and §3.3 the materials, and this site is
neither.

A repoint on such a ground cannot be pinned by a ratio and must be argued by
**direction** instead: `inkSecondary` (#5A5A55) is darker than `muted` (#8A8A83)
and `nightInkSecondary` (#B0AC9C) is lighter than `nightMuted` (#7A7768), so
contrast rises in both appearances over any ground either token shares. That is
weaker than a measurement and is labelled as such wherever it is used.

Two further grounds are **sheet defaults** — `ScoreboardSheet`, `ReportSheet`,
`PersonaDetailSheet`, and `PhaseEditorSheet` set no Pastura background token at
all, so they render on the system sheet surface. Also outside the fixture.

## 4. Recorded refusal — retuning `muted` itself

Raised and refused. **The refusal is on the recorded decision, not on the
arithmetic**: ADR-028 § Amendment 2026-08-13 (#1427) states the defect is «the
application, not the token», and §8 makes the sub-AA value a deliberate
expression of §1's
「静謐・観察」. Retiring the tier is its own ADR, not a side effect of a sweep
chartered to apply it — and it would not discharge the sweep either, since
tinted grounds still need the family-pairing remedy (§8: «地を所有するファミリが
供給する»).

The arithmetic behind both halves — that a retune is viable and lands between
`muted` and `inkSecondary`, and that `mossSoft` would still require the remedy —
is recorded at ADR-028 § "Retuning `muted` itself, refused", so it is not
re-derived here.

## 5. The ledger

Verdicts: **S** sanctioned · **M** misapplication (class in brackets) ·
**U** unmeasured ground, exemption cannot be cited · **N** non-text (1.4.11,
out of §8's scope) · **P** `#Preview`, never ships · **C** comment mention.

`B` names the batch. `B1` is applied; everything else still ships as written.

### Components

| Site (file · symbol) | Ground | light/dark | Verdict | B |
|---|---|---|---|---|
| `ActiveModelChip` · chevron glyph | `mossDark@0.10` | 2.953 / 3.098 | N + U | B4 |
| `ActiveModelChip` · `dotColor(.inactive)` | `mossDark@0.10` | 2.953 / 3.098 | N + U | B4 |
| `ActiveModelChipPresenter` · doc comment | — | — | C | — |
| `AgentOutputRow` · share glyph | `screenBackground` | 3.329 / 3.779 | N | — |
| `AgentOutputRow` · `INNER VOICE` tag | `screenBackground` | 3.329 / 3.779 | S — discloser label, not the disclosed | — |
| `AgentOutputRow` · rationale comment | — | — | C | — |
| `AgentOutputRow` · `thoughtBody` | `screenBackground` | 3.329 / 3.779 | **M (A5)** — the model's inner monologue is product, not metadata | B2 |
| `DogMark` · `26 pt` / `44 pt` captions ×2 | `screenBackground` | — | P | — |
| `GameHeaderStatus` · `foreground` (paused/cancelled/error) | `muted@0.14` self-wash over `screenBackground@0.78` | unmeasurable | **M (A1)** + U — the run-state pill is the header's reason to exist | B4 |
| `GameHeaderStatus` · `washToken` | same | unmeasurable | N | — |
| `IdleFriendlyProgressView` · ellipsis stand-in | 3 caller grounds, 2 material | mixed | N — `isUITestMode` only | — |
| `PasturaCard` · `Text("2")` | `bubbleBackground` | — | P | — |
| `PasturaRowLabel` · disclosure chevron | `bubbleBackground` | 3.475 / 3.021 | N | — |
| `PasturaSection` · header `Text(title)` | `screenBackground` | 3.329 / 3.779 | S on contrast — **§2.2 routing question**, see §6 | B5 |
| `PersonaDetailSheet` · `PEEK AT THEIR SECRET` | sheet default | unmeasured | S — toggle affordance; the secret renders at `ink` | — |
| `SheepAvatar` · size captions ×4 | `screenBackground` | — | P | — |
| `SimulationResultCard` · rank ordinal | `bubbleBackground` | 3.475 / 3.021 | S — derivable from row order | — |
| `SimulationResultCard` · `survivalRow` name (eliminated) | `bubbleBackground` | 3.475 / 3.021 | **M (A3)** — restrictive control | B3 |
| `SimulationResultCard` · `groupHeader` | `bubbleBackground` | 3.475 / 3.021 | S — redundant with per-row strikethrough + dot | — |
| `SimulationResultCard` · `valueText` (eliminated) | `bubbleBackground` | 3.475 / 3.021 | **M (A3)** — the card's final tally | B3 |
| `SimulationResultCard` · `nameColor` (eliminated) | `bubbleBackground` | 3.475 / 3.021 | **M (A3)** — `.ranking`/`.pairing` sibling of the row above | B3 |

The eliminated-row verdicts split from the state cue deliberately: **the
elimination is redundantly encoded** (strikethrough + `xmark.circle.fill`), so
dimming it costs nothing — but the **name and the number are not**, and they are
what the reader came to compare.

### Simulation · Report

| Site (file · symbol) | Ground | light/dark | Verdict | B |
|---|---|---|---|---|
| `HighlightCandidatesSection` · section caption | `bubbleBackground` | 3.475 / 3.021 | S — explains the section above it | — |
| `HighlightCandidatesSection` · share glyph | `bubbleBackground` | 3.475 / 3.021 | N | — |
| `ScoreboardSheet` · rank numeral | sheet default | unmeasured | S — derivable from order | — |
| `ScoreboardSheet` · name (eliminated) | sheet default | unmeasured | **M (A3)** + U — restrictive control | B3 |
| `ScoreboardSheet` · score (eliminated) | sheet default | unmeasured | **M (A3)** + U — restrictive control | B3 |
| `SimulationView` · `%@ is thinking…` | `screenBackground` | 3.329 / 3.779 | S — transient, superseded when the agent speaks | — |
| `SimulationView` · scrim-label comment | — | — | C | — |
| `SimulationView` · loading-scrim subtitle | `.regularMaterial` | unmeasurable | S + U — elaborates a title already at `ink` | B4 |
| `SimulationView+Background` · BG-continuation glyph | `screenBackground` | 3.329 / 3.779 | N | — |
| `SimulationView+LogEntries` · `assignmentEntry` | `screenBackground` | 3.329 / 3.779 | **M (A5)** | B2 |
| `SimulationView+LogEntries` · `voteResultsEntry` | `screenBackground` | 3.329 / 3.779 | **M (A5)** | B2 |
| `SimulationView+LogEntries` · `pairingResultEntry` `vs` | `screenBackground` | 3.329 / 3.779 | S — separator | — |
| `SimulationView+LogEntries` · `eventInjectedEntry` miss | `screenBackground` | 3.329 / 3.779 | **M (A4)** | B2 |
| `SimulationView+LogEntries` · `turnSkippedEntry` icon | `screenBackground` | 3.329 / 3.779 | N | — |
| `SimulationView+LogEntries` · `turnSkippedEntry` text | `screenBackground` | 3.329 / 3.779 | **M (A4)** — ADR-021 D5 | B2 |
| `SimulationView+LogEntries` · `actionRejectedEntry` icon | `screenBackground` | 3.329 / 3.779 | N | — |
| `SimulationView+LogEntries` · `actionRejectedEntry` text | `screenBackground` | 3.329 / 3.779 | **M (A4)** — ADR-021 D5 | B2 |
| `SimulationView+LogEntries` · `scoresSummary` | `screenBackground` | 3.329 / 3.779 | **M (A5)** | B2 |
| `ViewerPredictionSheet` · eyebrow | `page` | 3.030 / 4.152 | S — category label | — |
| `ViewerPredictionSheet` · `%lld s left` | `page` | 3.030 / 4.152 | **M (A3)** — a deadline the user acts against; the sheet auto-skips at zero | B3 |
| `ReportSheet` · `ID: %@` chip | `rule@0.45` | 2.300–3.018 / 2.520–3.503 | S + U — the ID is embedded in the report URL anyway | B4 |

### Results · Home · ScenarioDetail

| Site (file · symbol) | Ground | light/dark | Verdict | B |
|---|---|---|---|---|
| `ResultDetailView` · turns-skipped banner | `screenBackground` | 3.329 / 3.779 | **M (A4)** | B2 |
| `ResultDetailView+CodePhaseRows` · `scoreUpdateRow` | `screenBackground` | 3.329 / 3.779 | **M (A5)** | B2 |
| `ResultDetailView+CodePhaseRows` · `voteResultsRow` | `screenBackground` | 3.329 / 3.779 | **M (A5)** | B2 |
| `ResultDetailView+CodePhaseRows` · `vs` | `screenBackground` | 3.329 / 3.779 | S — separator | — |
| `ResultDetailView+CodePhaseRows` · `assignmentRow` | `screenBackground` | 3.329 / 3.779 | **M (A5)** | B2 |
| `ResultDetailView+CodePhaseRows` · `eventInjectedRow` | `screenBackground` | 3.329 / 3.779 | **M (A4)** | B2 |
| `ResultDetailView+RowLayout` · `↳ sub-phase` | `screenBackground` | 3.329 / 3.779 | S — nesting marker | — |
| `ResultsView` · row chevron | `screenBackground` | 3.329 / 3.779 | N | — |
| `ResultsView` · `categoryCaption` | `screenBackground` or `bubbleBackground` | 3.329 / 3.021 worst | S — list caption, §8's named shape | — |
| `ResultsView` · timestamp | same | same | S — list caption | — |
| `ResultsView` · `degradedRunCaption` | same | same | **M (A4)** | B2 |
| `ResultsView` · `pillForeground(.pending)` | `muted@0.14` self-wash | 2.895 / 3.239 | S on role + **U** — see §6.2 | B4 |
| `ResultsView` · `pillBackground(.pending)` | row ground | — | N | — |
| `ResultsView+Timeline` · `N records` | `screenBackground` | 3.329 / 3.779 | S — count of the list below it | — |
| `HomeView` · `Scenarios` header | `screenBackground` | 3.329 / 3.779 | S on contrast — §2.2 routing, see §6 | B5 |
| `HomeCompactScenarioRow` · chevron | `screenBackground` | 3.329 / 3.779 | N | — |
| `HomeCompactScenarioRow` · `caption` | `screenBackground` | 3.329 / 3.779 | **S — permissive control** | — |
| `ScenarioDetailView+Sections` · description | `screenBackground` | 3.329 / 3.779 | **M (A5)** — the scenario's own description | B2 |
| `ScenarioDetailView+Sections` · phase ordinal | `bubbleBackground` | 3.475 / 3.021 | S — derivable from order | — |

### Settings · ModelSelection · ModelDownload

| Site (file · symbol) | Ground | light/dark | Verdict | B |
|---|---|---|---|---|
| `SettingsView` · BG-continuation caption | `bubbleBackground` | 3.475 / 3.021 | S — expands the toggle title | — |
| `SettingsView` · prediction caption | `bubbleBackground` | 3.475 / 3.021 | S — expands the toggle title | — |
| `SettingsView+Models` · `Models` header | `screenBackground` | 3.329 / 3.779 | S on contrast — §2.2 routing, see §6 | B5 |
| `SettingsView+Models` · switch-blocked reason | `screenBackground` | 3.329 / 3.779 | **M (A1)** | **B1** |
| `SettingsView+PastResults` · `Clear all results` (blocked) | `bubbleBackground` | 3.475 / 3.021 | routing → `disabledText`, see §6.1 | B4 |
| `SettingsView+PastResults` · `Storage used: %@` | `screenBackground` | 3.329 / 3.779 | **M (A3)** | **B1** |
| `SettingsView+PastResults` · clear-blocked reason | `screenBackground` | 3.329 / 3.779 | **M (A1)** | **B1** |
| `ModelSettingsRow` · `·` separator | `bubbleBackground` | 3.475 / 3.021 | S — separator | — |
| `ModelSettingsRow` · `.checking` | `bubbleBackground` | 3.475 / 3.021 | **M (A1)** | **B1** |
| `ModelSettingsRow` · `.unsupportedDevice` | `bubbleBackground` | 3.475 / 3.021 | **M (A1)** | **B1** |
| `OrphanedModelFileRow` · on-disk filename | `bubbleBackground` | 3.475 / 3.021 | **M (A3)** — identifies what a delete removes | **B1** |
| `ModelPickerView` · `PASTURA · SETUP` | `screenBackground` | 3.329 / 3.779 | S — branding eyebrow | — |
| `ModelPickerView` · add-later reassurance | `screenBackground` | 3.329 / 3.779 | S — footnote | — |
| `ModelRow` · vendor · size meta | `moss@0.06` when selected, else `bubbleBackground` | 3.287 / 2.693 | **M (A3)** + U — bundles the file size | B4 |
| `ModelDownloadHostView+CodePhaseRows` · `codePhaseContent` `.assignment` arm | `screenBackground` | 3.329 / 3.779 | **M (A5)** | B2 |
| `ModelDownloadHostView+CodePhaseRows` · `voteResultsContent` | `screenBackground` | 3.329 / 3.779 | **M (A5)** | B2 |
| `ModelDownloadHostView+CodePhaseRows` · `scoresContent` | `screenBackground` | 3.329 / 3.779 | **M (A5)** | B2 |
| `ModelDownloadHostView+CodePhaseRows` · `vs` | `screenBackground` | 3.329 / 3.779 | S — separator | — |
| `ModelDownloadHostView+CodePhaseRows` · `eventInjectedContent` | `screenBackground` | 3.329 / 3.779 | **M (A4)** | B2 |
| `DLCompleteOverlay` · `Tap anywhere to begin` | `.ultraThinMaterial` | unmeasurable | **M (A2)** — the overlay is tap-gated | **B1** |

### Community · Editor

| Site (file · symbol) | Ground | light/dark | Verdict | B |
|---|---|---|---|---|
| `GalleryCatalogRow` · `N agents · N rounds` footer | `bubbleBackground` | 3.475 / 3.021 | S — §8's named caption shape | — |
| `GalleryScenarioDetailView` · external-link glyph | `screenBackground` | 3.329 / 3.779 | N | — |
| `GalleryScenarioDetailView` · step numeral | `bubbleBackground` | 3.475 / 3.021 | S — derivable from order | — |
| `GalleryScenarioDetailView` · read-only disclaimer | `screenBackground` | 3.329 / 3.779 | S — footnote | — |
| `GalleryScenarioDetailView` · detail-row values | `bubbleBackground` | 3.475 / 3.021 | **M (A3)** — `Est. inferences` is what a user checks a device against before running | B2 |
| `GalleryScenarioDetailView+Highlight` · `hook.caption` | `bubbleBackground` | 3.475 / 3.021 | S — footnote on the excerpt | — |
| `GalleryScenarioDetailView+Highlight` · edit invitation | `bubbleBackground` | 3.475 / 3.021 | S — the CTA is the button | — |
| `GalleryScenarioDetailView+RecommendedModel` · switch-blocked reason | `bubbleBackground` | 3.475 / 3.021 | **M (A1)** | **B1** |
| `SharedScenariosListView` · `Last updated: %@` | `screenBackground` | 3.329 / 3.779 | S — feed-freshness footnote | — |
| `PhaseBlockRow` · drag handle | `bubbleBackground` | 3.475 / 3.021 | N | — |
| `PhaseEditorSheet+ConditionalSection` · chevron | sheet default | unmeasured | N | — |
| `ScenarioEditorView` · `%lld agents` | `screenBackground` | 3.329 / 3.779 | S — counts the rows below | — |
| `ScenarioEditorView` · `%lld steps` | `screenBackground` | 3.329 / 3.779 | S — counts the rows below | — |

### Tally

The tables above print **94** lines for **98** sites — two rows collapse repeats
(`DogMark` ×2, `SheepAvatar` ×4), both `#Preview`. Expanded:

| | count |
|---|---|
| comment mentions | 3 |
| `#Preview`, never ships | 7 |
| **shipped** | **88** |
| — non-text (WCAG 1.4.11, out of §8's scope) | 16 |
| — sanctioned | 36 |
| — misapplication | 35 |
| — routing question (§6.1) | 1 |

Misapplications by batch: **B1 8 · B2 19 · B3 6 · B4 2**.

Nine rows additionally carry **U**, a ground §8's exemption was never measured
on — four of them already misapplications (`GameHeaderStatus`, `ModelRow`, and
both `ScoreboardSheet` rows), five otherwise sanctioned or non-text
(`ActiveModelChip` ×2, `SimulationView`'s scrim subtitle, `ReportSheet`,
`ResultsView`'s `.pending` pill). The five are the reason **U** is tracked
separately: they need no repoint, but §8 cannot currently be *cited* for them
either.

These counts are re-derivable from the tables — count `| \`` lines and expand the
two `×N` rows — rather than maintained by hand.

## 6. Decisions this sweep was chartered to make

### 6.1 The disabled `Clear all results` label

`isClearAllBlocked ? Color.muted : Color.danger`. This is not a contrast defect —
it is a **routing** one: the app has `disabledText` (#B5B0A2 / `nightDisabledText`
#605F54) for exactly this. §2.7 carries the two disabled *tokens* and nothing
about the bar; the exemption itself is recorded in **§2.9**'s `nightDisabledText`
row (WCAG 1.4.3's inactive-control carve-out). §8 does not mention disabled
controls at all — checked by reading its bullets, 2026-08-15 — so cite §2.9 for
the licence and §2.7 only for the token.

Correcting it therefore **lowers** the ratio, which §8 permits only when returning
to the token the norm points at — the same licence #1459 used. It is kept out of
batch 1 so a single PR does not mix raise-contrast and lower-contrast edits, whose
review arguments are opposite. Batch 4.

### 6.2 `ResultsView`'s `.pending` pill

Left on `muted`, and this is now a recorded verdict rather than a deferral.
`ResultsPillTokenTests.pendingStaysOnTheQuietudeTier` pins it precisely so this
sweep could not take it silently; the sweep looked and chose not to. The pill's
*role* is ambient (a run that has not started yet), so §8's tier is right — but
its ground is a `muted`-on-`muted` **self-wash** at 2.895 / 3.239, which §8's
exemption never measured. Recorded as **U** and revisited in batch 4 with the
other composited grounds, as one question rather than five.

### 6.3 §2.2's section labels — `--ink-2` or `--muted`

design-system §2.2 assigns section labels to `--ink-2` and records that
`PasturaSection` draws them with `--muted` instead, deferring the choice to «掃引時»
— this sweep. **Decision: align the code to the table.** §2.2 is the normative
statement of the role, #1298 already moved `ScenarioEditorView`'s two headers that
way, and no argument for the table being wrong surfaced in the audit.

Measured blast radius, larger than the three drawing sites suggest:

```sh
rg -l 'PasturaSection\(' Pastura/Pastura/Views/   # 9 consumers + the definition's own #Preview
```

Nine consumer files across five screens:
`GalleryScenarioDetailView`, `GalleryScenarioDetailView+Highlight`,
`SharedScenariosListView`, `ResultsView`, `ScenarioDetailView+Sections`,
`SettingsView`, `SettingsView+Feedback`, `SettingsView+Models`,
`SettingsView+PastResults` — plus the two hand-rolled headers
(`HomeView.scenariosSectionHeader`, `SettingsView+Models.modelsHeader`) and a
third variant §2.2 names as still on the system `secondaryLabel`. Use the
**call-shape** grep above; a type-name grep also matches `PasturaSectionStyle`.

Decided here, applied in batch 5 under #1485 — the change is visual,
app-wide, and needs ADR-028 gate 4/5 QA of its own.

## 7. Batches

| | Scope | Sites | State |
|---|---|---|---|
| **B1** | Blocked-state reasons, the tap-to-proceed instruction, and act-on numbers, in Settings / model management / gallery | 8 | **applied (#1448)** |
| **B2** | A4 + A5 — the simulation transcript and past-run detail rows: assignments, tallies, score summaries, degraded-turn narration, the scenario description, the gallery detail rows | 19 | open — **ADR-028 gate 4/5 device QA required** |
| **B3** | Eliminated-player rows (`ScoreboardSheet`, `SimulationResultCard`) and the prediction countdown | 6 | open |
| **B4** | Composited and material grounds as one question — the self-wash pills, `ActiveModelChip`, `ModelRow`, `ReportSheet`, `GameHeaderStatus` — plus §6.1's routing fix | 2 misapplications + 1 routing, over 8 rows carrying 7 of the 9 **U** flags | open |
| **B5** | §6.3's §2.2 alignment across 9 `PasturaSection` consumer files (5 screens) + 2 hand-rolled headers + the `secondaryLabel` variant | — | open — #1485 |

B2 is the larger visual change of the two batches carrying a QA note — nineteen
sites across the transcript and past-run detail, moving in the raise-contrast
direction on the app's core reading surfaces. It is also the batch where a test
cannot see the risk: `SimulationView+LogEntries` and
`ModelDownloadHostView+CodePhaseRows` are a **byte-for-byte duplicated pair**
(the DL-time demo mirrors the live log deliberately), so applying one and not
the other diverges the two visually while every count in `MutedSweepLedgerTests`
still reconciles.

Batches are ordered by how settled the judgement is, not by size. B2 and B3 are
straightforward applications of §2 once B1 establishes the shape; B4 needs §8 to
say what a *material or otherwise unmeasurable* ground routes to before any
site moves — the routing for a merely-composited one is already in §8's
`*-on-wash` bullet, so stating the gate that way would leave it already
satisfied; B5 is a visual
change to five screens — six with the hand-rolled headers — across nine files.

## 8. Regenerating this ledger

The population moves. Before working a batch:

```sh
grep -rn "Color\.muted" Pastura/Pastura --include="*.swift" | grep -vcE ':[0-9]+: *///?'
```

Compare against §1's figure and the per-file expectations in
`MutedSweepLedgerTests` — that guard is the mechanical mirror of §5 and fails on
an **addition** as well as on a regression, which prose alone cannot do. A row
whose file+symbol no longer resolves was renamed, not fixed; re-adjudicate it
against §2 rather than deleting it.

### Regenerating the ratio tables (§3.1 / §3.2)

Different procedure, different trigger: the count above moves when a **site** is
added or repointed, these tables when the **palette** moves. Do not compute a
ratio by hand or with a fresh script — §8 of `design-system.md` records that a
hand-rolled one quantizing channels to 0–255 diverges from the fixture — one of
the ways the earlier revision of §3.2 went wrong.

```sh
scripts/xcodebuild.sh test -only-testing PasturaTests/DesignTokensTests
python3 scripts/check-measurement-transcripts.py --self-test
python3 scripts/check-measurement-transcripts.py --check
```

`docTranscriptsMatchTheComputedFigures` prints every figure that moved as a
ready-to-paste pin literal; paste those into the fixture, then carry the same
three-digit figures here. The `--check` run names each doc face still
disagreeing, ADR-028's copy included, and stays red until they all agree.

Two things it does **not** do.

It never tells you a row's *site* is wrong — §3.2 files its own corrections under
«beyond the arithmetic, all from reading the sites rather than the table», and no
pin would have caught one of them.

And it reads only the anchored **tables and span blocks**, so a figure restated
anywhere else stays hand-kept: §5's per-site ratio column, prose restatements of
a single figure (ADR-028's own decision-summary table row among them), this
ledger's §1.1 / §2.1 / §6.2, the fixture's doc-comment prose, and two further
test files plus one production doc comment. That list is measured, not recalled —
#1496 carries the enumeration and the command that reproduces it. `ds/*.html` is
**not** on it: it does carry three-decimal ratios, but of a different population
(ground-vs-ground contrast, per-channel pair gaps), none a copy of these pins.
