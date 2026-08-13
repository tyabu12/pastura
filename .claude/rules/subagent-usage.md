# Subagent Usage Rules

> Derived from [claude-kit](https://github.com/tyabu12/claude-kit) `rules/subagent-usage.md` —
> the generic core is canonical there; reconcile one-way (kit → Pastura), **rule + doc as a pair**:
> since kit#24 both sides carry firing conditions here and depth in a paired doc, so diffing rules
> alone reads relocated depth as deletions. Pastura's doc is
> [`docs/agent-tooling/subagent-output-cap.md`](../../docs/agent-tooling/subagent-output-cap.md);
> the kit's are `docs/subagent-output-cap.md` (§1–§2) and `docs/code-review-path-scoped-rules.md`
> (§5) — the latter gets no Pastura counterpart on purpose, #1312 holds this repo's probes.
> Pastura-specific content lives only in this copy.

Always-loaded — see `CLAUDE.md` `## Context-Specific Rules` for the
loading-mode rationale. Subagent calls can originate from any layer
(slash commands, `/orchestrate`, manual `Agent` tool invocations), so
this rule must stay visible regardless of which file is being edited.

## 1. Background

Every subagent (anything launched via the `Agent` tool, including custom
`code-reviewer` / `claude-kit:critic` / `Explore` / `Plan`) runs under an
**output-token cap per response** — the *model's* cap, with no subagent-specific
variant. Neither frontmatter knob helps: `maxTurns` raises turns, not the
per-response cap, and `maxOutputTokens` is not a frontmatter key at all.

| Model | Cap | Ceiling via `CLAUDE_CODE_MAX_OUTPUT_TOKENS` |
|-------|-----|---------------------------------------------|
| Opus 5 | **64,000** | 128,000 † |
| Sonnet 5 | **64,000** | 128,000 † |
| Fable 5 | **64,000** † | 128,000 † |
| Haiku 4.5 | **32,000** | 64,000 † |

Measured 2026-08-12 on Claude Code **2.1.228**; `†` = catalog-read, not observed.
**Do not extrapolate to another generation in either direction** — the spread is
not uniform by family. On a Claude Code upgrade, re-read the live cap and
update the table; before trusting a pre-5 figure, read the doc's
§ "The cap table's provenance".

```sh
claude -p --model opus --output-format json "ok" | jq '.modelUsage[].maxOutputTokens'
```

`CLAUDE_CODE_MAX_OUTPUT_TOKENS` is the only real budget lever, and it **does**
reach subagents (evidence: doc § "The env-var lever reaches subagents").

**Model pins in this repo**: `code-reviewer.md` keeps `model: opus`
deliberately — for Opus-class review *judgement*, not for a token budget (§2's
numbers are model-independent). The kit-provided `claude-kit:critic` carries no
pin, so callers pass `model: opus` explicitly (as `/orchestrate` Step 1b does).
`fable` is a valid `Agent(model:)` / frontmatter value too — also a quality
lever, never a budget one. Skills omit `model:` and inherit the session model (a
pin would downgrade the main loop; re-pin only if the session model ever drops
below Opus-class).
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

**These numbers are review-attention bounds, NOT cap-derived** — a cap-table
change in §1 leaves them untouched unless it drops a cap *below* them, and they
are kit-canonical rather than a per-project knob. Go **tighter** at the call site when the diff is dense; never
looser. **Before revising them, or before arguing a call is an exception, read
the doc's § "Why the split thresholds are not cap-derived"** — the only valid
evidence is about review quality, not about tokens.

**A split leaves a seam no shard owns.** Each invocation sees only its own
slice, so anything spanning the split — a mirrored count, a cross-reference,
a claim one shard makes about another's files — is unreviewed by
construction. Name the seam's owner, or add a final pass over the whole.

**Spotting a cap hit.** A hit is not silent — Claude Code retries the response,
so what usually survives is a **seam** mid-report rather than a silent loss. The
tell is a **count mismatch**: the summary claims more issues, axes, or findings
than the body writes out, or names them with no evidence attached. Corroborate
with intermediate tool output present and no `SCOPE_TOO_LARGE`, then **split and
re-run**. In Pastura the check is arithmetic, not a prose judgement:
`code-reviewer`'s summary emits per-severity counts (`- **Critical**: N issues`)
to compare the body against. A report that is short *and internally consistent*
is just short — except in two shapes that leave no count to mismatch:

- **No verdict at all** — the run returns only its opening sentence. Seen on
  broad **multi-axis verification** prompts, not on large diffs (#1410). Treat
  it as "re-run narrower", not as a finding: cut what the prompt asks the agent
  to *verify*, not how many files it sees. Requesting the verdict in the first
  message is cheap insurance.
- **A zero-issue report** — a summary claiming nothing cannot mismatch, so a cut
  landing right after it reads as consistent. Closing that needs a structural
  check against a pinned Output Format; `queue-consumer` hard rule 6 carries one
  for the unattended path.

Both shapes trace to one conditional in the agent definitions. **When a report
looks truncated and you are deciding whether to re-run, read the doc's § "How a cap hit behaves"** before concluding the run was fine.

## 3. Model choice is a cost lever, not a budget lever

`Agent(model: "sonnet")` buys no headroom — Opus 5 and Sonnet 5 are both
**64,000**. Pick the model for **capability and cost**, never to escape a
budget. The one budget-relevant asymmetry is **Haiku at half** (32,000): do not
hand it a report-heavy task assuming every model carries the same load. When
work genuinely needs more room, **split the scope** — raising
`CLAUDE_CODE_MAX_OUTPUT_TOKENS` (§1) buys tokens, not attention.

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
  `critic` makes judgement calls (pre-mortem axis generation, bias rebuttal).
  For plan critique on architectural decisions, prefer **Opus + scope-split**
  over a cheaper model. Sonnet's reasoning depth is acceptable for routine
  reviews but not for the cases where `critic` is most valuable.

## 4. Agent self-defense

The two defend asymmetrically. `code-reviewer.md` restates §2's line/file
numbers and bails with `SCOPE_TOO_LARGE` **before any tool_use**;
`claude-kit:critic` carries an axis-only budget (≤5 axes, triage above 7) and
acts *during* the run, stopping to report at ~15 tool_use calls. **Keep
`code-reviewer.md`'s copy in sync with §2** — critic's is kit-owned and
one-way. Do not delete either as redundant: the doc's § "Why the agents
duplicate the budget" has the reason.

## 5. Official `/code-review` vs the custom agents

The official `/code-review` skill does **not** replace `code-reviewer`
or `critic` — the three occupy non-overlapping slots (for the
`code-reviewer`-vs-`critic` split itself, see §3).

| Tool | Reviews | Runs as | Convention source |
|------|---------|---------|-------------------|
| `/code-review` (official) | working-tree diff: bugs + reuse/simplify cleanups | **foreground, manual** (effort dial up to `ultra` = cloud, billed; `--comment` / `--fix`) | `CLAUDE.md` only |
| `code-reviewer` | feature-branch diff vs conventions | **subagent gate** — `/orchestrate` Step 4, `/queue-consumer` "No unreviewed PR" | `CLAUDE.md` **+** `.claude/rules/` traps |
| `claude-kit:critic` (plugin) | plans / ADRs / design — **not a diff** | subagent — `/orchestrate` Step 1b | — |

**Load-bearing: do NOT slim `code-reviewer`'s general-quality /
Swift-6-concurrency / secrets sections to "defer to `/code-review`".**
`code-reviewer` is the *sole* review gate on the unattended path
(`/queue-consumer` overnight), and the official skill misses `.claude/rules/`
traps and generic secrets/coverage findings entirely. **Before acting on any
proposal to consolidate the two, read the doc's § "Why `/code-review` cannot substitute"** — the two gaps are load-bearing and one of them has an open
cause that must not be reasoned forward from.

Reach for `/code-review` (e.g. `/code-review high`) as a **complement** —
deeper generic bug-hunting or `--fix` auto-apply *on top of* the
convention gate — never as a substitute.
