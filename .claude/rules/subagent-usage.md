# Subagent Usage Rules

> Derived from [claude-kit](https://github.com/tyabu12/claude-kit) `rules/subagent-usage.md` —
> the generic core is canonical there; reconcile one-way (kit → Pastura). Everything numeric — the
> cap table, the `#24055` status, the 800/8/5 and 1500/12/7 split thresholds — is kit-canonical:
> the thresholds are *derived* from the cap table (smallest practical budget, prose-dense report),
> so they are recomputed upstream, never retuned here. The one lever a caller controls is report
> density per changed line — generated fixtures report far shorter than dense source — and it
> licenses bounding a call **tighter at the call site, never looser**: split smaller rather than
> edit §2's numbers or any agent copy of them (today `.claude/agents/code-reviewer.md`).
> Pastura-specific content lives only in this copy.

Always-loaded — see `CLAUDE.md` `## Context-Specific Rules` for the
loading-mode rationale. Subagent calls can originate from any layer
(slash commands, `/orchestrate`, manual `Agent` tool invocations), so
this rule must stay visible regardless of which file is being edited.

## 1. Background

Claude Code subagents (anything launched via the `Agent` tool, including
custom `code-reviewer` / `claude-kit:critic` / `Explore` / `Plan`) run under a hard
**output-token cap**. The cap is NOT configurable via frontmatter
(`maxOutputTokens` does not exist) nor via `CLAUDE_CODE_MAX_OUTPUT_TOKENS`
(env var applies only to the main session, not subagent API calls).

Tracked upstream in [anthropics/claude-code#24055](https://github.com/anthropics/claude-code/issues/24055) (OPEN) — revalidate the heuristics below when it ships.

Per-model output cap:

| Model | Max output tokens |
|-------|-------------------|
| Opus 4.x | **32,000** |
| Sonnet 4.x / 5 | **64,000** |
| Haiku 4.x | 8,192 |
| Fable 5 | **undocumented** — see note below |

Raising frontmatter `maxTurns` does not help — the cap is on output tokens, not turns.

**Fable 5 note**: `fable` is a valid `Agent(model:)` / frontmatter
alias, but its subagent cap is undocumented (2026-06-11) — treat a
`fable` override as a quality lever; Sonnet 64K stays the only known
**budget** escape valve (§3). `code-reviewer.md` keeps `model: opus`
deliberately (§2 / §4 are 32K-calibrated); the kit-provided
`claude-kit:critic` carries no pin, so callers pass `model: opus`
explicitly (as `/orchestrate` Step 1b does). Skills omit
`model:` and inherit the session model (a pin would downgrade the main
loop; re-pin only if the session model ever drops below Opus-class).
Docs: [sub-agents](https://code.claude.com/docs/en/sub-agents.md),
[model-config](https://code.claude.com/docs/en/model-config.md).

## 2. Caller-side scope discipline

When invoking a subagent, bound the work so the final report fits the
budget (derived — tighten at the call site, don't edit; see the header):

- **Soft budget** (split if over): ~800 changed lines OR ~8 changed
  files OR ~5 review axes per invocation, whichever is tighter.
- **Hard split** (always split): >1500 changed lines, >12 files, or
  >7 axes — at this size the report reliably loses its substance
  before the run completes.

When numbers fall between soft and hard, prefer splitting. If splitting
is impractical, see **§3. Sonnet override**.

**A split leaves a seam no shard owns.** Each invocation sees only its own
slice, so anything spanning the split — a mirrored count, a cross-reference,
a claim one shard makes about another's files — is unreviewed by
construction. Name the seam's owner, or add a final pass over the whole.

**What exhaustion looks like.** *Not* a missing summary: review agents
are built to emit their verdict/summary **first** under cap pressure, so
it survives exactly when the run is truncated. Look instead for **detail
missing behind a present summary**, which is mechanically checkable as a
**count mismatch** — the summary claims more issues, axes, or findings
than the body actually writes out, or names them with no evidence
attached. Corroborate with intermediate tool output present and no
`SCOPE_TOO_LARGE`. That combination is the signal to **split and
re-run** — a report that is short *and internally consistent* is just
short, and needs nothing. In Pastura the check is arithmetic rather than
a prose judgement: `code-reviewer`'s summary emits per-severity counts
(`- **Critical**: N issues`) to compare the body against.

**A second failure shape: no verdict at all.** The paragraph above says a
missing summary is *not* what exhaustion looks like, because agents emit the
verdict first. Observed counter-example (#1410, 13 `code-reviewer` runs): four
returned **only their opening sentence** — "I'll start with the mandatory scope
check." — with no verdict, no findings, and no `SCOPE_TOO_LARGE`. The
count-mismatch detector cannot see this: there is no summary to compare a body
against.

The four shared a broad **multi-axis verification workload** (a prompt asking
the agent to execute many independent claims), not a large diff — two of them
covered under 120 changed lines. **Do not read a tool-call ceiling into it**:
all four stopped at exactly 30 tool calls, but a *successful* run in the same
batch used 36, so the count alone explains nothing and the mechanism is
unestablished.

**Apply**: treat an opening-line-only return as "re-run narrower", not as a
finding about the code, and cut the number of things the prompt asks the agent
to *verify* rather than the number of files. Asking for the verdict in the
first message is cheap insurance and is what the surviving runs did.

**Blind spot**: a summary claiming nothing cannot mismatch, so a
zero-issue report truncated right after it reads as consistent. Closing
that needs a structural check against a pinned Output Format — see
`queue-consumer` hard rule 6, which carries one for the unattended path.

## 3. Sonnet override (escape valve)

`Agent(model: "sonnet")` overrides the agent's frontmatter `model: opus`
default and unlocks the 64K Sonnet budget. Use sparingly:

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
  architectural decisions, prefer **Opus + scope-split** over Sonnet
  override. Sonnet's reasoning depth is acceptable for routine
  reviews but not for the cases where `critic` is most valuable.

## 4. Agent self-defense

`code-reviewer.md` carries an inline `Scope Guidance` section that bails
with `SCOPE_TOO_LARGE` before any tool_use when the soft budget is
exceeded. The kit-provided `claude-kit:critic` self-defends differently
(its `Output Discipline & Scope` section triages: highest-risk axes
first, explicit deferrals instead of a bail-out). Defense in depth:
budget exhaustion is silent, so duplicating §2's budget in the agents'
own bail-out is intentional.
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
