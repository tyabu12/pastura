# Subagent Usage Rules

> Derived from [claude-kit](https://github.com/tyabu12/claude-kit) `rules/subagent-usage.md` —
> the generic core is canonical there; reconcile one-way (kit → Pastura). Everything numeric — the
> cap table, the `#24055` status, the 800/8/5 and 1500/12/7 split thresholds — is kit-canonical, but
> two kinds of number live here and they age differently. The **cap table** is Claude Code's
> platform limit: recomputed when the platform changes, never retuned. The **split thresholds** are
> a *review-attention* bound and are **NOT** cap-derived — they rest on a *subagent's* attention at
> a given scope, identical for everyone who installs the kit, so they are revised on review-quality
> evidence and never by recomputing when a cap moves (§2). The one lever a caller controls is report
> density per changed line — generated fixtures report far shorter than dense source — and it
> licenses bounding a call **tighter at the call site, never looser**: split smaller rather than
> edit §2's numbers or any agent copy of them (today `.claude/agents/code-reviewer.md`).
> Pastura-specific content lives only in this copy.

Always-loaded — see `CLAUDE.md` `## Context-Specific Rules` for the
loading-mode rationale. Subagent calls can originate from any layer
(slash commands, `/orchestrate`, manual `Agent` tool invocations), so
this rule must stay visible regardless of which file is being edited.

## 1. Background

Every subagent (anything launched via the `Agent` tool, including custom
`code-reviewer` / `claude-kit:critic` / `Explore` / `Plan`) runs under an
**output-token cap per response**. It is the *model's* cap, not a
subagent-specific one: the request builder has no main/subagent branch and the
`Agent` tool passes no override. Raising frontmatter `maxTurns` does not help —
the cap is per response, not per run — and `maxOutputTokens` does not exist as
a frontmatter key.

| Model | Cap | Ceiling via `CLAUDE_CODE_MAX_OUTPUT_TOKENS` |
|-------|-----|---------------------------------------------|
| Opus 5 | **64,000** | 128,000 † |
| Sonnet 5 | **64,000** | 128,000 † |
| Fable 5 | **64,000** † | 128,000 † |
| Haiku 4.5 | **32,000** | 64,000 † |

Measured 2026-08-12 on Claude Code **2.1.228**. Pre-5 generations vary either
way — Opus 4.6-4.8 also sat at 64,000, Sonnet 4.x at 32,000, Haiku 3.5 at
8,192 — so **do not extrapolate backwards**. **† = read from the shipped model
catalog, not behaviourally verified**; only the unmarked caps were observed in
a live run. Read any model's live cap in about two seconds, without having to
provoke a truncation:

```sh
claude -p --model opus --output-format json "ok" | jq '.modelUsage[].maxOutputTokens'
```

`CLAUDE_CODE_MAX_OUTPUT_TOKENS` is the only real budget lever, and it **does**
reach subagents — contrary to what this rule claimed before, and confirmed by
forcing it to 1,200 and finding the subagent's own responses capped at exactly
that number. Tracked upstream in
[anthropics/claude-code#24055](https://github.com/anthropics/claude-code/issues/24055) (OPEN).

**Model pins in this repo**: `code-reviewer.md` keeps `model: opus`
deliberately — for Opus-class review *judgement*, not for a token budget. §2's
numbers are model-independent, so the pin buys the quality of the reading, not
the size of the budget. The kit-provided `claude-kit:critic` carries no pin, so
callers pass `model: opus` explicitly (as `/orchestrate` Step 1b does). `fable`
is a valid `Agent(model:)` / frontmatter value too — also a quality lever, never
a budget one. Skills omit `model:` and inherit the session model (a pin would
downgrade the main loop; re-pin only if the session model ever drops below
Opus-class).
Docs: [sub-agents](https://code.claude.com/docs/en/sub-agents.md),
[model-config](https://code.claude.com/docs/en/model-config.md).

## 2. Caller-side scope discipline

When invoking a subagent, bound the work so the reviewer's **attention** holds
— not so the report fits the cap; at these sizes it fits comfortably:

- **Soft budget** (split if over): ~800 changed lines OR ~8 changed
  files OR ~5 review axes per invocation, whichever is tighter.
- **Hard split** (always split): >1500 changed lines, >12 files, or
  >7 axes — at this size review quality degrades whatever the token
  budget permits.

When numbers fall between soft and hard, prefer splitting. Model choice is no
escape from an over-scoped call — see **§3**.

### Why the thresholds are not cap-derived

They used to be, pinned to a cap no spawnable model ever had. The cap was never
the binding constraint at these scopes; what they buy is **review attention**,
which does not scale with a model's `max_tokens`. So revise them on
review-quality evidence, **not** by recomputing when a cap moves — a cap-table
update (§1) must leave the numbers above untouched.

**A split leaves a seam no shard owns.** Each invocation sees only its own
slice, so anything spanning the split — a mirrored count, a cross-reference,
a claim one shard makes about another's files — is unreviewed by
construction. Name the seam's owner, or add a final pass over the whole.

**What a cap hit looks like.** It is **no longer silent**: Claude Code detects
`stop_reason: max_tokens`, nudges the agent to resume, and retries up to
**3** times before surfacing an `API Error: … exceeded the N output token
maximum.` The report usually survives with a **seam** where the cut happened —
but if every resume also overflows, the run fails outright with that error and
returns nothing.

The tell is *not* a missing summary: review agents are built to emit their
verdict/summary **first** under cap pressure, so it survives exactly when the
run is truncated. Look instead for **detail missing behind a present summary**,
which is mechanically checkable as a **count mismatch** — the summary claims
more issues, axes, or findings than the body actually writes out, or names them
with no evidence attached. Corroborate with intermediate tool output present
and no `SCOPE_TOO_LARGE`. That combination is the signal to **split and
re-run** — a report that is short *and internally consistent* is just
short, and needs nothing. In Pastura the check is arithmetic rather than
a prose judgement: `code-reviewer`'s summary emits per-severity counts
(`- **Critical**: N issues`) to compare the body against.

**A second failure shape: no verdict at all**, contradicting the guarantee
above — the run returns only its opening sentence, leaving the count-mismatch
detector no summary to check a body against. Seen on broad **multi-axis verification** prompts, not on large diffs
(#1410). **Apply**: treat it as "re-run narrower" rather than as a finding, and
cut what the prompt asks the agent to *verify*, not how many files it sees.
Requesting the verdict in the first message is cheap insurance.

**Blind spot**: a summary claiming nothing cannot mismatch, so a
zero-issue report truncated right after it reads as consistent. Closing
that needs a structural check against a pinned Output Format — see
`queue-consumer` hard rule 6, which carries one for the unattended path.

## 3. Model choice is a cost lever, not a budget lever

`Agent(model: "sonnet")` no longer buys headroom — Opus 5 and Sonnet 5 are
both **64,000** — so the "Sonnet override" that used to sit here as a budget
escape valve no longer exists. Pick the model for **capability and cost**,
never to escape a budget. The one budget-relevant asymmetry is **Haiku at
half** (32,000): do not hand it a report-heavy task on the assumption every
model carries the same load. When work genuinely needs more room than the model
has, **split the scope**. Raising `CLAUDE_CODE_MAX_OUTPUT_TOKENS` (§1) buys
tokens, not attention, and is never a substitute for splitting.

A cost-driven downgrade is still bounded by the same sensitivity rules
`/orchestrate` applies:

- **Acceptable**: scope-bound mechanical-checklist work that orchestrate's
  Coupling rule does NOT mark Opus-required. Example: a code review
  pass that is pure Hard-Rules / Dependency-Rules / Access-Modifier
  enforcement on a large mechanical diff (mass rename, code generation).
- **Not acceptable**: orchestrate Opus-required paths — project tooling
  (`.claude/{skills,agents,rules}/**`), AppRouter / navigation,
  dependency-rule boundaries, ADR/spec edits, etc.
- **`critic` non-recommendation** (`critic` in prose = the
  `claude-kit:critic` plugin agent — invoke it by that namespaced name):
  `critic` makes judgement calls
  (pre-mortem axis generation, bias rebuttal). For plan critique on
  architectural decisions, prefer **Opus + scope-split** over a cheaper
  model. Sonnet's reasoning depth is acceptable for routine
  reviews but not for the cases where `critic` is most valuable.

## 4. Agent self-defense

`code-reviewer.md` carries an inline `Scope Guidance` section that bails
with `SCOPE_TOO_LARGE` before any tool_use when the soft budget is
exceeded. The kit-provided `claude-kit:critic` self-defends differently
(its `Output Discipline & Scope` section triages: highest-risk axes
first, explicit deferrals instead of a bail-out). Defense in depth:
a cap hit usually shows up as nothing louder than a seam mid-report, so
duplicating §2's budget in the agents' own bail-out is intentional.
For what exhaustion actually looks like, see §2 — the detector lives
there, with the caller-side heuristics it corroborates.

## 5. Official `/code-review` vs the custom agents

The official `/code-review` skill does **not** replace `code-reviewer`
or `critic` — the three occupy non-overlapping slots. (For the
`code-reviewer`-vs-`critic` split itself, see §3's `critic`
non-recommendation note; this section covers only the official-skill
axis.)

| Tool | Reviews | Runs as | Convention source |
|------|---------|---------|-------------------|
| `/code-review` (official) | working-tree diff: bugs + reuse/simplify cleanups | **foreground, manual** (effort dial up to `ultra` = cloud, billed; `--comment` / `--fix`) | `CLAUDE.md` only |
| `code-reviewer` | feature-branch diff vs conventions | **subagent gate** — `/orchestrate` Step 4, `/queue-consumer` "No unreviewed PR" | `CLAUDE.md` **+** `.claude/rules/` traps |
| `claude-kit:critic` (plugin) | plans / ADRs / design — **not a diff** | subagent — `/orchestrate` Step 1b | — |

**Load-bearing: do NOT slim `code-reviewer`'s general-quality /
Swift-6-concurrency / secrets sections to "defer to `/code-review`".**
`code-reviewer` is the *sole* review gate on the unattended path
(`/queue-consumer` overnight); `/code-review` is a foreground
interactive skill never wired into a subagent slot, so on that path
nothing else runs. The official skill also leaves two gaps by design
(per its plugin definition): it reads `CLAUDE.md` only — never
`.claude/rules/`, so the trap cheat sheet is invisible to it — and its
false-positive rule discards generic code-quality / security /
test-coverage findings unless `CLAUDE.md` demands them. So Dependency
Rules (in `CLAUDE.md`) may surface via either gate, but `.claude/rules/`
traps and generic secrets/coverage surface only through `code-reviewer`.

Reach for `/code-review` (e.g. `/code-review high`) as a **complement** —
deeper generic bug-hunting or `--fix` auto-apply *on top of* the
convention gate — never as a substitute.
