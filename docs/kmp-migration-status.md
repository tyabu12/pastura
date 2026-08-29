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

_Last updated: 2026-08-29._

## Stages

| Stage | What | Status | Key PRs / pointer |
|:--:|---|:--:|---|
| 0 | Pre-port refactors on `main` | ✅ done | #990 #991 #1051 #1000 |
| 1 | `shared/models` + CI infrastructure | ✅ done | #1052 #1055 #1059 |
| 2 | Two-boundary vertical slice = GO/NO-GO gate | ✅ **GO** (2026-07-18) | #1063 #1137 #1172 · [ADR-023 §12](decisions/ADR-023.md) |
| 3 | Bulk port to `commonMain` | ✅ done | ↓ Stage 3 breakdown |
| 4 | Cross-language parity harness | 🔄 in progress | 1a #1387 · 1b #1458 · S3a [#1605](https://github.com/tyabu12/pastura/issues/1605) landed; S3b (RNG seam) [#1615](https://github.com/tyabu12/pastura/issues/1615) landed; S3b-2 (seeded fixtures) next · [#501](https://github.com/tyabu12/pastura/issues/501) |
| 5 | iOS consumption switch + code-merge | ⬜ not started | the remaining integration · adapter traps: [`kmp-interop.md`](../.claude/rules/kmp-interop.md) · ⚠️ en-only `ScenarioValidationMessage.render()` / `ScenarioLintMessage.render()` block this — [#1464](https://github.com/tyabu12/pastura/issues/1464), [#1562](https://github.com/tyabu12/pastura/issues/1562) |

Legend: ✅ done · 🔄 in progress · 🟡 partial · ⬜ not started.

## Stage 3 — bulk port (done)

| Slice | Status | Pointer |
|---|:--:|---|
| Models mirror | ✅ done | #1193 #1196 #1202 |
| Wave A — non-handler run-path (scoring, mechanisms, prompt/LLM glue) | ✅ done | #1207 #1212 #1217 |
| Wave B — 14 phase handlers | ✅ 14/14 | checklist ↓ |
| code-phase track | ✅ done | CP1 #1226 · CP2 #1230 · CP3 #1232 |
| Loader / validator port + `detector`·`logger` wiring | ✅ done | #1464 · #1552 (B1/B2) · #1558 (C2a) · #1560 (C2b) · #1562 (D1a) · #1564 (D1b) · #1574 (D2a) · #1579 (D2b) · #1582 (D2c) · #1587 (D2d) · #1591 (D3) · #1603 (seams) · [ADR-023](decisions/ADR-023.md) §4 · #501 |

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

- **Stage 4** (parity harness): 🔄 in progress — **both parity rungs are live**; the residue is
  scope, not machinery. See [ADR-023](decisions/ADR-023.md) §6 Stage 4,
  [#1387](https://github.com/tyabu12/pastura/issues/1387) (slice 1a, closed),
  [#1458](https://github.com/tyabu12/pastura/issues/1458) (slice 1b, closed),
  [#1605](https://github.com/tyabu12/pastura/issues/1605) (S3a, closed) and
  [#501](https://github.com/tyabu12/pastura/issues/501) (remaining Stage-4 work).

  `EngineParityTests` replays each `ParityGolden` fixture through the Kotlin engine and walks
  the transcripts against `DivergenceLedger`. It runs per-PR on the JVM (`:shared:engine:jvmTest`
  in `kmp-build-test`) and nightly on Kotlin/Native (`:shared:engine:build` includes
  `macosArm64Test`); `parity-emit --check` in `harness-build` guards the generated golden from
  either drift direction. **Every happy-path fixture agrees with nothing excused** — full
  runs, event for event and field for field, less four fields held constant:
  `duration_seconds` and `raw_text` are normalized away (`ParityFixtureEmitter.normalize`), while
  `t` and `attempt` are pinned to 0 by the emitter — which is why a `Structural` ledger entry has
  byte-identical lines to tell apart and keys on an ordinal.

  Of the six fixtures the four nominal ones carry the real-scenario parity claim (9 of 14
  handlers witnessed after S3a); the two controls exist so the ledger's own mechanisms stay
  provably reachable, with
  `someFixtureDrivesBothEntryKinds` keeping the structural one armed. Why each is shaped as it
  is: the `purpose` strings on `ParityFixtureEmitter.specs`.

  **S3b** landed the `RandomSource` seam on both engines
  ([#1615](https://github.com/tyabu12/pastura/issues/1615)) — parity fixtures can now carry a
  seed, but none does yet. Residue, all scope rather than mechanism: **S3b-2** seeded fixtures
  for the RNG-bearing presets witnessing the remaining 5 handlers and `assign random_one` ·
  #501, **S4** the cancellation event tail, **S5** ADR-023 §5.2 invariant 1's
  suspend-then-succeed assertion, **S6** the divergence-6 ruling (pinned as a ledger entry;
  deciding which side changes moves shipped Swift behaviour). `SimulationEvent.ErrorEvent`'s
  projection is known to disagree across languages and is unexercised by every fixture — S4 is
  the likely first driver.
- **Stage 5** (iOS switch + code-merge): ⬜ not started — the remaining iOS integration; the ported
  Kotlin loader still has no caller in `shared/engine`. See
  [ADR-023](decisions/ADR-023.md) §6 Stage 5.
