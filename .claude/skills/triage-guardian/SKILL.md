---
name: triage-guardian
description: Triage automation-origin open Draft PRs into a conservative merge / discard / judgment report, and surface aggregate WIP backpressure — read-only, never merges or closes. Use when the user asks to triage the Draft PR queue, run the triage guardian, prep a review session, check the brush-up automation backlog, or see whether the generators should throttle.
allowed-tools: Read, Grep, Glob, Bash
---

# /triage-guardian

One read-only triage pass over the automation-origin Draft-PR queue:
**enumerate → health → classify → report**. Run from the repository root of
the current checkout.

This is generator **O** of the "nightly brush-up automation" family — and the
first member that *protects* the scarce resource (the human's review attention)
rather than *producing* artifacts that spend it. The other members
(`consistency-audit`, `queue-consumer`) emit Draft PRs / issues; O reads that
queue and tells the human what to look at first, what is safe to discard, and
whether the generators should throttle.

**The central constraint:** a guardian that protects review attention must not
itself consume it. O therefore writes **nothing** — no PR, no issue, no
committed file, no PR comment, no label. Its only output is a transcript report
the human *pulls* when they sit down to review. This is the deliberate opposite
of the generators, and the reason O is the lightest family member to run.

## Non-goals

- **Never merges, never closes, never marks ready.** Every disposition is a
  recommendation for the human; the human is the only actuator. A "discard
  candidate" is a suggestion with counter-evidence, not an action.
- **Never writes anything.** No Draft PR, no issue, no digest file, no comment,
  no label, no push. `allowed-tools` omits `Write`/`Edit` so this is enforced
  at the tool layer, not just by convention. (#562 removed an over-built digest
  from a skill that produced ≤1 artifact per run; O produces **zero**, so even a
  digest would be pure review-burden with no payoff.)
- **Never triages human work.** Only automation-origin Drafts (branch prefix
  `^(audit|agent)/`) are classified. A human's own WIP Draft is their business;
  flagging it "discard candidate" would be both wrong and intrusive. Total Draft
  count is reported only as ambient context.
- **No second-guessing code correctness.** Substantive code PRs (`agent/*`,
  which carry queue-consumer feature implementations) route straight to "Needs
  your judgment" — O does not read diffs to argue about whether the code is
  right. That is what the human reviewer (and the PR's own mandatory
  code-reviewer pass) already did.

## Output Contract (inherited from the brush-up family)

**Canonical text: `.claude/rules/automation-output-contract.md` — read it in
full before Step 0.** It is path-scoped to `.claude/skills/**`, which fires when a
skill file is *read*, not on this skill's *execution* — a run drives its scripts
through Bash without reading a skill file, so nothing auto-loads it during a
run. The rule that binds O hardest is
**rule 2: any judgment output must carry a confidence score + a
counter-evidence ("why this might be wrong") section.** The "Discard candidate"
bucket is exactly such a judgment output — and the highest-stakes one, because
acting on a wrong discard destroys queued work. So **every** Discard line
carries confidence + counter-evidence (Step 3). Manual-first (rule 5) also
applies: the first real Draft O classifies is a precision-check point for the
human, mirroring consistency-audit's Step 1 note.

## Constants

- **Automation-Draft predicate** (canonical — see "Backpressure" below):
  an open Draft PR whose head branch matches `^(audit|agent)/`.
  `audit/*` = consistency-audit; `agent/*` = queue-consumer.
- **`AUTOMATION_WIP_CEILING = 5`** (canonical — see "Backpressure" below).
- Audit detector (reused for `audit/*` freshness): `.claude/skills/consistency-audit/scripts/audit_docs.py`

## Hard rules (non-negotiable)

1. **Read-only.** No `gh pr merge`, `gh pr close`, `gh pr ready`, `gh pr comment`,
   `gh pr edit --add-label`, `gh issue create`, `git push`, no `git commit`. If a
   step seems to need a write, it is out of scope — report it instead.
2. **Conservative classification wins.** A wrong "Ready" (human rubber-stamps a
   bad merge) or a wrong "Discard" (queued work destroyed) is worse than a miss.
   When the evidence is anything short of decisive, route to "Needs your
   judgment" — never up to "Ready" or "Discard".
   This survives Output Contract rule 6's 2026-08-12 change intact, and the
   resemblance to the wording that rule retired is why it says so here:
   **classification is the output stage.** O enumerates nothing — `gh pr list`
   hands it the complete Draft set — so being conservative here filters *how a
   already-enumerated PR is labelled*, never *whether it is looked at*. Rule 6
   bans the latter only.
3. **Never present a disposition as an action.** "Ready for your merge decision"
   means *nothing blocks a merge; you decide* — it is never "auto-merge
   eligible". O has no merge authority and must not imply it has.
4. **Stay within the read-only `gh` surface.** Use only `gh pr list`,
   `gh pr view`, `gh pr checks`, and the already-allowlisted audit detector.
   Do **not** reach for `gh api …/compare/…` or any broader command — keeping O
   on the narrow read surface is what lets it schedule with zero new write
   permissions.

## Step 0 — Preflight (abort on any failure)

1. `gh auth status` succeeds.
2. `gh` and `python3` are available (`python3` only needed if any `audit/*` PR
   is present, for the freshness re-run; check lazily).
3. `git fetch origin main` — the `audit/*` freshness re-run compares drift
   against `origin/main`, so the base must be current.
4. **Read `.claude/rules/automation-output-contract.md` in full.** Abort if
   missing. It does not auto-load during a run (its `paths:` glob fires on a read the run
   never performs), so this is the only step that puts the contract in context.

No clean-tree requirement: O never branches, commits, or leaves anything in the
working tree, so a dirty tree from a sibling task does not affect it. (It still
must not *overlap the queue-consumer window* in a shared checkout — see
"Scheduling".)

## Step 1 — Enumerate the automation-origin Draft queue

```bash
gh pr list --state open --draft \
  --json number,title,headRefName,createdAt,url \
  --jq '[.[] | select(.headRefName | test("^(audit|agent)/"))]'
```

Also capture the ambient total for context:

```bash
gh pr list --state open --draft --json number --jq 'length'
```

If the automation list is empty, report "no automation Drafts in the queue"
(plus the ambient total) and stop. There is nothing to triage and nothing to
throttle.

## Step 2 — Per-PR mechanical health

For each automation Draft `N`, gather only mechanically-determinable facts.
**Pin these exact invocations** — the alternatives have traps (validated
against real PRs at write time):

- **CI** — `gh pr checks <N> --json bucket` returns a bucket histogram and
  **exits 0 even on mixed/pending/failing states**. Do NOT use bare
  `gh pr checks <N>`: it exits 8 (pending) / 1 (failing) — non-zero on exactly
  the PRs the guardian most needs to classify, which aborts a `set -e` loop.
  ```bash
  gh pr checks <N> --json bucket --jq '[.[].bucket] | group_by(.) | map({(.[0]): length}) | add'
  ```
  Read as: all `pass`/`skipping` ⇒ green; any `fail`/`cancel` ⇒ red; any
  `pending` ⇒ still running. A PR with **zero** checks yields `null` (the `add`
  over an empty array) — that is *unknown*, not green, so route it to "Needs
  your judgment", never to "Ready".
- **Mergeability** — `gh pr view <N> --json mergeable,mergeStateStatus`.
  **`UNKNOWN` is the common case for an untouched Draft** (GitHub computes merge
  state lazily, only when a merge is contemplated) — it is *not* an error. Treat
  `mergeable == "UNKNOWN"` **or** `mergeStateStatus == "UNKNOWN"` as
  "unknown ⇒ route to Needs your judgment". When non-`UNKNOWN`,
  `mergeStateStatus` carries the behind/conflict signal: `DIRTY` = conflicts,
  `BEHIND` = behind base, `CLEAN`/`UNSTABLE` = mergeable (the latter with
  non-required-check noise). This is deliberately the only behind/conflict
  source — `gh api …/compare/…` is avoided per Hard rule 4.
- **Age** — from `createdAt` (Step 1). A long-stale Draft is a staleness signal,
  not by itself a discard reason.
- **Freshness (`audit/*` only)** — re-run the audit detector against the fetched
  base to see whether the drift this PR fixes still exists on `origin/main`:
  ```bash
  python3 .claude/skills/consistency-audit/scripts/audit_docs.py --repo-root . > /tmp/triage_audit.json
  ```
  Read `auto_fixable`. If the drift the PR targets is **absent** there, the fix
  has been superseded (merged via another path, or hand-fixed) — strong evidence
  for "Discard candidate", phrased as supersession ("the drift this PR fixes is
  already absent on main"), **not** "the PR is wrong" (the detector runs against
  main, not the PR's branch). The Output Contract batches *all* of a run's fixes
  into one `audit/<date>` PR, so supersession is **per-finding**: only treat the
  PR as a Discard candidate when **every** finding it targets is absent from
  `auto_fixable`. If some are gone but others remain, route to "Needs your
  judgment" — a partial supersession is the human's call.

`agent/*` PRs get no freshness re-run and no diff read — they are substantive
code and route to "Needs your judgment" by rule (Non-goals).

## Step 3 — Conservative 3-bucket classification

Assign each automation Draft to exactly one bucket. **When the evidence is short
of decisive, route down to (3)** (Hard rule 2).

1. **Ready for your merge decision** — *strongest evidence required.* CI green
   (all `pass`/`skipping`), `mergeStateStatus` is a non-`UNKNOWN` mergeable state
   (`CLEAN`/`UNSTABLE`), and the PR is from a contract-bounded generator (today:
   `audit/*`, whose auto-fix path edits only an authoritative-source-computed
   value — see Output Contract rule 3, authoritative values only, spliced at the exact offset). Present as
   *"nothing blocks a merge; you decide"* — **never** "auto-merge eligible"
   (Hard rule 3). If CI is pending or mergeability is `UNKNOWN`, it is NOT Ready
   — route to (3).

2. **Discard candidate** — the fix is superseded (`audit/*` freshness re-run
   shows the drift already absent on main), CI is red on a stale PR, or
   `mergeStateStatus == "DIRTY"` (unrecoverable conflict). **Per Output Contract
   rule 2, every Discard line MUST carry:**
   - a **confidence** score (how sure this is genuinely discardable), and
   - a **counter-evidence / "why this might be wrong"** note — e.g. "freshness
     ran against main, not the PR branch; the human may have intended a
     follow-up", or "CI red could be an infra flake (see
     `.claude/rules/xcodebuild-cli.md` § CI flake catalog), not a real failure".

   Discard means *recommend the human close it + delete the branch* — O never
   does either.

3. **Needs your judgment** — the **default, safe bucket.** Everything not
   decisively (1) or (2): all `agent/*` substantive-code PRs, anything with
   `UNKNOWN` mergeability or pending CI, anything ambiguous. When in doubt, here.

## Step 4 — Report (transcript only)

Emit a single high-signal report to the user / routine transcript:

- The three buckets, each PR as one line: `#N` · branch · one-line title · the
  mechanical facts that placed it there. Discard lines additionally carry
  confidence + counter-evidence (Step 3).
- **Aggregate WIP backpressure line**: `automation Drafts: <count>/<ceiling>` so
  the throttle state is visible at a glance (e.g. `3/5 — generators still
  generating`, or `5/5 — generators will skip next run`).
- The ambient total Draft count (incl. human Drafts) as context.
- A pointer to `/tmp/triage_audit.json` if a freshness re-run was done.

That report is the **whole** record. O leaves nothing behind — for a scheduled
run the routine's own run-log is the durable channel a human reads on demand
(see "Scheduling"). Do not write a file to "preserve" it; that would reintroduce
the artifact the read-only constraint forbids.

## Backpressure — canonical definition (single source of truth)

**This section is the canonical home of the WIP-backpressure constant and
predicate.** `consistency-audit` and `queue-consumer` reference it from their
Step 0 preflights; they inline the literal predicate/constant only because
markdown has no import (a `gh`-pipe needs the literal string), and each carries a
`# canonical: triage-guardian/SKILL.md § Backpressure` comment so drift is cheap
to spot. **If you change either value, update all three files in the same PR.**

```
AUTOMATION_WIP_CEILING = 5
automation-Draft predicate = open Draft PR whose head matches ^(audit|agent)/
```

Count, used identically by O (to report) and by each generator (to self-throttle):

```bash
WIP=$(gh pr list --state open --draft --json headRefName \
  --jq '[.[] | select(.headRefName | test("^(audit|agent)/"))] | length')
```

**Scope: this section bounds the Draft-PR lane only.** The constant and
predicate above count *open Draft PRs*, so rule-2 judgment **issues** fall
outside them entirely. That lane has its own per-run cap — `JUDGMENT_ISSUE_CAP`,
canonical in `.claude/skills/consistency-audit/SKILL.md` (Constants + Step 4
step 2), since `consistency-audit` is the only generator that files issues
unattended. It is a cross-reference, not a mirrored literal: it is **not** part
of the three-file sync rule above, and changing it does not touch this file.

**Why an aggregate ceiling on top of per-generator caps.** Each generator
already caps its *own* lane (consistency-audit: ≤1 open `audit/*`;
queue-consumer: QUOTA-2 per run). Nothing watches the *sum*. As more generators
come online, each stays within its local cap while the aggregate of unreviewed
Drafts climbs past what one human can absorb. The ceiling is that missing
sum-level guard. **It is advisory** — the per-generator hard caps remain the real
bound, so the preflight-count TOCTOU race (two generators both observe `4` and
both proceed to `6`) is benign.

**Why `5`.** Today's aggregate max is `1` (audit) `+ 2` (agent) `= 3 < 5`, so the
ceiling is **inert under the current 2-generator roster** — it first binds when a
3rd/4th generator lands (the roadmap lists i18n parity, code analysis, scenario
fuzzing). Wiring it now, while the convention is fresh, is the same move as
defining the Output Contract before there were consumers: the next generator
inherits backpressure for free instead of being retrofitted. The number is a
review-attention budget — revisit it if the roster or the human's capacity
changes.

## Scheduling & manual-first

- **Pull, not push.** O's primary mode is a human running `/triage-guardian`
  *before a review sitting* — the report is review-session prep the human pulls,
  exactly when they are spending attention intentionally. O never pings.
- **Manual-first.** Validate precision by hand before any scheduling: the first
  real automation Draft O classifies is the precision-check point (Output
  Contract rule 5 — manual-first).
- **The skill never self-registers a schedule.** Once precision is trusted, a
  *separate* Desktop **local** Routine may invoke `/triage-guardian` (the
  family's scheduling model — see consistency-audit § Scheduling). Because O is
  read-only, a scheduled run's durable record is the **routine's own run-log**
  (the analogue of consistency-audit's no-drift nights, where "the run history is
  the record") — a channel the human reads on demand, **not** a notification.
  Transcript-only therefore delivers value only when a human reads that log;
  that is acceptable precisely because O is pull-oriented. Do not add a push
  channel without a deliberate decision that does not violate read-only.
- **Lightest member to schedule.** O needs no `git commit` gate (it commits
  nothing) and **no new write-allowlist entries** (its commands —
  `gh pr list/view/checks`, the audit detector — are read-only and already
  allowlisted). On a scheduled checkout it still must **not overlap the
  queue-consumer window** if they share a checkout, to avoid reading a
  half-written queue state.
