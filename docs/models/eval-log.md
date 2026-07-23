# Model Evaluation Log

Durable, committed ledger of model-candidate **evaluation verdicts** — the
judgment that a `/model-eval` (Gate 1) or real-device (Gate 2) pass produced,
so a verdict survives after the intake issue's comment is buried.

## What lives where (three record surfaces)

A verdict is recorded in three places with distinct roles — this file is the
durable, version-controlled one:

| Surface | Role | Durability |
|---|---|---|
| `data/models/eval-digest.md` | Raw per-cell scorecard (every axis + tok/s), **script-regenerated** by `/model-eval` | Gitignored, **per-machine** — re-sampling rewrites it |
| GitHub issue #979 | Rolling **intake queue** — triage, candidate proposals | Comment thread, buries over time |
| **This file** | The **verdict** (pass/fail + rationale + differentiation) | Committed, PR-reviewed |

**Anti-drift rule — entries carry judgment only.** An entry records the verdict,
date, model id/quant, one-line differentiation, rationale, and an aggregate
point-in-time snapshot — then **points to `data/models/eval-digest.md` for the
raw per-cell scores**. Do NOT copy the per-cell score matrix here: it is the
volatile, script-owned content of the gitignored digest, and a hand-copied
mirror goes stale the moment a cell is re-sampled.

**Scope vs. ADR-011.** The [ADR-011](../decisions/ADR-011.md) § "Alternatives
considered" Candidate A–F table is the committed home for the **6 GB-tier /
1B-class** candidates it tracks (Gemma 3 1B, DeepSeek R1 Distill 1.5B, Qwen 2.5
1.5B, …; it also lists a couple of larger models — Phi-4 mini, Apple FM — only to
reject them as out-of-tier-scope). This ledger is the general durable home for
every candidate **absent** from that table — notably full-tier (6.5 GB-minRAM)
models like Sarashina. Rule: a candidate in ADR-011's table is recorded there;
everything else here.

---

## Sarashina 2.2 3B Instruct v0.1 (Q4_K_M) — 2026-07-23 — **FAIL (NO-GO)**

- **Gate**: 1 (Mac filter, `/model-eval`) — re-eval after the #751 empty-output
  blocker was fixed (PR #1024); the original 2026-07-08 run was blocked, not
  cleanly quality-rejected.
- **Model**: `mmnga/sarashina2.2-3b-instruct-v0.1-gguf` · `Q4_K_M` · MIT,
  non-gated · ~2.07 GB · Stage-0 profile #1016 (`sarashina-2-2-3b-q4-k-m`).
- **Differentiation**: genuine **native-Japanese creative/humor** — the ja
  bokete / word_wolf cells reach idiomatic, culturally-grounded output neither
  incumbent matches (Gemma 4 E2B = expressive but English-fragile; Qwen 3 4B =
  analytical but ja-confused). A real third character — but **only** on ja
  creative presets.
- **Snapshot** (point-in-time; raw scores in the digest): 5/6 cells ok; the two
  ja creative cells are strong, everything else is weak — `prisoners_dilemma` ja
  broke down (3→4/5 agents drifted to **English in a ja scenario**), and
  `word_wolf` en **timed out at 600s on both attempts**. Slowest overall
  throughput of any evaluated model (4.86 tok/s vs incumbent Qwen 3 4B's 6.77).
- **Rationale**: a catalog slot would rest **solely** on ja-native humor while
  the model carries a ja-scenario breakdown risk (the English drift) and is
  impractically slow. Even the passing ja cells logged position-0 grammar
  resamples, so the ja character is unreliable outside pure-humor presets. The
  #751 empty-output path is gone from the 5 passing cells but **not retired** —
  it still fires in the failed `word_wolf` en cell. Independently concurred by a
  Fable second-opinion pass.
- **Disposition**: does **not** advance to the ADR-011 real-device PoC. Retain
  the #1016 Stage-0 profile; revisit only with a faster quant or a materially
  stronger JP-native successor.
- **Pointers**: raw scorecard → `data/models/eval-digest.md` §2026-07-23
  (gitignored) · intake → #979 · harness `language_mismatch`-detector bug
  surfaced during this eval → #1234.
