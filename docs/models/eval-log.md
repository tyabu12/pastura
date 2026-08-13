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

## Gemma 4 E2B QAT `UD-Q4_K_XL` (`unsloth/gemma-4-E2B-it-qat-GGUF`) — 2026-08-13 — **PASS (Mac filter only — advances to the ADR-011 real-device PoC, never an adoption)**

- **Gate**: 1 (Mac filter, `/model-eval`) — 6/6 cells `ok`, `attempts_mean` 1.00,
  `language_mismatch_total` 0, no crash. Run on a **bumped pin** (`llama.swift`
  2.10327.0 / llama.cpp b10327) in a throwaway worktree; `main` stays at 2.8694.0
  and no pin change came out of this eval.
- **Model**: `unsloth/gemma-4-E2B-it-qat-GGUF` · `gemma-4-E2B-it-qat-UD-Q4_K_XL.gguf`
  · Apache-2.0, non-gated · 2,620,370,976 B · sha256 `e5310072…6889` (both matching
  the HF resolve `X-Linked-Size` / `X-Linked-ETag`) — **−15.7 %** against the shipped
  Q4_K_M's 3,106,735,776 B. **Despite the name the quantisation is not K-quant**: the
  tensor spread is `Q4_0`×278 / `F32`×263 and `general.name` reads *"smart Q4_0,
  QAT-lossless"* — which is also why it has Metal kernels where the mobile sibling
  below does not. 541-tensor shared-KV layout, so **b10327+ is a hard prerequisite**.
  No Stage-0 profile of its own; a throwaway candidate profile was used so the run
  logs self-describe.
- **Differentiation**: **not a new catalog character — the question is
  REPLACE-the-build, not earn-a-new-slot.** This is the *same* Gemma 4 E2B at a
  different quantisation, so character is indistinguishable from the incumbent by
  construction; that is the point. Against a same-session control it is not merely
  non-regressive: it converts two cells where the incumbent's premise never fired
  (`prisoners_dilemma` ja collapsed to an all-cooperate five-way tie;
  `word_wolf` ja missed an explicit citrus leak) into runs where the mechanic
  engages — cross-round adaptation, whisper-as-deception, a correctly-detected wolf.
  It is **weaker than the incumbent on `bokete` in both languages**, where it
  produced self-votes the incumbent did not.
- **Snapshot** (point-in-time; raw scores in the digest): rubric **121** against a
  **same-session** incumbent control arm at **107**. The control was re-run today
  rather than compared against the recorded 2026-07-08 numbers, because cross-session
  judge drift has been measured at up to −17 points on a single model — so **do not
  compare this figure to any other dated entry.** n=1 per cell, one judge, one
  session, and the gap leans on `prisoners_dilemma` ja: its control cell was the
  outlier driving most of the margin, so that cell alone was re-sampled (11 → 18) and
  **both** samples are recorded; against the first sample the control totals 100.
  Only the control was re-sampled, which can only move the comparison in the
  incumbent's favour. Treat +14 as a screening signal, not a measured delta.
  ADR-011 **P1** (non-gated, Apache-2.0, anonymous resolve 302 → CDN 200) and **P2**
  (`<|turn>` id 105 / `<turn|>` id 106 both `token_type=3`) verified for this
  re-export; **P3–P5 untouched**.
- **Rationale**: the Mac filter cannot accept, only reject — and there is nothing
  here to reject on. Mechanical floor clean, no measured quality regression, and the
  largest download saving of any QAT build that actually runs.
- **Disposition**: **advances to the ADR-011 real-device PoC (P3–P5). This is not an
  adoption**, and two costs sit outside the −0.49 GB headline. (1) It cannot run at
  all on `main`'s pin, so adoption is gated on the #1415 bump landing first — whose
  device-only risk (Metal behaviour, the 8 GB minimum-RAM sizing in ADR-002
  § "Supported Devices", binary size) is entirely unmeasured, as is the DRY sampler
  that bump rewrites.
  (2) Swapping a build is not an in-place update: per `ModelRegistry`'s supersede
  convention it means a new `id` **and** `fileName` with the old entry removed, so
  **existing users re-download 2.62 GB** and the superseded 3.11 GB file becomes an
  orphan they must delete by hand (ADR-015 / #548) — the saving accrues to *new*
  installs. The retired id must move into `RETIRED_MODEL_IDS` in
  `scripts/gallery_highlight_validate.py` in the same PR (ADR-029).
- **Pointers**: raw scorecard → `data/models/eval-digest.md` §2026-08-13 ·
  `gemma-4-e2b-qat-q4-k-xl`, with the control arm under `gemma-4-e2b-q4-k-m` of the
  same date (gitignored, per-machine — the **durable** backing is the issue comment
  next) · full derivation → [#1416 comment][eval-20260813] · pin-bump implications →
  [#1415 comment][eval-20260812] · intake → #979.

[eval-20260813]: https://github.com/tyabu12/pastura/issues/1416#issuecomment-5275995869
[eval-20260812]: https://github.com/tyabu12/pastura/issues/1415#issuecomment-5275999544

---

## Gemma 4 E2B QAT Mobile `UD-Q2_K_XL` (`unsloth/gemma-4-E2B-it-qat-mobile-GGUF`) — 2026-08-13 — **BLOCKED (backend kernel coverage — not evaluated, therefore not rejected)**

- **Gate**: 1 (Mac filter, `/model-eval`) — **crashed on the first inference, so no
  quality judgment exists.** Exactly **one** cell was run (`word_wolf` ja); the
  remaining five were **not attempted**, because the cause is scenario-independent.
  Read the snapshot as 0 ok / 1 run, **not** 0 / 6.
- **Model**: `unsloth/gemma-4-E2B-it-qat-mobile-GGUF` ·
  `gemma-4-E2B-it-qat-UD-Q2_K_XL.gguf` · Apache-2.0, non-gated · 2,186,186,784 B ·
  sha256 `0a5bbc20…da28` (both matching the HF `X-Linked-Size` / `X-Linked-ETag`) —
  **−29.6 %** against the shipped Q4_K_M, the largest saving anywhere in this family.
  A GGUF conversion of Google's [QAT Mobile][qat-mobile] line, which publishes no
  GGUF itself; its `wNa8o8` scheme reads concretely from the header as `TQ2_0`×61 /
  `Q8_0`×70 / `Q4_0`×146 / `F32`×263.
- **Differentiation**: **UNASSESSABLE** — zero inferences completed, so the
  2-bit-decoder-layer quality question is *untested*, not answered.
- **Snapshot**: 1 cell run, 0 `ok`, **0 inferences**; no rubric scores exist. The
  process died with `SIGSEGV` (exit 139) *after* a clean model load — `run_start`
  emitted and the `assign` phase completed, so the 2026-08-08 shared-KV loader
  blocker **is** cleared by b10327. ADR-011 **P1** and **P2** both **PASS** for this
  re-export (`<|turn>` id 105 / `<turn|>` id 106 are both `token_type=3 (CONTROL)`,
  identical to the incumbent — the unsloth #5070 NORMAL-flag trap is *not* present
  here), so a retry need not re-derive them.
- **Rationale**: a **second, deeper** gap sits behind the shared-KV one, and it is
  not the same kind of problem. llama.cpp's Metal backend ships **no kernels at all**
  for the `TQ` (ternary) family, so the pipeline lookup returns NULL and
  `ggml_metal_encoder_set_pipeline` dereferences it:
  `"Function kernel_mul_mm_tq2_0_f32 was not found in the library"`
  (`MTLLibraryErrorDomain` Code=5) → `EXC_BAD_ACCESS address=0x0`. Confirmed by
  grepping the shipped framework binary **with a known-present kernel as positive
  control** — `kernel_mul_mm_q4_0` / `q8_0` / `q4_K` all resolve, every `tq1_0` /
  `tq2_0` kernel is absent (`tq2_0` survives only as a block-struct name).
  **Unlike the loader gap, this one is not pin-relative**: it is equally absent at
  b10375, ~48 builds newer. Upstream also appears not to reflect the missing kernel
  in its op-support check, so it crashes rather than falling back to CPU.
- **Unblocked by**: llama.cpp's Metal backend gaining `TQ2_0` kernels — at minimum
  `kernel_mul_mm_tq2_0_f32` — **and** a `llama.swift` release at that build. Stated
  as text deliberately, so the gate survives the retry issue being renamed or closed.
  Cheap re-check before downloading anything: grep the release xcframework binary for
  `tq2_0` kernel names, keeping a known-present kernel in the same grep as a control.
- **Retry**: #1416.
- **Disposition**: **not rejected.** At −29.6 % it remains the largest download
  saving in the family and is worth re-testing if that upstream gap closes.
- **Pointers**: raw scorecard → `data/models/eval-digest.md` §2026-08-13 ·
  `gemma-4-e2b-qat-mobile-q2-k-xl` (gitignored, per-machine) · full derivation,
  including the lldb trace and the kernel sweep →
  [#1416 comment][eval-20260813] · intake → #979.

[qat-mobile]: https://huggingface.co/collections/google/gemma-4-qat-mobile

---

## Gemma 4 E2B QAT Q4_0 (`google/gemma-4-E2B-it-qat-q4_0-gguf`) — 2026-08-12 — **FAIL (NO-GO)**

- **Gate**: 1 (Mac filter, `/model-eval`) — the retry the 2026-08-08 **BLOCKED**
  entry below was waiting on. Run inside the #1415 pin spike on `llama.swift`
  2.10327.0 (b10327), which unblocked the load; all 6 cells then completed.
- **Model**: as recorded in the 2026-08-08 entry below (`gemma-4-E2B_q4_0-it.gguf`,
  3,349,516,256 B, sha256 `fa401b55…6634`) — unchanged file, so its P1 / P2 / EOG
  pre-clearances carry over.
- **Differentiation**: earns no slot. Its two weak cells are **substantive, not
  stylistic** — `word_wolf` ja states the secret word outright and produces two
  self-votes; `word_wolf` en collapses into four agents echoing one sentence. It
  beats the incumbent on `prisoners_dilemma` ja only because that particular
  incumbent run drifted into Korean.
- **Snapshot** (point-in-time): rubric **103** against **113** for the incumbent on
  the *same* pin. ⚠️ **Neither number is in the digest.** The spike deliberately did
  not run `append_eval.py` — its `(date, profile_id)` section key carries no pin or
  GGUF dimension, so the incumbent and the candidate (same family, same day) would
  have overwritten each other. The durable record is the #1415 comment below.
  ⚠️ **Not comparable to the 2026-08-13 entries above** (121 / 107): those were
  scored in a different session, and this pair's own incumbent leg (113) sits 6
  points above the 2026-08-13 control (107) on the *same build* — which is the
  cross-session judge drift both sessions took a control arm to defend against.
- **Rationale**: the motivating upside is now measured and it is negative — **−10
  against the incumbent on the same pin**, while the file is **+7.8 % larger**
  (3.35 vs 3.11 GB), the wrong direction for the ADR-011 6 GB tier. Nothing here
  earns a catalog slot, and it supplies no reason to bump the pin.
- **Disposition**: does **not** advance to the ADR-011 real-device PoC. The QAT
  *family* is not rejected by this: it is a fact about the `Q4_0` build only, and the
  two unsloth re-exports were evaluated separately above.
- **Pointers**: spike result, with the full method and the same-session control arms
  → [#1415 comment][eval-20260812] · pin spike → #1415 · intake → #979.

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
- **Retry**: **ran, and is recorded as the 2026-08-12 entry above** — the unblock
  condition was met inside the #1415 spike and the candidate scored a clean NO-GO.
  This entry stays a `BLOCKED` record of 2026-08-08 rather than being relabelled: on
  that date zero inferences ran, so a rejection cannot be dated to it.
- **Disposition**: **not rejected.**
  Pre-cleared for the retry, so it need not be re-derived: ADR-011 **P1**
  non-gated (HF `gated: false`; anonymous resolve 302 → CDN 200) and **P2**
  CONTROL flags (`<|turn>` id 105, `<turn|>` id 106, both `token_type=3`); EOG set
  `{1, 50, 106, 212}` is a **superset** of the incumbent's `{50, 106, 212}`, so
  `<turn|>` terminates generation on both builds and there is no runaway-generation
  risk. The two unsloth QAT re-exports this entry flagged as worth evaluating
  alongside have since been measured — both carry their own 2026-08-13 entries above.
  **P3–P5 remain untouched** (Gate 2).
- **Pointers**: raw scorecard → `data/models/eval-digest.md` §2026-08-08 ·
  gemma-4-e2b-q4-k-m (gitignored, and replaced by key `(date, profile_id)` — which
  here is the *incumbent's* id, so treat it as volatile) · intake → #979 · pin
  spike → #1415 · retry outcome → the 2026-08-12 entry above · dead `stopSequence` +
  false rationale comment surfaced during this eval → #1417.

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
