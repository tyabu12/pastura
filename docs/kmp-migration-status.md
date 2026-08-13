# KMP Engine Migration — Status Board

At-a-glance progress for the KMP Engine migration (ADR-023 / [#501](https://github.com/tyabu12/pastura/issues/501)).

> **This board is a progress view — nothing more. Its two sources of truth:**
>
> | For | Read |
> |---|---|
> | *Why* — architecture, boundary contracts, the GO/NO-GO decision | [ADR-023](decisions/ADR-023.md) (design authority) |
> | *What / how* — per-stage execution detail, per-PR records, the §12 GO conditions | [#501](https://github.com/tyabu12/pastura/issues/501) (execution detail) |
> | *Where we are* — one-glance progress | **this file** |
>
> **Maintenance invariant (binding).** Every row carries **status + PR# + a pointer only**. Never
> restate ADR-023 §12's GO conditions, #501's scope, or any rationale here — that content lives in
> the two sources above, and mirroring it turns this into a 4th, drifting source. Keep each
> "what's left" cell to a phrase-length progress note, not a scope/rationale sentence. This is what
> keeps every update a one-line diff.
>
> **The Wave B handler checklist is machine-checked** by `scripts/check-kmp-status.py` (pre-commit +
> CI): a `[x]` that has no ported `.kt`, a ported `.kt` with no `[x]`, or a handler-set mismatch
> against the ADR-023 port ledger fails the build — so that section cannot silently drift. Every
> other section is hand-maintained; refresh it when a KMP PR merges (see
> [`.claude/rules/kmp-interop.md`](../.claude/rules/kmp-interop.md)).

_Last updated: 2026-08-13._

## Stages

| Stage | What | Status | Key PRs / pointer |
|:--:|---|:--:|---|
| 0 | Pre-port refactors on `main` | ✅ done | #990 #991 #1051 #1000 |
| 1 | `shared/models` + CI infrastructure | ✅ done | #1052 #1055 #1059 |
| 2 | Two-boundary vertical slice = GO/NO-GO gate | ✅ **GO** (2026-07-18) | #1063 #1137 #1172 · [ADR-023 §12](decisions/ADR-023.md) |
| 3 | Bulk port to `commonMain` | 🔄 in progress | ↓ Stage 3 breakdown |
| 4 | Cross-language parity harness | 🔄 in progress | slice 1a landed ([#1387](https://github.com/tyabu12/pastura/issues/1387), closed); 1b next · [#501](https://github.com/tyabu12/pastura/issues/501) |
| 5 | iOS consumption switch + code-merge | ⬜ not started | the remaining integration · when writing the Swift `LLMBackend` adapter, confirm whether `knownTurnMarkers`' Kotlin interface default crosses K/N — by compiling the adapter, since a `PasturaShared.h` read alone does not settle it (see that member's KDoc) |

Legend: ✅ done · 🔄 in progress · 🟡 partial · ⬜ not started.

## Stage 3 — bulk port (in progress)

| Slice | Status | Pointer |
|---|:--:|---|
| Models mirror | ✅ done | #1193 #1196 #1202 |
| Wave A — non-handler run-path (scoring, mechanisms, prompt/LLM glue) | ✅ done | #1207 #1212 #1217 |
| Wave B — 14 phase handlers | ✅ 14/14 | checklist ↓ |
| code-phase track | ✅ done | CP1 #1226 · CP2 #1230 · CP3 #1232 |
| Loader / validator port + `detector`·`logger` wiring | ⬜ not started | remaining Stage-3 units, not the full list · [ADR-023](decisions/ADR-023.md) §4 · #501 |

### Wave B handler checklist

A handler is `[x]` when its port exists at
`shared/engine/src/commonMain/kotlin/com/pastura/engine/Phases/<Name>.kt`. This section is
machine-checked — see the maintenance invariant above.

<!-- kmp-status:wave-b:start -->
- [x] AssignHandler — #1226
- [x] EliminateHandler — #1226
- [x] SpeakAllHandler — #1222
- [x] SummarizeHandler — #1226
- [x] ChooseHandler — #1262
- [x] ConditionalHandler — #1342
- [x] EventInjectHandler — #1230
- [x] NarrateHandler — #1330
- [x] ReflectHandler — #1242
- [x] RelationshipUpdateHandler — #1232
- [x] ScoreCalcHandler — #1230
- [x] SpeakEachHandler — #1307
- [x] VoteHandler — #1249
- [x] WhisperHandler — #1252
<!-- kmp-status:wave-b:end -->

## Stages 4–5 — remaining integration

- **Stage 4** (parity harness): 🔄 in progress — slice 1a landed; 1b next; no parity rung live yet.
  See [ADR-023](decisions/ADR-023.md) §6 Stage 4,
  [#1387](https://github.com/tyabu12/pastura/issues/1387) (slice 1a, closed) and
  [#501](https://github.com/tyabu12/pastura/issues/501) (remaining Stage-4 work).
  ⚠️ The divergent fixture's negative control now drives a **value** divergence only:
  ADR-021 § Amendment 2026-08-06 resolved `SCHEMA_GUARD_POSITION` (both engines skip a turn
  whose declared canonical primary is empty), and none of the three *currently-ledgered*
  structural classes is reachable from a scripted fixture (see `ParityFixtureEmitter`'s
  `purpose` for the per-class reason). That is an enumeration over today's `DivergenceClass`
  cases, **not** a proof that no structural arm exists: an unledgered one does. Swift's
  schema-guarded salvage (#907) accepts a multi-object response
  (`{"statement": "hello", "inner_thought": "thinking"}{"stray": 1}`) that Kotlin's `extractFirstJsonObject`
  refuses, yielding Swift `agent_output` vs Kotlin `turn_skipped` — the same structural shape
  that was just lost. The asymmetry is pinned by paired parser tests in both languages; adding
  the `DivergenceClass` case and the fixture arm is deliberately deferred, because a case with
  no entry is the "pre-approved licence" `DivergenceLedger` warns about, and nothing consumes
  `ParityGolden` yet to verify the arm end-to-end.
  ⚠️ The guard that would have caught this loss is **kind-coverage** — an assertion that the
  divergent fixture drives ≥1 `Structural` *and* ≥1 `Value` entry. Not the unfired-entry
  assertion, and not the "every case is cited" test `DivergenceLedger` already prescribes: the
  case and its entry were deleted *together*, so both stay green. Re-arming and the
  kind-coverage guard are tracked on
  [#501](https://github.com/tyabu12/pastura/issues/501) (#1387 is closed).
- **Stage 5** (iOS switch + code-merge): ⬜ not started — the remaining iOS integration. See
  [ADR-023](decisions/ADR-023.md) §6 Stage 5.
