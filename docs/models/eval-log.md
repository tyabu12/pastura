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
| **This file** | The **verdict** (`pass` / `borderline` / `fail` / `blocked` + rationale + differentiation) | Committed, PR-reviewed |

**Anti-drift rule — entries carry judgment only.** An entry records the verdict,
date, model id/quant, one-line differentiation, rationale, and an aggregate
point-in-time snapshot — then **points to `data/models/eval-digest.md` for the
raw per-cell scores**. Do NOT copy the per-cell score matrix here: it is the
volatile, script-owned content of the gitignored digest, and a hand-copied
mirror goes stale the moment a cell is re-sampled.

### `BLOCKED` entries

`BLOCKED` is a **verdict of its own**, not a flavour of `FAIL`: the candidate
could not be *evaluated*, so it was never rejected and the outcome is
retry-gated. Vocabulary and admissibility are canonical in
`.claude/skills/model-eval/SKILL.md`
§ "`blocked` — admissibility and its two enforcement layers"; the flow position
is in [`onboarding.md`](onboarding.md). A `BLOCKED` entry here additionally
carries:

- **Unblocked by** — the named condition that would allow a retry.
- **Retry** — where the retry is tracked. The blocker's own issue is acceptable.

**The differentiation field maps across two artifacts, and only one of them is
validated.** `/model-eval` writes the gitignored digest, where `append_eval.py`
*enforces* the rule; this ledger is hand-authored and validated by nothing, so
the mapping is a convention you apply:

| Cells completed | digest JSON (`append_eval.py`, enforced) | this ledger (convention) |
|---|---|---|
| none `ok` | `differentiation` **absent** | `**Differentiation**: **UNASSESSABLE**` + why |
| ≥1 `ok` | `differentiation` **required**, scoped to the completed cells | the same text, stated as partial |
| ≥1 `ok`, too few to judge | `PARTIAL (n/6 cells) — insufficient to differentiate` (the validator checks only non-emptiness) | the same, verbatim — a sanctioned value, since a couple of cells rarely answers the slot-earning question |

`UNASSESSABLE` is how a total block satisfies the anti-drift rule's
one-line-differentiation requirement without fabricating a judgment from zero
inferences. `render_section` emits it for you **when no cell completed**, so it
survives the digest → ledger transcription; a partial block renders its real
differentiation instead, and must not be relabelled `UNASSESSABLE`.

**Heading form.** `## <model> — <date> — **BLOCKED (<one-line reason>)**`, not
the pre-#1419 `FAIL (BLOCKED …)`. Nothing validates this file, so the heading is
where the vocabulary will drift back first. One pre-#1419 blocked run
(Sarashina, 2026-07-08) has **no heading of its own** and is grandfathered
inside the 2026-07-23 entry — see the note there.

**Scope vs. ADR-011.** The [ADR-011](../decisions/ADR-011.md) § "Alternatives
considered" Candidate A–F table is the committed home for the **6 GB-tier /
1B-class** candidates it tracks (Gemma 3 1B, DeepSeek R1 Distill 1.5B, Qwen 2.5
1.5B, …; it also lists a couple of larger models — Phi-4 mini, Apple FM — only to
reject them as out-of-tier-scope). This ledger is the general durable home for
every candidate **absent** from that table — notably full-tier (6.5 GB-minRAM)
models like Sarashina. Rule: a candidate in ADR-011's table is recorded there;
everything else here.

---

## Gemma 4 E2B QAT Q4_0 (`google/gemma-4-E2B-it-qat-q4_0-gguf`) — 2026-08-08 — **BLOCKED (runtime compatibility — not evaluated, therefore not rejected)**

- **Gate**: 1 (Mac filter, `/model-eval`) — **blocked at model load, never
  reached inference.** All 6 battery cells failed in ~0.9 s each, 2 attempts
  apiece, with the identical scenario-independent error
  `llama_model_load: error loading model: missing tensor 'blk.15.attn_k.weight'`.
- **Model**: `google/gemma-4-E2B-it-qat-q4_0-gguf` @ `675cff4` ·
  `gemma-4-E2B_q4_0-it.gguf` · QAT `Q4_0` · Apache-2.0, non-gated · 3,349,516,256 B
  · sha256 `fa401b55…6634` (both matching the HF resolve `X-Linked-Size` /
  `X-Linked-ETag`). A *different build* of a catalog model — the shipped
  descriptor (`unsloth/gemma-4-E2B-it-GGUF` Q4_K_M, non-QAT) is unaffected and
  remains in the catalog. **No Stage-0 profile of its own** — the run reused the
  incumbent's `gemma-4-e2b-q4-k-m` profile, legitimate per
  [`onboarding.md`](onboarding.md) (Stage 0 is per *family*) after verifying the
  three prompt-format fields are equivalent; so the raw logs carry the
  incumbent's `modelIdentifier` and a retry still has no validated profile.
- **Differentiation**: **UNASSESSABLE** — zero inferences, so the QAT question is
  *untested*, not answered.
- **Snapshot**: `runs_ok 0 / 6`, `attempts_mean 2.0`, inferences **0** — no rubric
  scores exist for any cell.
- **Rationale**: Gemma 4 E2B **QAT** GGUFs ship a **shared-KV tail-layer** layout —
  541 tensors, omitting `attn_k` / `attn_v` / `attn_k_norm` for layers 15–34 (60
  tensors) — where the shipped non-QAT Q4_K_M materialises all 601. Zero tensors
  exist in the QAT file that are absent from the incumbent, so it is a structural
  difference, not corruption. The pinned llama.cpp b8694 (`mattt/llama.swift`
  `exact: "2.8694.0"`) has no shared-KV tail-layer loader. **Not vendor-specific**:
  unsloth's own QAT re-export (`unsloth/gemma-4-E2B-it-qat-GGUF` →
  `gemma-4-E2B-it-qat-UD-Q4_K_XL.gguf`, 2,620,370,976 B, sha256 `e5310072…6889`)
  carries the same 541-tensor layout (identical tensor-name set, different
  quantisation and byte length), so the split is **QAT-vs-non-QAT,
  not Google-vs-unsloth**. Confirmed by direct measurement in a throwaway
  standalone SwiftPM package with the repository's own pin untouched: llama.swift
  **2.10327.0** (llama.cpp b10327) loads the QAT file *and* the incumbent, while
  b8694 loads only the incumbent — a bump is therefore sufficient *and* the
  wrapper release exists.
- **Unblocked by**: the pinned llama.cpp gains shared-KV tail-layer support
  (`mattt/llama.swift` bumped past b8694).
- **Retry**: #1416 (Gate 1 retry), gated on #1415 (the pin spike).
- **Disposition**: **not rejected.**
  Pre-cleared for the retry, so it need not be re-derived: ADR-011 **P1**
  non-gated (HF `gated: false`; anonymous resolve 302 → CDN 200) and **P2**
  CONTROL flags (`<|turn>` id 105, `<turn|>` id 106, both `token_type=3`); EOG set
  `{1, 50, 106, 212}` is a **superset** of the incumbent's `{50, 106, 212}`, so
  `<turn|>` terminates generation on both builds and there is no runaway-generation
  risk. Worth evaluating alongside the unsloth QAT file above, which is ~0.49 GB
  *smaller* than the shipped Q4_K_M (2.62 vs 3.11 GB). **P3–P5 remain untouched**
  (Gate 2).
- **Pointers**: raw scorecard → `data/models/eval-digest.md` §2026-08-08 ·
  gemma-4-e2b-q4-k-m (gitignored, and replaced by key `(date, profile_id)` — which
  here is the *incumbent's* id, so treat it as volatile) · intake → #979 · pin
  spike → #1415 · retry → #1416 · dead `stopSequence` + false rationale comment
  surfaced during this eval → #1417.

---

## Sarashina 2.2 3B Instruct v0.1 (Q4_K_M) — 2026-07-23 — **FAIL (NO-GO)**

- **Gate**: 1 (Mac filter, `/model-eval`) — re-eval after the #751 empty-output
  blocker was fixed (PR #1024); the original 2026-07-08 run was blocked, not
  cleanly quality-rejected.
  - *Grandfathered (#1419).* That 2026-07-08 run predates the `BLOCKED` verdict
    and has **no entry of its own** — deliberately, since the retry it waited on
    already landed and is recorded right here (unblocked by the #751
    empty-output fix → PR #1024; both fields reconstructed after the fact). It is
    also why the taxonomy admits a **partial** block: 3 of its 6 cells
    hard-failed and the rest did not, so some completed — recorded in that
    direction in the `sarashina223B` doc comment in
    `tools/harness/Sources/PasturaHarnessKit/ModelProfile.swift`, the digest
    itself being gitignored. A "zero `ok` cells" precondition would therefore
    have made this very shape unrecordable.
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
