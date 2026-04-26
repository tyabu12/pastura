# Grammar-Constrained Sampling — Paired Baseline Procedure

> Pre-merge gate for #194 PR#b. ADR-002 §12.6 references this file as the
> authoritative measurement protocol. Numbers go into the PR description;
> the xcresult bundles stay local.

## Why paired

GBNF adds per-token grammar-state cost. The absolute tok/s on any given
device swings enough between cold / warm / thermal states that a single
post-PR number is noise. We want the **delta** between grammar OFF and
grammar ON under otherwise-identical conditions. One physical device,
same OS version, same scene-phase, same recent thermal history, model
loaded once per pair — that is the only measurement regime that isolates
the grammar contribution.

## What to measure

Two numeric gates (hard) and one qualitative observation (record
alongside):

| Signal | Source | Gate | Direction |
|--------|--------|------|-----------|
| Residual Hyp A rate | `scripts/analyze-streaming-diag.sh` → `retry cause=parse_failed` / total inferences | ≤ 1/100 | Lower is better |
| tok/s degradation | `inferenceCompleted` `tokenCount` + `durationSeconds` from the simulation export | ≤ 30 % | Smaller absolute-value delta is better |
| Persona consistency | Developer binary thumbs-up/down per session | Record as +/− + short note | Qualitative only |

Failing either numeric gate → consider lazy grammar (ADR-002 §12.3
fallback) before proceeding. Persistent qualitative regression → pin
the session fixtures as a regression corpus and re-evaluate the
hard-JSON choice.

## Scope

- **Simulator + physical device, both** — CI simulator clones mask
  thermal behaviour that surfaces on an iPhone 15 Pro / 16 Pro; the
  physical-device delta is the merge gate, the simulator pair is a
  sanity check.
- **Two presets: `prisoners_dilemma` AND `word_wolf`** — `prisoners_dilemma`
  exercises the `choose` enumeration path; `word_wolf` exercises the
  `vote` phase whose schema shape (`vote, reason`) and round-robin
  elimination logic neither of the other presets covers. The vote
  phase is the only place the enumeration-on-`action` pattern does
  NOT apply — so it catches "grammar works for choose but regresses
  for plain strings" by construction.
- **Speed: `.normal`** — the project default; `.slow` adds stream-jitter
  noise that obscures the grammar effect, `.instant` bypasses the
  event-layer gate.
- **Inferences per session: ≥30** — below that, the 1/100 gate has no
  resolution (a single retry would read as 3–5 %). 30 inferences
  ≈ 15 minutes on a 16 Pro per `prisoners_dilemma` run; budget
  ~1 hour per device × session matrix.

## Procedure

1. Start from a cold device (simulator: fresh clone; physical: force-quit
   + 5-min idle). Record thermal state from `Settings > Battery >
   Battery Health` baseline.
2. Load the preset, **grammar OFF** (pre-PR#b build: check out the
   commit before the #194 PR#b merge, or use a flag-off build if added).
3. Run the simulation through to completion. Do NOT interact mid-run
   (no Control Center, no scroll-back) — this run isolates baseline
   parse behaviour, not streaming UX.
4. Capture with Console.app, filter `subsystem:com.pastura
   category:StreamingDiag`, save the log to
   `/tmp/grammar-baseline-<preset>-<device>-off.log`.
5. Without model reload if possible (preserves KV/cache state), repeat
   with **grammar ON** (#194 PR#b build). Save to
   `/tmp/grammar-baseline-<preset>-<device>-on.log`.
6. Run `scripts/analyze-streaming-diag.sh` on both logs.
7. Export the simulation via the Share Sheet — Markdown export includes
   per-turn tok/s. Use this for the tok/s comparison.
8. Record the qualitative observation:
   - "Agents stayed in character" vs "output felt flat / out-of-character"
   - "Choose rationale was plausible" vs "inner_thought was near-duplicate of action"
   - Free-form one-sentence note per session.

## Report template

Paste into the #194 PR#b description under a `## Measurement` heading.

```
## Measurement (#194 PR#b)

### prisoners_dilemma — iPhone 16 Pro (A18 Pro, iOS 26.4)
- Inferences captured: 32 OFF / 31 ON
- Hyp A (parse retry): 1/32 OFF → 0/31 ON
- tok/s: 24.8 OFF → 22.1 ON (-11 %)
- Persona: + ("cooperative / betrayal reasoning stayed distinct")

### word_wolf — iPhone 16 Pro
- ...

### prisoners_dilemma — simulator (iPhone 17 Pro, macOS host)
- ...

### Verdict
- Hyp A ≤ 1/100: ✅ (both presets, both environments)
- tok/s ≤ 30 %: ✅ (max observed: -12 %)
- Persona: ✅ (all four sessions thumbs-up)
- Merge: APPROVED by measurement gate
```

## Re-running after model swap

When the model changes (Gemma 4 E2B → successor per ADR-002 §3), re-run
this protocol for the new model before relaxing the gate. A model change
can shift Hyp A baseline enough that the 1/100 threshold needs a sibling
`docs/measurements/grammar-<model>.md` rather than in-place updates here
(which would erase the Gemma-4 baseline).
