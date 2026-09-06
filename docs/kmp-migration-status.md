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

_Last updated: 2026-09-06._

## Stages

| Stage | What | Status | Key PRs / pointer |
|:--:|---|:--:|---|
| 0 | Pre-port refactors on `main` | ✅ done | #990 #991 #1051 #1000 |
| 1 | `shared/models` + CI infrastructure | ✅ done | #1052 #1055 #1059 |
| 2 | Two-boundary vertical slice = GO/NO-GO gate | ✅ **GO** (2026-07-18) | #1063 #1137 #1172 · [ADR-023 §12](decisions/ADR-023.md) |
| 3 | Bulk port to `commonMain` | ✅ done | ↓ Stage 3 breakdown |
| 4 | Cross-language parity harness | ✅ done (2026-08-30) | 1a #1387 · 1b #1458 · S3a [#1605](https://github.com/tyabu12/pastura/issues/1605) landed; S3b (RNG seam) [#1615](https://github.com/tyabu12/pastura/issues/1615) landed; S3b-2 (seeded fixtures) [#1618](https://github.com/tyabu12/pastura/issues/1618) landed; S4 (cancellation tail) [#1622](https://github.com/tyabu12/pastura/issues/1622) landed; S5 (suspend parity) [#1625](https://github.com/tyabu12/pastura/issues/1625) landed; S6 (divergence-6 ruling) [#1629](https://github.com/tyabu12/pastura/issues/1629) landed — Stage-4 residue cleared · [#501](https://github.com/tyabu12/pastura/issues/501) |
| 5 | iOS consumption switch + code-merge | 🔄 in progress | rulings + slices S5-1…S5-5 [#1633](https://github.com/tyabu12/pastura/issues/1633) · [ADR-023 §6 Stage 5](decisions/ADR-023.md) · adapter traps: [`kmp-interop.md`](../.claude/rules/kmp-interop.md) · message localization leaf landed [#1631](https://github.com/tyabu12/pastura/issues/1631) (Apple actual: in-app `ja` check → S5-4) · S5-1 link landed [#1636](https://github.com/tyabu12/pastura/issues/1636) [#1639](https://github.com/tyabu12/pastura/issues/1639) [#1640](https://github.com/tyabu12/pastura/issues/1640) [#1635](https://github.com/tyabu12/pastura/issues/1635) · S5-2 adapters + isolation audits landed [#1647](https://github.com/tyabu12/pastura/issues/1647) (#1650 #1655 + audits PR; probe nightly-wired [#1661](https://github.com/tyabu12/pastura/issues/1661)) · Phase 3 entered 2026-09-04 ([#1671](https://github.com/tyabu12/pastura/issues/1671)) · S5-3 prerequisites landed [#1673](https://github.com/tyabu12/pastura/issues/1673) · **S5-3 H5/H7 landed 2026-09-05** on `v1.3+886` — both PASS ([#501 evidence](https://github.com/tyabu12/pastura/issues/501#issuecomment-5550162180), close-out issue [#1679](https://github.com/tyabu12/pastura/issues/1679)); Decision 6 (ii) discharged, ADR-004 → GO · **S5-4 switch landed** ([#1681](https://github.com/tyabu12/pastura/issues/1681)) · **S5-4 soak PASS 2026-09-06** on `v1.3+888` ([#501 evidence](https://github.com/tyabu12/pastura/issues/501#issuecomment-5559576459), [runbook](qa/kmp-soak-qa.md)); Decision 6 (iii) discharged, ADR-004 §12 · next: S5-5 code-merge ([#1685](https://github.com/tyabu12/pastura/issues/1685)) |

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

- **Stage 4** (parity harness): ✅ complete (closed 2026-08-30, operator call on
  [#1633](https://github.com/tyabu12/pastura/issues/1633)) — **both parity rungs are live**, every
  planned slice (1a–S6) has landed, and the ledger carries only the two permanent divergence-6 pins. See [ADR-023](decisions/ADR-023.md) §6 Stage 4,
  [#1387](https://github.com/tyabu12/pastura/issues/1387) (slice 1a, closed),
  [#1458](https://github.com/tyabu12/pastura/issues/1458) (slice 1b, closed),
  [#1605](https://github.com/tyabu12/pastura/issues/1605) (S3a, closed) and
  [#501](https://github.com/tyabu12/pastura/issues/501) (umbrella).

  `EngineParityTests` replays each `ParityGolden` fixture through the Kotlin engine and walks
  the transcripts against `DivergenceLedger`. It runs per-PR on the JVM (`:shared:engine:jvmTest`
  in `kmp-build-test`) and nightly on Kotlin/Native (`:shared:engine:build` includes
  `macosArm64Test`); `parity-emit --check` in `harness-build` guards the generated golden from
  either drift direction. **Every happy-path fixture agrees with nothing excused** — full
  runs, event for event and field for field, less four fields held constant:
  `duration_seconds` and `raw_text` are normalized away (`ParityFixtureEmitter.normalize`), while
  `t` and `attempt` are pinned to 0 by the emitter — which is why a `Structural` ledger entry has
  byte-identical lines to tell apart and keys on an ordinal.

  Of the ten fixtures the six nominal ones carry the real-scenario parity claim (every handler
  is now witnessed by at least one fixture — "witnessed" here means replayed through a golden,
  distinct from the machine-checked *ported* checklist above); the four controls exist so the
  ledger's own mechanisms — and the two §5.2 contract clauses no nominal run reaches,
  cancellation and suspension — stay provably reachable, with
  `someFixtureDrivesBothEntryKinds` keeping the structural one armed. Why each is shaped as it
  is: the `purpose` strings on `ParityFixtureEmitter.specs`.

  **S3b** landed the `RandomSource` seam on both engines
  ([#1615](https://github.com/tyabu12/pastura/issues/1615)); **S3b-2**
  ([#1618](https://github.com/tyabu12/pastura/issues/1618)) landed the first seeded fixtures —
  `word_wolf` and `last_fable` — which reached `assign random_one`, `event_inject`, `eliminate`,
  `narrate`, `reflect` and `relationship_update` with an empty ledger on the first replay.
  **S4** ([#1622](https://github.com/tyabu12/pastura/issues/1622)) closed the cancellation
  event tail by fixing Swift: `ConditionalHandler` now throws on cancellation and the runner
  emits exactly one `.error(.cancelled)` per run, so `CANCELLATION_EVENT_TAIL` was deleted
  from the ledger; `parityCancelConditional` cancels both engines on the same emitted
  `phaseCompleted` (an event position, not a call index — Kotlin's `LLMCaller` observes
  cancellation inside a backend call, the Swift responder does not) and both `EventLineMapper`s
  now project the `error` line as the bare Swift case name.
  **S5** ([#1625](https://github.com/tyabu12/pastura/issues/1625)) froze ADR-023 §5.2
  invariant 1 — suspend re-issues stay off the retry budget — as
  `paritySuspendPreservesRetryBudget`: one turn takes exactly the three budgeted attempts
  interleaved with three suspend cycles, so either engine charging a suspend would skip the
  turn. Suspension is invisible in both transcripts (no `SimulationEvent` marks it), so
  `callCount` now counts suspend re-issues on both sides and each side guards its schedule
  loudly (`suspendNeverFired` / the delivered-suspend assertion). Green on both rungs with an
  empty ledger; no engine code changed.
  **S6** ([#1629](https://github.com/tyabu12/pastura/issues/1629)) ruled divergence-6 —
  `NUMBER_LITERAL_FORMATTING`, Swift `NSNumber.stringValue` vs Kotlin's preserved literal —
  **accepted permanently; neither engine changes** ([ADR-023 §15](decisions/ADR-023.md)). The
  text parses to the same Double wherever a field is read numerically, so the difference is
  unobservable as a value; the two ledger entries stay as the permanent pins. No Stage-4 residue
  remains.
- **Stage 5** (iOS switch + code-merge): 🔄 in progress — the three deferred questions were ruled on
  2026-08-30 ([#1633](https://github.com/tyabu12/pastura/issues/1633)) and the stage is sliced
  S5-1 link · S5-2 adapters + isolation audits (gives the Kotlin loader its first caller) ·
  S5-3 H5/H7 · S5-4 flag-gated switch + soak · S5-5 code-merge; S5-1/S5-2 were pre-Phase-3
  infrastructure, S5-3 onward needed Phase-3 entry. **S5-1 has landed**
  ([#1636](https://github.com/tyabu12/pastura/issues/1636),
  [#1639](https://github.com/tyabu12/pastura/issues/1639),
  [#1640](https://github.com/tyabu12/pastura/issues/1640),
  [#1635](https://github.com/tyabu12/pastura/issues/1635)'s PR-C): the app links and embeds the
  `PasturaSharedEngine` umbrella, and `SharedEngineLinkage` and `SharedEngineRunner` now live under
  `App/KMP/`. **S5-2 has landed** ([#1647](https://github.com/tyabu12/pastura/issues/1647):
  #1650 the `LLMBackend` actual, #1655 the §5 seam bridges + Kotlin `ScenarioLoader`'s first
  caller, plus the isolation-audit PR — Pattern-7 probe measured, Pattern-6 audit re-run; the
  probe now also runs nightly as a regression step,
  [#1661](https://github.com/tyabu12/pastura/issues/1661)). **Phase 3 entered 2026-09-04**
  ([#1671](https://github.com/tyabu12/pastura/issues/1671)). **S5-3 prerequisites have landed**
  ([#1673](https://github.com/tyabu12/pastura/issues/1673): the Kotlin `H7CrashProbe` with its
  inverse `@Throws` pin, the double-gated Settings Diagnostics row, the `release.sh` K/N dSYM /
  `Symbols/` checks and archive preservation, and the runbook
  [`docs/qa/h7-symbolication-qa.md`](qa/h7-symbolication-qa.md)). **S5-3 has landed**
  (2026-09-05, `v1.3+886`; [#501 evidence](https://github.com/tyabu12/pastura/issues/501#issuecomment-5550162180),
  close-out issue [#1679](https://github.com/tyabu12/pastura/issues/1679)): H5 passed on the upload,
  H7 on two named `H7CrashProbe` frames in App Store Connect's own crash view plus the archive
  dSYM resolving the same addresses locally. Decision 6 (ii) is discharged and ADR-004 graduated
  from Conditional GO to GO (§11); `release.sh`'s K/N dSYM / `Symbols/` checks are now fail-fast.
  The first cut, `v1.3+885`, could not reveal Diagnostics (#1677 → #1678). **S5-4 switch landed**
  ([#1681](https://github.com/tyabu12/pastura/issues/1681)) and its **soak passed** 2026-09-06 on
  `v1.3+888` — one operator cycle on an iPhone 16e in `ja`, the runbook's four presets (of six
  bundled) completed on the Kotlin engine, pause / background / kill-resume as specified, the `appleMain`
  `localizedFormat` actual rendering Japanese on device, no new crash in App Store Connect
  ([#501 evidence](https://github.com/tyabu12/pastura/issues/501#issuecomment-5559576459),
  [runbook](qa/kmp-soak-qa.md)). Decision 6 (iii) is discharged (ADR-004 §12), so all three
  sub-conditions are met — but the Swift Engine is still the shipping engine, because the S5-4
  switch is opt-in and **S5-5 flips the default**. Next: S5-5 code-merge and close-out
  ([#1685](https://github.com/tyabu12/pastura/issues/1685)). See
  [ADR-023](decisions/ADR-023.md) §6 Stage 5.
