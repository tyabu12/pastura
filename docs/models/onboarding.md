# Model Onboarding

The committed procedure for onboarding a new GGUF model candidate into the
Pastura catalog (`ModelRegistry`). It is **pointer-heavy by design**: each stage
names its canonical source and defers the mechanism to it. On any conflict, the
pointed-to source wins over this page — treat the citations, not this summary,
as authoritative.

`docs/models/` (this file) is the committed process. It is distinct from
`data/models/` — the `/model-eval` skill's **gitignored** eval artifacts
(`eval-runs/` raw logs, `eval-digest.md` scorecard journal), which are local,
never committed, and never reach users.

## End-to-end flow

```
Stage 0  harness ModelProfile PR (new family only)
   │
Gate 1   /model-eval  — cheap Mac filter (足切り)
   │        ├─ reject ──▶ record candidate + failure mode (stop)
   │        ├─ borderline ──▶ re-sample weak cell(s), re-judge (never reject on one sample)
   │        └─ blocked ──▶ record blocker + retry pointer ──┐  (NOT a stop)
   │                                                        │
   │               ◀── retry when the blocker clears ───────┘
   │        (pass = ADVANCE only; it cannot accept)
   ▼
Gate 2   ADR-011 real-device PoC — the ONLY accept path
   │        ├─ no-go ──▶ record candidate + failure mode (stop)
   │        └─ blocked ──▶ record blocker + retry pointer ──┐  (NOT a stop)
   │                                                        │
   │               ◀── retry when the blocker clears ───────┘
   ▼
Registration  (/orchestrate: descriptor + mirrors + device QA)
```

Gate 1 can **reject** cheaply, return **borderline** (→ re-sample per the
skill's asymmetric verdict — one unlucky single-run sample must never discard a
candidate), or return **blocked**. Gate 2 is the sole gate that can **accept**.

**`blocked` is not a rejection** — it means the candidate could not be
*evaluated* (a model-load failure, a runtime incompatibility, a known infra
path), so there is nothing to reject and the outcome is retry-gated. Both gates
can produce it; a blocked entry must always name **what would unblock it** and
**where the retry is tracked**.

The two gates enforce that asymmetrically, and the asymmetry is deliberate:

- **Gate 1** is machine-checked, but only structurally. `/model-eval`'s
  `append_eval.py` rejects a `blocked` scorecard that lacks an unblock
  condition or a retry pointer; it refuses a `differentiation` judgment when no
  cell completed, and conversely *requires* one — scoped to the completed
  cells, or an explicit "insufficient to differentiate" — when at least one
  did. Admissibility itself (is the failure environmental or the candidate's
  own?) is **not** checked by anything and stays a human call — see
  `.claude/skills/model-eval/SKILL.md`
  § "`blocked` — admissibility and its two enforcement layers", which also
  explains why a mechanical proxy was rejected.
- **Gate 2** is **convention-only**. There is no machine-readable Gate-2
  artifact, so nothing validates a real-device blocked outcome; record it in
  [`eval-log.md`](eval-log.md) with the same two fields by hand.

## Stage 0 — Harness profile (new model family only)

A candidate from a family not already in `ModelProfile.all` (today: `gemma` /
`qwen`) needs a prior `tools/harness` PR — landed through `/orchestrate` — adding
a `ModelProfile` static plus its pin test. The profile mirrors **8** load-bearing
registry values under its own field names (`id`, `name`, `stopSequence`,
`turnMarkers`, `systemPromptSuffix`, `assistantPrefix`, `expectedFileName`,
`expectedSHA256`; `name` / `expectedFileName` / `expectedSHA256` map to the
registry's `displayName` / `fileName` / `sha256`); `ModelProfileTests`
pins them against the future/planned `ModelRegistry` values so the harness and
app never drift.

**`turnMarkers` is collected, not copied.** Read the candidate's own turn-start /
turn-end strings out of the GGUF header (they are tokenizer-specific and share no
convention across families — Gemma 4's `<|turn>` / `<turn|>` vs ChatML's
`<|im_start|>` / `<|im_end|>`), and record their `token_type` alongside. Then
**re-run the marker sweep over the accumulated transcripts** rather than carrying
forward the last recorded numbers:

Run from **the primary checkout, not an `/orchestrate` worktree** —
`data/models/eval-runs/` is gitignored, so it exists only where the harness ran,
and the path below is relative to that checkout's root.

**There are two ways to record a false zero here, and the loop guards against
both:**

- **A placeholder left in.** Replace the two `<candidate …>` operands with the
  candidate's actual marker strings first; left as-is the loop counts the
  literal text and reports `0`.
- **A missing corpus.** `grep -r` over an absent directory writes to stderr and
  the pipeline still prints `0` for every marker — indistinguishable from a real
  negative. Hence the precondition on the first line.

Both produce the exact failure this paragraph exists to warn about, so treat a
row of zeros as suspect until the precondition has passed.

```sh
[ -d data/models/eval-runs ] || { echo 'corpus absent — use the primary checkout' >&2; exit 1; }
for m in '<|im_end|>' '<|im_start|>' '<|turn>' '<turn|>' \
         '<candidate turn-start>' '<candidate turn-end>'; do
  printf '%s\t' "$m"; grep -rhoF "$m" --include='*.jsonl' data/models/eval-runs/ | wc -l
done
```

Append the result to [`eval-log.md`](eval-log.md) § "Spelled-out chat-template
markers" with the date and scope. Two things make the re-run load-bearing rather
than ceremonial: a spelled-out marker is a property of the **GGUF export** (a
re-export can mis-flag a CONTROL marker as NORMAL, and then it decodes into
text — unslothai/unsloth#5070), so a negative taken on one file says nothing
about the next; and the sweep is only meaningful against transcripts that
**exist**, so note which models the corpus actually covers before reading a zero
as evidence. Both fields feed the same silent-failure mode: a wrong pair makes
the truncation and leakage mechanisms inert with nothing to observe (#1422).

Budget **one** investigation round per new family for prompt-template traps.
llama.cpp's `llama_chat_apply_template` reads the GGUF-embedded chat template, so
no per-model Swift formatting code is ever needed — only the hook values
(`systemPromptSuffix` / `assistantPrefix`). Case study: Qwen (#366) needed the
`<think>\n\n</think>\n\n` assistant prefill because a thinking-mode model emits a
leading `<think>` that crashes the GBNF grammar sampler; the `/no_think` suffix
alone is only a soft hint. The mechanism's source of truth is
`.claude/rules/engine.md` § "Grammar sampler does not mask special tokens" — do
not re-derive it here.

## Gate 1 — Mac filter (`/model-eval`)

Run `/model-eval <gguf-path> <profile-id>`. The skill's SKILL.md § "Positioning"
is canonical; it defines the gate. Key properties only:

- It can **REJECT** an unfit candidate cheaply, but **cannot accept** — a pass
  only *advances* to Gate 2. A Mac pass must never be reported as "adopted".
- **Borderline** (one weak/failed cell) → re-sample the weak cell(s), never
  reject on a single unlucky run (asymmetric, variance-aware verdict).
- There is **no** tok/s or rubric-total pass number by design (mechanism
  contract, not a pinned threshold).

Metadata note: the two integrity fields you will later pin (`sha256`,
`fileSize`) come authoritatively from `curl -sIL` on the HF resolve URL — the
`X-Linked-Size` / `X-Linked-ETag` headers — with no on-device PoC needed for
those two values.

## Gate 2 — Real-device accept (ADR-011)

Clear **all five** prerequisites in
`docs/decisions/ADR-011.md` § Decision, item 2 ("Hard prerequisites for any
future 6 GB tier candidate"). That list is the source of truth and is
**deliberately not restated here** — it is a mechanism contract that will be
edited when the backend changes (e.g. LiteRT-LM). One-line gloss of what the five
cover: non-gated GGUF source; correct CONTROL token-type flags; on-device GBNF
PoC on ≥ 2 presets; no regression on the existing catalog; no raw prompt-token
sampler-accept on a grammar chain.

This is the **only** accept path. Echoing the skill: a Mac-filter pass must never
be reported as adopted — adoption happens here, on real-device PoC, or not at
all.

## Registration checklist (after Gate 2 — via `/orchestrate`)

Add a `ModelDescriptor` to `ModelRegistry.catalog`. Field map, read from the
init in `Pastura/Pastura/App/ModelRegistry.swift`:

| Field | Notes |
|---|---|
| `id` | Stable catalog id; also the `--profile` / `ModelProfile.id`. |
| `displayName` / `shortDisplayName` | Full + compact labels. |
| `vendor` / `vendorURL` | Publisher name + site. |
| `downloadURL` | **Pins a specific HF commit SHA** (`resolve/<commit>/...`), not `main`. A `-qat-` repo is **not** a drop-in swap for its non-QAT sibling — see `.claude/rules/engine.md` § "GGUF source *and variant* matter". |
| `fileName` | GGUF filename; unique across the catalog. |
| `fileSize` / `sha256` | From `curl -sIL` `X-Linked-Size` / `X-Linked-ETag` (Gate 1 note). |
| `stopSequence` | Prompt-format field — must match the Stage-0 profile. |
| `minRAM` | Device RAM floor. |
| `modelInfoURL` | HF model card. |
| `systemPromptSuffix` | Prompt-format field — must match the profile (`nil` for none). |
| `assistantPrefix` | Prompt-format field — Qwen-only today (thinking-mode prefill); omit if unused. |
| `tagline` | **One** `String(localized:)` literal (not two source strings); its `ja` translation lands in `Localizable.xcstrings`. |

Then, in the same `/orchestrate` run:

- **Prompt-format handoff.** The three format fields (`stopSequence`,
  `systemPromptSuffix`, `assistantPrefix`) must agree with the Stage-0
  `ModelProfile`; the pin test enforces the harness side.
- **`LicenseCatalog` entry** — add the model's license block
  (`Pastura/Pastura/Views/Settings/LicenseCatalog.swift`).
- **README mirror** — update "Supported LLM models" per CLAUDE.md § Reference
  Documents (Bundled models (`ModelRegistry.swift`) → README "Supported LLM
  models").
- **Real-device QA** — confirm inference on a real device (Metal and
  memory-pressure behavior is not reproduced by the Mac harness or the
  simulator — the reason Gate 2 exists at all, per ADR-011).

## Curation policy

The catalog stays curated at **3–5 models**. A slot is earned by **distinct
character** (input: the `/model-eval` scorecard's `differentiation` field), not
by a marginally higher score — a model that merely duplicates an incumbent's
character earns no slot even with decent numbers. Each model also costs
~2.5–3.1 GB on device, so the ceiling is a real cost, not a style preference.

## Recording outcomes

- **Pass (through Gate 2)** → the registration PR above.
- **Blocked (either gate)** → record the blocker + the unblock condition + the
  retry pointer, on the same three surfaces below. The candidate stays live;
  do **not** write it up as a rejection.
- **No-go / reject (either gate)** → record the verdict + failure mode. Three
  committed surfaces, by role:
  - **[`eval-log.md`](eval-log.md)** — the durable verdict ledger; the home for
    every candidate **except** the 6 GB-tier/1B-class ones ADR-011 tracks
    (e.g. a full-tier 3B like Sarashina). Judgment only — raw scores stay in the
    gitignored `data/models/eval-digest.md`.
  - **ADR-011 § "Alternatives considered"** (Candidate A–F table) — the home for
    the **6 GB-tier/1B-class** candidates it tracks; amend its table in the same
    `/orchestrate` PR when the candidate is one of those.
  - **issue #979** — the rolling intake queue; drop a comment there either way.
