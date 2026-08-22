---
paths:
  - "Pastura/Pastura/Engine/**"
  - "Pastura/Pastura/LLM/**"
---

# Engine Design Rules

## Adding a new `PhaseType`

Most touch points are no-default exhaustive `switch`es and the build catches an
omission. Four do not.

- **Kotlin enum mirror.** `InferenceEstimator.kt`'s `when` is `else`-free but
  breaks only once `shared/models/.../PhaseType.kt` gains the case, and no gate
  ties the two enums together (the ADR-023 ledger covers `Engine/**` + `LLM/**`
  only). Add the Swift case alone and the Kotlin lane stays green while the enums
  diverge.
- **Conditional-branch policy.** `ScenarioValidator.validateBranch` and
  `ConditionalHandler.subHandlers` are not `PhaseType`-exhaustive, so decide
  explicitly: *allow* (register in `subHandlers`) or *reject* (a
  `validateBranch` throw plus a `ScenarioValidationMessage` case). Skip both and
  a branch-nested use passes every load gate, then throws mid-run at dispatch.
  Mirror the verdict into the two Kotlin maps, which no validator covers
  (`.claude/rules/kmp-interop.md` Pattern 4).
- **Empty-primary skip reachability.** A new **LLM** phase must either route its
  `LLMCaller.call` through `turnGate.attempt`, or return `nil` from
  `ScenarioConventions.primaryField(for:)` — otherwise `retriesExhausted` reaches
  a call site the gate does not own, aborting the run if that site does not catch
  and silently swallowing the turn if it does.
- **`mood` capture.** Every LLM handler calls `promptBuilder.captureMood` by hand;
  a new handler that omits it compiles and the agent's `mood` silently stops
  carrying into its next prompt (`Engine/PromptBuilder+Injection.swift`).

Reference: `Engine/Phases/ConditionalHandler.swift`.

## Parse vs validate boundary

`ScenarioLoader.load(yaml:)` runs no limit or semantic checks, only structural
mapping and construct-time invariants, so a **new** YAML-ingest path must call the
gate itself: persist → `validateForCommit(_:)`, run → `validate(_:)`, re-parse
already-persisted YAML → nothing (the gate ran upstream at create time). New
semantic DSL rules go in `ScenarioSemanticLinter`, not
`Engine/ScenarioValidator.swift`.

## Phase-ordering silent no-ops

Both run and produce output; the lint layer only warns.

- **`relationship_update` placement** — after the vote/choose phase producing its
  signals, **before `score_calc`** (`PrisonersDilemmaLogic` clears
  `state.pairings`). A `lastOutputs`-writing LLM phase in between loses the vote
  signal; `reflect`/`whisper` interleave safely.
- **`log_window: N`** — the window truncates the same log the speak_each address
  rule reads, so keep N ≥ agentCount for accumulating scenarios or same-round
  earlier speakers vanish from the addressee pool.

Reference: `Engine/ScenarioSemanticLinter+Ordering.swift` (R4), `+Config.swift` (R17).

## Read the event's own `phaseType`, not `currentPhaseType`

`SimulationViewModel.currentPhaseType` is set from `.phaseStarted`, so a nested
`.phaseStarted` shadows it with the inner phase type; a consumer needing exact
attribution must read the event's own `phaseType` or mis-attribute silently.
Reference: `App/SimulationViewModel.swift`.

## Consumer-scoped resolver naming

When a `Scenario` value is resolved differently per consumer, name the resolver
after **its consumer** — `engineLanguage`, not a generic `effectiveLanguage`,
which invites a later "consolidation" routing other consumers through it and
silently bypassing their priority. Reference: `Models/Scenario.swift` (the consumer table in `engineLanguage`'s doc comment — extend it when adding a consumer).

## A change here may owe a Kotlin twin — read the ledger row first

`shared/adr-023-port-ledger.tsv` carries one row per file in these two
directories. A `REPLACED`, `FOLDED`, or `SPLIT` row names the Kotlin file(s)
or design the same change must also land in (ADR-023 §4, §13); a `PORT` row
whose same-named `.kt` already exists under `shared/engine` is paired by name.
Only `SPLIT` targets are machine-verified, and only for existence — no gate
checks that your edit reached them. `.claude/rules/kmp-interop.md` is `shared/**`-scoped and does not load
for an edit here — this section is the reminder on this side.

## Prompt literals are paired with the Kotlin port

`scripts/check-prompt-literal-parity.py` owns the mechanics and prints its own
reason. A wording change is a *behaviour* change: give its harness A/B a
**deleted-text control arm**, or "the two wordings tie" cannot be told apart from
"this text does nothing".

## Conforming to a K/N-exported protocol from `LLM/`

A Stage-5 adapter (ADR-023 §6) wrapping `LlamaCppService` as an `LLMBackend` conformer hits
one trap with no diagnostic: the protocol imports unannotated (per the KDoc, unprobed), so the
conforming type must be `nonisolated` or the `@objc` thunk traps at runtime —
`.claude/rules/swift-isolation.md` Pattern 7, K/N instance. The rest of the K/N boundary (every
Kotlin-defaulted member lands `@required`, so `knownTurnMarkers` must be stated; no Swift
`Sendable` on exports) is `.claude/rules/kmp-interop.md`, which loads for `shared/**` and
`tools/kmp-gate-spike/**` only — read it before writing the adapter. Reference: the KDoc on
`knownTurnMarkers` in `shared/engine/src/commonMain/kotlin/com/pastura/engine/LLMBackend.kt`.

## SimulationEvent & the projection contract

Every production `switch` over `SimulationEvent`, `PhaseType`, or
`CodePhaseEventPayload` must be no-default exhaustive. No gate bans `default:`,
so such an arm silently swallows a new case.

- **No `default:`** — an ignored case gets its own listed arm with a why-comment,
  so a new case lands in *no* arm (`ReplayViewModel.apply`).
- **Tiered switches are allowed iff the terminal tier is no-default exhaustive**
  — earlier tiers may `default:` forward (`EventLineMapper`).
- **No raw-string switching over phase/event kinds** — parse
  `PhaseType(rawValue:)` first (`ScenarioSignaturePhase.init?(phaseRawValue:)`).

Reference: `docs/decisions/ADR-022.md` § D2.

## llama.cpp Backend Traps

The first four share one crash signature (`Unexpected empty grammar stack` →
SIGABRT) with **different root causes and different fixes** — diagnose before
fixing. The fifth is a GGML-level abort; the last two never crash.

### Grammar sampler does not mask special tokens

`llama_sampler_init_grammar` does not exclude special tokens from its mask, so a
thinking-mode model emitting a leading `<think>` crashes
`llama_grammar_accept_token`, uncaught at the Swift boundary. Fix: prefill the
assistant turn via `ModelDescriptor.assistantPrefix`; GBNF think-block rules,
`/no_think` hints, and chain filtering were tried and rejected. When adding a
model, check whether its chat template emits a special token before the response
by default — if so it needs a closed-form `assistantPrefix` or no grammar. Reference: `App/ModelRegistry.swift`.

### GGUF source *and variant* matter

unsloth's Gemma 3 GGUF exports flag `<start_of_turn>` / `<end_of_turn>` as NORMAL
instead of CONTROL, so llama.cpp BPE-splits the chat markers and the model's
garbage first token trips the grammar. **Same crash signature as above, different
fix**: switch GGUF source (`ggml-org/*-GGUF` or bartowski for Gemma 3 — the shipped Gemma 4 E2B unsloth export is unaffected, so do not swap its descriptor);
`assistantPrefix` does not help. It is also the systematic route by which a turn
marker reaches decoded text, so `JSONResponseParser+Truncate.swift` is live, not
dead code — its shipped-model zero measures the files, not the models.

**Variant, not just publisher.** Gemma 4 **QAT** exports ship a shared-KV tail
layer older llama.cpp builds cannot load (`missing tensor
'blk.15.attn_k.weight'`), so a `-qat-` repo is never a drop-in swap for its
non-QAT sibling. That is a **loader** gap and pin-relative; **quant kernel
coverage is not** — a build whose tensors use a type the Metal backend has no
kernel for **loads cleanly, then SIGSEGVs on the first inference**. Never read a
pin bump as unblocking a variant family: before pulling a GGUF on an unshipped
quant, grep the release xcframework for that quant's kernel names **with a
known-present kernel in the same grep as a positive control**, or a pattern
matching nothing looks identical to a real absence. Reference:
`docs/models/onboarding.md`.

### Raw `llama_sampler_accept` with prompt tokens corrupts grammar state

`llama_sampler_accept` propagates to every chain component including the grammar,
and prompt tokens (`<bos>`, chat markers, plain text) do not match the GBNF
`root` rule — every accept throws, the stack empties, and the next
`llama_sampler_sample` hits `GGML_ASSERT(!stacks.empty())` → SIGABRT
mid-generation. **A C++ catcher does NOT save you**: the catches succeed during
prefill, the assertion fires later in `apply_impl`, and POSIX signals do not
cross try/catch. So the grammar stays **outside** the chain and is accepted on
non-EOG tokens only — moving it back into the chain silently reopens both the
empty-output and the SIGABRT failure.
Reference: `LLM/LlamaCppService+GrammarSample.swift`.

### Grammar must not enumerate values — structure only

`GBNFGrammarBuilder` constrains JSON **structure** (object shape, keys, the shared
`string` production) but MUST NOT emit value enumerations: CJK / multi-byte /
dynamic literals crash the sampler at accept-time, and the trigger is the model's
BPE tokenizer — a char-class guard passing for Gemma 4 E2B is unverified for the
next model. Constrain closed-set values at **runtime** instead:
`ChooseHandler.validateAction` drops the pairing and emits `.actionRejected`,
`VoteHandler` drops the tally, `OutputSchema.Kind.choice` stays payload-free. Reference: `LLM/GBNFGrammarBuilder.swift`.

### iOS Simulator cannot run quantized inference

Simulator Metal reports `MTL0 ... 0 MiB free`; weight tensors fail to buffer and
the CPU fallback hits `GGML_ASSERT` → SIGABRT. That is a GGML-level abort, **a
distinct crash class from the grammar paths above**, and SafeSampler cannot catch
it: load-only integration tests pass while anything calling `generate` dies.
Verify inference on a real device.
Reference: `LLM/LlamaCppService.swift`.

### Errors split between the log callback and raw stderr

A prebuilt C/C++ library can split error reporting across the log-callback API
(`llama_log_set`) and direct `fprintf(stderr, …)` writes that bypass it, and iOS
`os_log` does not capture process stderr — llama.cpp logs a generic parse failure
while the actionable detail (`"expecting ']'"`) is lost. On a new
C-API integration, grep the library source for BOTH `*_LOG_*` macros AND
`fprintf(stderr, …)` on error paths before the first commit, and scaffold a
narrow `dup2`-based capture if any exist. Reuse `initGrammarCapturingStderr`: the
`Pipe()` drain order is load-bearing and `defer` does NOT work there. Reference: `LLM/LlamaCppService+Sampler.swift`.

### The chain's `penalties` cannot reach across a `generate()`

A sampler's history is **per-sampler-object** and `createSampler` allocates a
fresh chain on every `generate()`, so the `penalties` buffer starts empty each
call: load-bearing **within** a generation (do not remove it), blind **across**
them however high `repeatPenalty` / `penalty_last_n` go. Silent — no crash, no
diagnostic; the knob simply moves nothing. Name the scope any repetition fix
targets:

1. **Within one generation** — the chain's `penalties`, and only its last
   `penalty_last_n` tokens. Not total even here.
2. **An agent's own prior turns, `speak_each` only** — the DRY sampler seed.
3. **Anything else** (cross-agent collapse, any other phase) — unreached; it
   needs a new seeder, not a knob.

Reference: `LLM/LlamaCppService+DrySampler.swift`.
