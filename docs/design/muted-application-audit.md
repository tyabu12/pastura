# `muted` application audit (#1448)

Ledger for the app-wide sweep of `Color.muted`, design-system §8's deliberately
sub-AA "quietude" tier. Companion to [design-system.md](design-system.md) §8 and
to [ADR-028](../decisions/ADR-028.md) § "Amendment 2026-08-13 — the quietude tier
is ground-relative (#1427)", which scoped this sweep and fixed its two worked
examples in `PredictionOutcomeBadge`.

**This file is the sweep's ledger, not its rule.** §8 remains normative; what is
recorded here is the per-site *application* of §8 across the population, plus the
adjudications that were judgement calls. The sweep runs in batches — batches 1,
2, 3 and 5 are applied; every other row still ships as written.

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
`docs/agent-tooling/knowledge-layering.md` § Detection is actually about — repo
*trackedness* — so an untracked scratch `.swift` under `Views/` would enter the
census and redden `MutedSweepLedgerTests`, which walks the filesystem rather
than the index. Reach for `git ls-files -z | xargs -0 grep -nH` when that
matters. Watch the
sibling `+Feature.swift` split: cross-check against
`find Pastura/Pastura/Views -name '*.swift'` (`docs/agent-tooling/knowledge-layering.md` § Scope & Completeness
Discipline).

Batch 1 removed eight occurrences and emptied three files; batch 5 (#1485)
removed three more and emptied three more; batch 2 repointed nineteen sites for
a net eighteen occurrences and emptied none; batch 3 repointed six — the
eliminated rows in `SimulationResultCard` / `ScoreboardSheet` and the prediction
countdown — and emptied none either. So the population as it ships today is
**64 lines · 4 doc-comment mentions · 60 code sites across 37 files**.
`MutedSweepLedgerTests` pins the per-file breakdown — §8.

The mentions went 3 → 4 because batch 2's why-comment in `ResultDetailView`
names the token it left behind. **A comment mention is not a site** — §8's
command and the guard both skip comment lines, but the raw line count above
counts them, so it moved by seventeen while the occurrence count moved by
eighteen.

**Nineteen sites, eighteen occurrences: the gap is `ResultDetailView`.** Its
degraded banner was one `Label` carrying a single `.foregroundStyle`, so moving
the text off `muted` meant tinting the two slots separately, and the glyph kept
the spelling. That occurrence is an **addition this sweep made**, not a survivor
— see the second `ResultDetailView` row in §5.

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

Pinned by `DesignTokensTests+MutedTranscript`; §8 carries the same span. `muted`
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

Computed by `DesignTokensTests+MutedAsContent`, pinned in its sibling
`DesignTokensTests+MutedTranscript` as `opaqueGroundPins`, and held equal to this
table by `scripts/check-measurement-transcripts.py` — edit the table alone and it
goes red (#1488). **The rows are also where §5's check learns which dark ground
answers which light one**: `opaqueGroundPins` is flat and its order differs from
this table's, so nothing above this table carries that pairing. Permute the dark
halves of the three rows §5 names (`screenBackground`, `bubbleBackground`,
`page`) and 28–72 §5 rows redden — measured over all five non-identity
permutations, not the three transpositions alone. Permute them among the other
three and **none** does; that half of the pairing stays unguarded (#1496).
Procedure: §8 **of this ledger**. Every other `§8` above — the intro paragraph,
the table's calibration-point cell — is design-system.md's.

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

Same wiring, as `washRowPins` — and the checker holds ADR-028 § Amendment
2026-08-15's four-row copy to those pins too (#1488). The `Wash over ground`
column is read as well: its leading backticked token is what a §5 row joins on,
so two rows sharing one raises rather than collapsing (#1496). Until then the
transcript claim above this table was only a claim:
`DesignTokensTests+MutedAsContent`'s arms were all inequalities, orderings and
counts, so no ratio was named anywhere for a table to be a transcript *of*.

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

A repoint on such a ground cannot be pinned by a ratio. **Reach for a nominal
ground first** — where an opaque floor exists under the translucency, measure
against it and label the row *nominal* rather than a bound (design-system §8,
routing priority 1). Only where no floor can be written is the repoint argued by
**direction** instead: `inkSecondary` (#5A5A55) is darker than `muted` (#8A8A83)
and `nightInkSecondary` (#B0AC9C) is lighter than `nightMuted` (#7A7768).

⚠️ **That does not by itself mean contrast rises**, and an earlier revision of
this paragraph said it did — «over any ground either token shares», which is
false. Moving a foreground darker raises the ratio only while the ground is
*lighter than `muted` itself*; over a ground darker than both tokens the
comparison inverts and the repoint **lowers** it, because `muted` is then the
token further from the ground. So the direction argument carries a side
condition: it is available only when the ground can be shown to stay lighter
than `muted` in light, and darker than `nightMuted` in dark. Where that cannot
be shown, go back to a nominal measurement or leave the site alone. Weaker than
a measurement either way, and labelled as such wherever it is used.

Two further grounds are **sheet defaults** — `ScoreboardSheet`, `ReportSheet`,
`PersonaDetailSheet`, and `PhaseEditorSheet` set no Pastura background token at
all, so they render on the system sheet surface. Also outside the fixture.
Batch 3 moved `ScoreboardSheet`'s two eliminated rows on this ground by the
direction argument above — the first sheet-default rows to move, labelled as
direction-argued in the file's own why-comment, and pinned by symbol in
`MutedSweepLedgerTests+BatchThree` rather than by any ratio.

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

`B` names the batch. `B1`, `B2`, `B3` and `B5` are applied; everything else still
ships as written. An applied row is **kept**, not deleted — the adjudication is what §5
records, and the bolded batch marker is what says the repoint landed.

**A third state exists, and the batch marker alone cannot express it.** A row can
be *looked at* by a batch and deliberately **not moved** — the sweep adjudicated
it and the answer was "stay". That is not the same as a row nothing has reached
yet, and it reads identically here: an unbolded `B` marker. So such a row says
**retained** in its verdict column, and §6.4 carries the per-site reasoning.
Reserve the word: **kept** is about the *row* surviving in this table, **retained**
is about the *site* keeping `muted`. B4 is where this first mattered, because it
is the batch that ends the sweep — after it, an unbolded marker with no
"retained" would wrongly read as unfinished work.

### Components

| Site (file · symbol) | Ground | light/dark | Verdict | B |
|---|---|---|---|---|
| `ActiveModelChip` · chevron glyph | `mossDark@0.10` | 2.953 / 3.098 | N + U | B4 |
| `ActiveModelChip` · `dotColor(.inactive)` | `mossDark@0.10` | 2.953 / 3.098 | N + U | B4 |
| `ActiveModelChipPresenter` · doc comment | — | — | C | — |
| `AgentOutputRow` · share glyph | `screenBackground` | 3.329 / 3.779 | N | — |
| `AgentOutputRow` · `INNER VOICE` tag | `screenBackground` | 3.329 / 3.779 | S — discloser label, not the disclosed | — |
| `AgentOutputRow` · rationale comment | — | — | C | — |
| `AgentOutputRow` · `thoughtBody` | `screenBackground` | 3.329 / 3.779 | **M (A5)** — the model's inner monologue is product, not metadata | **B2** |
| `DogMark` · `26 pt` / `44 pt` captions ×2 | `screenBackground` | — | P | — |
| `GameHeaderStatus` · `foreground` (paused/cancelled/error) | `muted@0.14` self-wash over `screenBackground@0.78` | unmeasurable | **M (A1)** + U — the run-state pill is the header's reason to exist | B4 |
| `GameHeaderStatus` · `washToken` | same | unmeasurable | N | — |
| `IdleFriendlyProgressView` · ellipsis stand-in | 3 caller grounds, 2 material | mixed | N — `isUITestMode` only | — |
| `PasturaCard` · `Text("2")` | `bubbleBackground` | — | P | — |
| `PasturaRowLabel` · disclosure chevron | `bubbleBackground` | 3.475 / 3.021 | N | — |
| `PasturaSection` · header `Text(title)` | `screenBackground` | 3.329 / 3.779 | S on contrast — routing → `--ink-2`, see §6.3 | **B5** |
| `PersonaDetailSheet` · `PEEK AT THEIR SECRET` | sheet default | unmeasured | S — toggle affordance; the secret renders at `ink` | — |
| `SheepAvatar` · size captions ×4 | `screenBackground` | — | P | — |
| `SimulationResultCard` · rank ordinal | `bubbleBackground` | 3.475 / 3.021 | S — derivable from row order | — |
| `SimulationResultCard` · `survivalRow` name (eliminated) | `bubbleBackground` | 3.475 / 3.021 | **M (A3)** — restrictive control | **B3** |
| `SimulationResultCard` · `groupHeader` | `bubbleBackground` | 3.475 / 3.021 | S — redundant with per-row strikethrough + dot | — |
| `SimulationResultCard` · `valueText` (eliminated) | `bubbleBackground` | 3.475 / 3.021 | **M (A3)** — the card's final tally | **B3** |
| `SimulationResultCard` · `nameColor` (eliminated) | `bubbleBackground` | 3.475 / 3.021 | **M (A3)** — `.ranking`/`.pairing` sibling of the row above | **B3** |

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
| `ScoreboardSheet` · name (eliminated) | sheet default | unmeasured | **M (A3)** + U — restrictive control | **B3** |
| `ScoreboardSheet` · score (eliminated) | sheet default | unmeasured | **M (A3)** + U — restrictive control | **B3** |
| `SimulationView` · `%@ is thinking…` | `screenBackground` | 3.329 / 3.779 | S — transient, superseded when the agent speaks | — |
| `SimulationView` · scrim-label comment | — | — | C | — |
| `SimulationView` · loading-scrim subtitle | `.regularMaterial` | unmeasurable | S + U — elaborates a title already at `ink` | B4 |
| `SimulationView+Background` · BG-continuation glyph | `screenBackground` | 3.329 / 3.779 | N | — |
| `SimulationView+LogEntries` · `assignmentEntry` | `screenBackground` | 3.329 / 3.779 | **M (A5)** | **B2** |
| `SimulationView+LogEntries` · `voteResultsEntry` | `screenBackground` | 3.329 / 3.779 | **M (A5)** | **B2** |
| `SimulationView+LogEntries` · `pairingResultEntry` `vs` | `screenBackground` | 3.329 / 3.779 | S — separator | — |
| `SimulationView+LogEntries` · `eventInjectedEntry` miss | `screenBackground` | 3.329 / 3.779 | **M (A4)** | **B2** |
| `SimulationView+LogEntries` · `turnSkippedEntry` icon | `screenBackground` | 3.329 / 3.779 | N | — |
| `SimulationView+LogEntries` · `turnSkippedEntry` text | `screenBackground` | 3.329 / 3.779 | **M (A4)** — ADR-021 D5 | **B2** |
| `SimulationView+LogEntries` · `actionRejectedEntry` icon | `screenBackground` | 3.329 / 3.779 | N | — |
| `SimulationView+LogEntries` · `actionRejectedEntry` text | `screenBackground` | 3.329 / 3.779 | **M (A4)** — ADR-021 D5 | **B2** |
| `SimulationView+LogEntries` · `scoresSummary` | `screenBackground` | 3.329 / 3.779 | **M (A5)** | **B2** |
| `ViewerPredictionSheet` · eyebrow | `page` | 3.030 / 4.152 | S — category label | — |
| `ViewerPredictionSheet` · `%lld s left` | `page` | 3.030 / 4.152 | **M (A3)** — a deadline the user acts against; the sheet auto-skips at zero | **B3** |
| `ReportSheet` · `ID: %@` chip | `rule@0.45` | 2.300–3.018 / 2.520–3.503 | S + U — the ID is embedded in the report URL anyway | B4 |

### Results · Home · ScenarioDetail

| Site (file · symbol) | Ground | light/dark | Verdict | B |
|---|---|---|---|---|
| `ResultDetailView` · turns-skipped banner text | `screenBackground` | 3.329 / 3.779 | **M (A4)** | **B2** |
| `ResultDetailView` · turns-skipped banner glyph | `screenBackground` | 3.329 / 3.779 | N — **added by B2**, see below | — |
| `ResultDetailView+CodePhaseRows` · `scoreUpdateRow` | `screenBackground` | 3.329 / 3.779 | **M (A5)** | **B2** |
| `ResultDetailView+CodePhaseRows` · `voteResultsRow` | `screenBackground` | 3.329 / 3.779 | **M (A5)** | **B2** |
| `ResultDetailView+CodePhaseRows` · `vs` | `screenBackground` | 3.329 / 3.779 | S — separator | — |
| `ResultDetailView+CodePhaseRows` · `assignmentRow` | `screenBackground` | 3.329 / 3.779 | **M (A5)** | **B2** |
| `ResultDetailView+CodePhaseRows` · `eventInjectedRow` | `screenBackground` | 3.329 / 3.779 | **M (A4)** | **B2** |
| `ResultDetailView+RowLayout` · `↳ sub-phase` | `screenBackground` | 3.329 / 3.779 | S — nesting marker | — |
| `ResultsView` · row chevron | `screenBackground` | 3.329 / 3.779 | N | — |
| `ResultsView` · `categoryCaption` | `screenBackground` or `bubbleBackground` | 3.329 / 3.021 worst | S — list caption, §8's named shape | — |
| `ResultsView` · timestamp | same | same | S — list caption | — |
| `ResultsView` · `degradedRunCaption` | same | same | **M (A4)** | **B2** |
| `ResultsView` · `pillForeground(.pending)` | `muted@0.14` self-wash | 2.895 / 3.239 | S on role + **U** — see §6.2 | B4 |
| `ResultsView` · `pillBackground(.pending)` | row ground | — | N | — |
| `ResultsView+Timeline` · `N records` | `screenBackground` | 3.329 / 3.779 | S — count of the list below it | — |
| `HomeView` · `Scenarios` header | `screenBackground` | 3.329 / 3.779 | S on contrast — routing → `--ink-2`, see §6.3 | **B5** |
| `HomeCompactScenarioRow` · chevron | `screenBackground` | 3.329 / 3.779 | N | — |
| `HomeCompactScenarioRow` · `caption` | `screenBackground` | 3.329 / 3.779 | **S — permissive control** | — |
| `ScenarioDetailView+Sections` · description | `screenBackground` | 3.329 / 3.779 | **M (A5)** — the scenario's own description | **B2** |
| `ScenarioDetailView+Sections` · phase ordinal | `bubbleBackground` | 3.475 / 3.021 | S — derivable from order | — |

### Settings · ModelSelection · ModelDownload

| Site (file · symbol) | Ground | light/dark | Verdict | B |
|---|---|---|---|---|
| `SettingsView` · BG-continuation caption | `bubbleBackground` | 3.475 / 3.021 | S — expands the toggle title | — |
| `SettingsView` · prediction caption | `bubbleBackground` | 3.475 / 3.021 | S — expands the toggle title | — |
| `SettingsView+Models` · `Models` header | `screenBackground` | 3.329 / 3.779 | S on contrast — routing → `--ink-2`, see §6.3 | **B5** |
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
| `ModelDownloadHostView+CodePhaseRows` · `codePhaseContent` `.assignment` arm | `screenBackground` | 3.329 / 3.779 | **M (A5)** | **B2** |
| `ModelDownloadHostView+CodePhaseRows` · `voteResultsContent` | `screenBackground` | 3.329 / 3.779 | **M (A5)** | **B2** |
| `ModelDownloadHostView+CodePhaseRows` · `scoresContent` | `screenBackground` | 3.329 / 3.779 | **M (A5)** | **B2** |
| `ModelDownloadHostView+CodePhaseRows` · `vs` | `screenBackground` | 3.329 / 3.779 | S — separator | — |
| `ModelDownloadHostView+CodePhaseRows` · `eventInjectedContent` | `screenBackground` | 3.329 / 3.779 | **M (A4)** | **B2** |
| `DLCompleteOverlay` · `Tap anywhere to begin` | `.ultraThinMaterial` | unmeasurable | **M (A2)** — the overlay is tap-gated | **B1** |

### Community · Editor

| Site (file · symbol) | Ground | light/dark | Verdict | B |
|---|---|---|---|---|
| `GalleryCatalogRow` · `N agents · N rounds` footer | `bubbleBackground` | 3.475 / 3.021 | S — §8's named caption shape | — |
| `GalleryScenarioDetailView` · external-link glyph | `screenBackground` | 3.329 / 3.779 | N | — |
| `GalleryScenarioDetailView` · step numeral | `bubbleBackground` | 3.475 / 3.021 | S — derivable from order | — |
| `GalleryScenarioDetailView` · read-only disclaimer | `screenBackground` | 3.329 / 3.779 | S — footnote | — |
| `GalleryScenarioDetailView` · detail-row values | `bubbleBackground` | 3.475 / 3.021 | **M (A3)** — `Est. inferences` is what a user checks a device against before running | **B2** |
| `GalleryScenarioDetailView+Highlight` · `hook.caption` | `bubbleBackground` | 3.475 / 3.021 | S — footnote on the excerpt | — |
| `GalleryScenarioDetailView+Highlight` · edit invitation | `bubbleBackground` | 3.475 / 3.021 | S — the CTA is the button | — |
| `GalleryScenarioDetailView+RecommendedModel` · switch-blocked reason | `bubbleBackground` | 3.475 / 3.021 | **M (A1)** | **B1** |
| `SharedScenariosListView` · `Last updated: %@` | `screenBackground` | 3.329 / 3.779 | S — feed-freshness footnote | — |
| `PhaseBlockRow` · drag handle | `bubbleBackground` | 3.475 / 3.021 | N | — |
| `PhaseEditorSheet+ConditionalSection` · chevron | sheet default | unmeasured | N | — |
| `ScenarioEditorView` · `%lld agents` | `screenBackground` | 3.329 / 3.779 | S — counts the rows below | — |
| `ScenarioEditorView` · `%lld steps` | `screenBackground` | 3.329 / 3.779 | S — counts the rows below | — |

### Tally

The tables above print **95** lines for **98** sites. Two collapse repeats
(`DogMark` ×2, `SheepAvatar` ×4), both `#Preview`, and **one is not a baseline
row at all** — `ResultDetailView`'s banner glyph, which batch 2 created by
splitting a single `Label` tint into two. It is marked in place and excluded
from every figure below; the arithmetic is over the 94 rows the `9a40565a`
census had. Expanded:

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

These counts are re-derivable from the tables — count `| \`` lines **above this
`### Tally` heading**, expand the two `×N` rows, and drop the row marked **added
by B2** — rather than maintained by hand. The bound matters: the table just
above opens two of its own rows with `` | ` ``.

**They do not move when a batch applies**, and the gap that opens is not drift.
§5 keeps an applied row, so the row set — and this tally with it — stays the
`9a40565a` census of adjudications; §1 carries the population as it *ships*.
The difference between the two is exactly the applied batches.

**A batch can also add a row** — a different event from *applying*, which is why
the glyph row above is marked rather than folded in. A repoint that changes a
call's **shape** mints an occurrence the baseline census never adjudicated, so
§5 must be able to carry a row its own tally does not count. Expect it whenever
a batch splits one styling call into two or makes any other multi-slot move; a
plain token swap cannot cause it.

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

### 6.3 §2.2's section labels — decided `--ink-2`, applied in B5

design-system §2.2 assigned section labels to `--ink-2` and recorded that
`PasturaSection` drew them with `--muted` instead, deferring the choice to «掃引時»
— this sweep. (§2.2 no longer records the divergence or the deferral, having
been rewritten to the resolved state; its `--ink-2` assignment stands, and this
paragraph is the account of why.) **Decision: align the
code to the table.** §2.2 is the normative statement of the role, #1298 already
moved `ScenarioEditorView`'s two headers that way, and no argument for the table
being wrong surfaced in the audit.

**The edit is three `.foregroundStyle` call sites. The blast radius is not
three of anything** — `PasturaSection` draws for many screens from one line, so
that figure is the one that reads smallest and it is not any of the three below.
Those three are what sizes review and QA, one enumeration feeds all of them, and
conflating them mis-sizes the work in opposite directions. Read which one a
figure is before reusing it:

```sh
rg -l 'PasturaSection\s*[({]' Pastura/Pastura/Views/   # 11 = 10 consumers + the definition
```

- **10 consumer files.** The character class, not a bare `\(`: the
  trailing-closure form `PasturaSection { … }` is an untitled card, and
  `GalleryScenarioDetailView+RecommendedModel` reaches `PasturaSection` by no
  other spelling — a `\(`-only grep drops it silently. Both shapes are still
  **call-shape** greps; a type-name one additionally matches
  `PasturaSectionStyle`.
- **7 of those 10 draw a header.** An untitled call renders none, and three
  files pass no title anywhere: `SettingsView+Models`, `SharedScenariosListView`,
  and `GalleryScenarioDetailView+RecommendedModel` — the last of which reaches
  `PasturaSection` only by the trailing-closure form the bullet above is about;
  the other two use the paren form with `style:` alone. The drawing set is
  `SettingsView`, `SettingsView+Feedback`, `SettingsView+PastResults`,
  `ScenarioDetailView+Sections`, `ResultsView`, `GalleryScenarioDetailView`,
  `GalleryScenarioDetailView+Highlight`.
- **5 screens change visually** — the figure that sizes the QA. Settings,
  ScenarioDetail, Results and GalleryScenarioDetail from the seven above, plus
  Home for `HomeView.scenariosSectionHeader`. `SettingsView+Models.modelsHeader`
  is hand-rolled but sits on Settings, already counted; さがす
  (`SharedScenariosListView`) is a consumer that renders **no** header, so it is
  not a QA screen.

Two hand-rolled headers sit outside `PasturaSection` and take the same decision:
`HomeView.scenariosSectionHeader` and `SettingsView+Models.modelsHeader`.

Decided here, **applied in batch 5 (#1485)** — those three call sites now draw
`--ink-2`, repainting the five screens above under ADR-028 gate 4/5 QA.

**One QA question comes from the repoint rather than from any token rule, and
it is structural — ask it once on each of the five screens, not five times.**
§2.2 assigns `--ink-2` to *both* section labels **and** subtext, so a header
that moves onto it now shares its colour with the quietest body text beneath
it, separated by size alone. Recorded here rather than in a PR body so it
outlives the merge. Every pairing below is individually correct; what is
unmeasurable is whether the header still reads subordinate to what it heads:

| Screen | Header vs. the `--ink-2` beneath it |
|---|---|
| Results | section title vs. a row's scenario description — **same colour *and* same `.subheadline`**; the priority screen |
| Home | `Scenarios` vs. the first row's `.footnote` description |
| ScenarioDetail | `Personas (N)` / `Phases (N)` vs. persona `.caption` descriptions and the non-LLM `PhaseTypeLabel` |
| GalleryScenarioDetail | `A glimpse of a real run` vs. the `.callout.italic()` teaser |
| Settings | `Models` vs. the switch-blocked reason (class A1, already on `--ink-2` since B1) |

If it reads badly the fix is one change to `PasturaSection`'s header treatment
(tracking, caps, weight), not five per-site patches — the collision comes from
the token table, not from any one screen. **Both appearances move the same way
and by close to the same factor** — this pair does not invert the way §2.3's
and §2.4's ladders do — so neither appearance is the safe side to skim. Figures
deliberately omitted: the `--ink-2` grounds are not among the pins, and §8's
"Regenerating the ratio tables" forbids computing one by hand to fill the gap.
Not a defect to pre-empt.

**§2.2's third treatment is not folded in, and what it raises is left open.**
Headers still on the system `secondaryLabel` are not a residue of this one:
they are every system `Form` / `List` section header in the app — **21 sites
across 9 files**, `LicensesSheet` ×2 plus 19 across the Editor sheet family — on
a substrate Pastura has never claimed. Moving them would answer *does Pastura
tokenize system `Form` / `List` section chrome?*, which nothing has decided, and
would roughly triple the QA. #1298 is evidence for narrowing rather than
against it: it moved `ScenarioEditorView`'s two headers because a `--muted`
count sat beside each inside one `HStack`, and its inline comment says so —
"only the count-bearing headers qualify". Tracked as **B6** in §7.

No single grep reproduces that 21, so the recipe is the record — two greps
over `Pastura/Pastura`, then three named subtractions:

```sh
grep -rn 'Section(String(localized' --include='*.swift' | grep -v PasturaSection   # 7
grep -rn '} header: {' --include='*.swift'                                          # 18
```

25 literals, minus the two hosted in a `Menu` (`ActiveModelChip` · `Active
model`, and `ResultDetailView` · `Developer`, itself `#if DEBUG`) and the two
`ScenarioEditorView` headers #1298 already tokenized = **21, over 9 files**.
`.headerProminence` and the legacy `Section(header:)` form are both zero
app-wide, and no `Section` literal exists outside `Views/`.

**21 is a floor on rendered headers, not a measurement of them.** Two of the
literals sit in helpers invoked twice — `PhaseEditorSheet+ConditionalSection`'s
`branchSection` (then / else) and `VariablePickerSheet`'s `group` — and both
render a runtime `Text(title)`, so ≥23 headers reach the screen and a future
grep keyed on a localized literal *inside* a header would miss them. The error
runs toward more work than stated, so it does not threaten the exclusion. Two further headers were
read and excluded as **not** §2.2 section labels: `ResultsView+Timeline`'s day
header and `HighlightCandidatesSection`'s `Share a highlight` are bold `ink`
titles, not subordinate labels.

### 6.4 The rows the sweep looked at and left alone

Five `muted` sites carry **U** — a ground §8's exemption was never measured on —
and were nonetheless **retained**. They are recorded together because "unmeasured"
is the thing they share and it is *not* what decided them: each one was decided on
**role**, exactly as §8's own bullet says a U row should be. Two different rules
supply the answer, which is why the group does not reduce to a count.

**Retained under §8's tier** — ambient roles, so the quietude tier is correct and
the unmeasured ground changes nothing:

| Site | Ground | Why the role is ambient |
|---|---|---|
| `ResultsView` · `pillForeground(.pending)` | `muted@0.14` self-wash | A run that has not started yet. The pill states a *pending* state whose content is elsewhere on the row; §6.2 records the verdict and `ResultsPillTokenTests.pendingStaysOnTheQuietudeTier` pins it so the sweep could not take it silently |
| `SimulationView` · loading-scrim subtitle | `.regularMaterial` | Elaborates a title already drawn at `ink`. Nothing here is the sole statement of anything — the scrim's title carries the state |
| `ReportSheet` · `ID: %@` chip | `rule@0.45` | The identifier is embedded in the report URL the sheet submits, so the user never has to read it off the screen to act |

**Retained under WCAG 1.4.11, not §8** — non-text, so §8's text bar never applied
in the first place:

| Site | Ground | Note |
|---|---|---|
| `ActiveModelChip` · chevron glyph | `mossDark@0.10` | A disclosure affordance's arrow, at 1.4.11's 3:1 bar |
| `ActiveModelChip` · `dotColor(.inactive)` | `mossDark@0.10` | A status dot; the state it encodes is also in the chip's label |

**Do not fold the two tables into one figure.** They agree on the outcome and
differ on the rule, and a later reader deriving "what §8's tier retains" from a
single number would inherit two non-text sites that §8 never governed. §5 marks
all five `retained` in the verdict column with an unbolded `B4`, per §5's intro.

**What this section is not.** It is not a licence to retain by default. Each row
above names the role that decided it, and the sweep moved every site whose role
was one of §2's five classes even where the ground was equally unmeasured — B1's
`DLCompleteOverlay`, B3's two `ScoreboardSheet` rows, B4's `GameHeaderStatus`
arms. The asymmetry between those and these is **role**, never measurability.

## 7. Batches

| | Scope | Sites | State |
|---|---|---|---|
| **B1** | Blocked-state reasons, the tap-to-proceed instruction, and act-on numbers, in Settings / model management / gallery | 8 | **applied (#1448)** |
| **B2** | A3 + A4 + A5 — the simulation transcript and past-run detail rows: assignments, tallies, score summaries, degraded-turn narration, the scenario description, and the gallery detail values (the one A3 here) | 19 | **applied (#1448)** |
| **B3** | Eliminated-player rows (`ScoreboardSheet`, `SimulationResultCard`) and the prediction countdown — all A3; the two `ScoreboardSheet` rows are the first **U** rows to move, by §3.3's direction argument | 6 | **applied (#1448)** |
| **B4** | Composited and material grounds as one question — the self-wash pills, `ActiveModelChip`, `ModelRow`, `ReportSheet`, `GameHeaderStatus`, the sites whose target token is undecided (a direction-argued repoint is outside this gate, §3.3) — plus §6.1's routing fix | 2 misapplications + 1 routing, over 8 rows carrying 7 of the 9 **U** flags | open |
| **B5** | §6.3's §2.2 alignment — the `PasturaSection` header plus 2 hand-rolled ones: 3 repointed call sites, 5 screens repainted | 3 | **applied (#1485)** |
| **B6** | §6.3's open question — system `Form` / `List` section headers still on `secondaryLabel`. **Not a `Color.muted` batch**: these sites carry no token at all, so nothing in §1, §5 or the census counts them — and unlike B2–B4, no unprompted guard ever routes an editor here. It therefore **outlives its own umbrella**: #1448 closes when the `Color.muted` census reads done, which B6 contributes nothing to. So — **do not close #1448 while this row is open; spin B6 out as its own issue at #1448-close time.** Needs the substrate decision before any site moves | 21 over 9 files | open — undecided |

B2 was the larger visual change of the two batches carrying a QA note — nineteen
sites across the transcript and past-run detail, moving in the raise-contrast
direction on the app's core reading surfaces. It is also the batch where a test
could not see the risk: `SimulationView+LogEntries` and
`ModelDownloadHostView+CodePhaseRows` are a **byte-for-byte duplicated pair**
(the DL-time demo mirrors the live log deliberately), so applying one and not
the other diverges the two visually while every count in `MutedSweepLedgerTests`
still reconciles. They were applied in one commit, and comparing the two screens
row-for-row is a **device-QA** step rather than something the diff settles — it
is written into `docs/qa/dark-mode-qa.md` § 2 so a later edit to one of them has
somewhere to be checked against.

**`MutedSweepLedgerTests+BatchTwo` pins B2's applied sites by symbol**, not by
per-file `Color.inkSecondary` count the way B5's arm does: in B2's densest files
roughly half of that token predates the batch, so a per-file total there cannot
attribute a revert to a site. The figures are in the doc comment on
`MutedSweepLedgerTests.expectedAppliedInkSecondary`, the one place they are kept.

B3 is pinned the same way (`MutedSweepLedgerTests+BatchThree`, sharing B2's
checker), and it is the batch where the *state cue* rather than a count is what
QA has to look at: an eliminated row kept its strikethrough and its xmark while
its name and tally rose one tier, so the row now differs from a survivor by one
ink step instead of two. Whether it still reads as *out* is the question
`docs/qa/dark-mode-qa.md` § 2 records, together with the countdown's — a
deadline that now outranks the eyebrow above it.

Batches are ordered by how settled the judgement is, not by size. B2 and B3 are
straightforward applications of §2 once B1 establishes the shape — with the
caveat B2 turned up: a site whose token sits on a `Label` or any other
multi-slot call cannot be repointed without changing the call's shape, and that
is a decision, not a swap (§5's added glyph row); B4 needs §8 to
say what a *material or otherwise unmeasurable* ground routes to before any
of **its** sites moves — the routing for a merely-composited one is already in
§8's `*-on-wash` bullet, so stating the gate that way would leave it already
satisfied. A direction-argued repoint on a §3.3 ground is **outside** that
gate, and two batches have made one: B1's `DLCompleteOverlay` (which carries no
**U** — its ground is a material, not merely unmeasured, so B3's rows are still
the first **U** rows to move) and B3's two `ScoreboardSheet` rows. Neither
claims a ratio, and both land on the token
§8's neutral-ground bullet already names; what B4 owes §8 is the answer for the
sites where the token might *not* be `--ink-2` — the self-wash pills and the
moss-washed chips, whose role is ambient and whose ground is tinted; B5
repoints three call sites but repaints five screens, because one
of the three is a shared component — §6.3 separates that figure from the three the
blast radius actually has.

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

Different trigger from the count above: that moves when a **site** is added or
repointed, these tables when the **palette** moves. Do not compute a ratio by
hand or with a fresh script — §8 of `design-system.md` records that a hand-rolled
one quantizing channels to 0–255 diverges from the fixture, one of the ways the
earlier revision of §3.2 went wrong.

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

And it reads **blocks, not sections** — the anchored tables (§3.1, §3.2, §5's
site tables, ADR-028's copy) and, per span section, the one block naming the
fixture. So a figure restated in running prose a few lines from a block that *is*
read stays hand-kept, across both doc and test files. **Don't enumerate those by
hand — print them**, because four hand-written versions of that list were wrong:

```sh
python3 scripts/check-measurement-transcripts.py --residue
```

`ds/*.html` does not appear: it carries three-decimal ratios, but of a different
population (ground-vs-ground contrast, per-channel pair gaps), none a copy of
these pins.

That list is no longer only *reported*. `--census` (#1496) holds its **shape** —
per file and class, a line count, a distinct-value count and a digest — against a
declaration in the checker, so a new copy is something someone classified rather
than something nobody saw. It runs in CI's `shell-tests` only, never in the
pre-commit gate, because it reads the working tree while that gate decides from
the index. When it fires, diff `--residue` against the declaration before pasting
anything: it names which direction fired — a copy appeared, was added, was
removed, or rotted (kept distinct from the pins having moved, which `--check`
settles) — but a rot leaves this scan in exactly the state a deletion does, and a
rot that keeps a face's line count unchanged is announced under the *addition*
preamble, which calls it "not a defect".

Read what it claims at the width of the mechanism. **Except for two gaps, no copy
written at the pins' three-decimal spelling reaches a tracked file without this
failing** — classified and declared inside the suffixes it scans, reported as
unclassified outside them, reported rather than skipped when a file will not
read. The gap that changes what a doc author writes is the first: round a figure
to fewer decimals and it passes silently. That one, the other, and the narrower
bound that applies to Swift are stated in the checker's module docstring — the
operative copy, what CI runs and what its failure text prints. Each line is
classified `code-comment`, `in-read-section`, or `argued`, and **none of the
three is a defect to drive to zero**. Derivation, why widening the compared
blocks to swallow the `in-read-section` class is not the cheap fix it looks, and
why one product-code copy was cut while this file's §1.1 / §2.1 / §6.2 prose
stays: ADR-028 § Amendment 2026-08-20 (#1496).

§5 is the one face that moved from that list into the gate, and it is checked
**row by row**: each row's `light/dark` figures must equal the pin its own
`Ground` cell names (#1496). A row carrying *another* row's value goes red —
which membership alone could not see, since every such figure is still a pin.

The mapping is derived, not hand-kept. §3.1 supplies the light↔dark pairing and
§3.2's `Wash over ground` column the wash join, so perturbing either reddens
rows here. Dispatch reads the `light/dark` cell first and the `Ground` cell only
after: `screenBackground` and `bubbleBackground` each carry both a figure pair
and a `—`, so reading the ground first would redden the three `#Preview` rows
that name a real ground and measure nothing. The forms that cell may take are
enumerated in the checker (`LEDGER_5_UNCOMPARED` and its siblings); a new one
**raises** rather than being skipped.

Membership is still run alongside it, but **on today's ledger it is subsumed** —
measured, after two drafts here claimed otherwise. A figure matching no pin
cannot equal its own ground's pin either, so both checks redden on one; and a
drifted sub-table header raises from both. What keeps it wired in is that the
subsumption belongs to the *form set*: membership reads every decimal in the
cell, the row check only cells matching a declared compared form, so a future
unmeasured form that still carries a figure would leave one and stay in the
other. That set is empty today.
