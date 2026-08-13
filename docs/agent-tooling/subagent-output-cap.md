# Subagent output caps — the depth behind `subagent-usage.md`

Paired with the always-loaded rule `.claude/rules/subagent-usage.md`, which carries the firing
conditions — the numbers, the budgets, and the decision each one drives. This file carries the
*why* and the *evidence*: how the numbers were obtained, what they do and do not establish, and
which of them move on what trigger.

**Reconcile as a pair.** The kit counterpart is [claude-kit](https://github.com/tyabu12/claude-kit)
`docs/subagent-output-cap.md`; its rule is `rules/subagent-usage.md`. Diffing either half alone
reads relocated depth as a deletion.

**Why this is a doc and not a `paths:`-scoped rule.** A path-scoped rule injects on a `Read` whose
path matches its globs, so it would still leave the always-loaded budget. It was not chosen because
the moment this content is needed — sizing a subagent call — happens in *any* file, and no glob
covers "any". Keeping the trigger in the always-loaded rule and the evidence here is the honest
split. The cost, accepted: this file loads only when something reads it, so the rule's pointers to
it are written as instructions, not as "see also".

## The cap table's provenance

Measured **2026-08-12 on Claude Code 2.1.228**. The `†` markers in the rule's table mean
*read from the shipped model catalog, not behaviourally verified*; only the unmarked caps were
observed in a live run. Re-read the live value on a Claude Code upgrade — it takes seconds and
needs no truncation to be provoked:

```sh
claude -p --model opus --output-format json "ok" | jq '.modelUsage[].maxOutputTokens'
```

**Do not extrapolate across generations in either direction.** The spread is not uniform by family:
Opus 4.6-4.8 already sat at 64,000 while Sonnet 4.x was at 32,000 and Haiku 3.5 at 8,192. A new
generation means re-reading the catalog, not scaling the numbers you have.

## The env-var lever reaches subagents

The rule used to claim the opposite. It was corrected by forcing the variable to 1,200 and finding
the subagent's own responses capped at exactly that number — so the variable is not
main-session-only, and it is the one real budget lever. Model choice is not one (see below).

Tracked upstream at
[anthropics/claude-code#24055](https://github.com/anthropics/claude-code/issues/24055), **open** as
of 2026-08-12: it asks for the cap to be configurable per subagent.

## Why the split thresholds are not cap-derived

They used to be presented as derived, pinned to a cap no spawnable model ever had. Two things
follow from that being wrong.

First, the cap was never the binding constraint at these scopes — a threshold that would not have
changed had the cap been right was not really derived from it. What the thresholds buy is **review
attention**, which does not scale with a model's `max_tokens`.

Second, and this is the consequence for future edits: revise them on evidence about *review
quality* — a reviewer that misses things at 800 changed lines, or does fine at 1,500 — and never by
recomputing when a cap moves. A cap-table update leaves the thresholds untouched.

That is also why they stay **kit-canonical** rather than becoming a per-project knob: the attention
being bounded is a *subagent's* at a given scope, identical for every installation of the kit. The
one lever a caller genuinely controls is report density per changed line — 800 lines of generated
fixtures report far shorter than 800 lines of dense source — and it licenses bounding a call
**tighter at the call site, never looser**. Split smaller instead of editing the numbers, in the
rule or in any agent copy of them (today `.claude/agents/code-reviewer.md`).

## How a cap hit behaves

A hit is **not silent**. Claude Code detects `stop_reason: max_tokens`, nudges the agent to resume,
and retries up to **3** times before surfacing `API Error: … exceeded the N output token maximum.`
The report usually survives with a **seam** where the cut happened; only if every resume also
overflows does the run fail outright and return nothing.

The count-mismatch heuristic works because of how the review agents are written, not because of
anything the platform does. `code-reviewer.md`'s Output Format puts `## Review Summary` first, so
the summary is written before the body it summarises and a cut lands in the body — leaving the
header over-claiming. An agent that summarised *last* would give no such tell.

**What that does not guarantee.** The instruction that makes an agent stop investigating and emit
the report early is *conditional* on the agent noticing its own budget: `code-reviewer.md` fires it
"near 20+ `tool_use` calls". A run that exhausts before noticing never reaches the Output Format at
all. That is the mechanism behind both escape shapes the rule lists:

- **No verdict at all** — the conditional never fires and the run returns only its opening
  sentence, leaving the count-mismatch check no summary to work from. Observed on broad
  **multi-axis verification** prompts rather than on large diffs (#1410), which is why the remedy
  is to cut what the prompt asks the agent to *verify* rather than how many files it sees — and why
  asking for the verdict in the first message helps: it makes the instruction unconditional.
- **A zero-issue report** — a summary claiming nothing has no count to under-deliver on, so a cut
  landing right after it stays internally consistent and passes the check. Closing this needs a
  structural check against a pinned Output Format: the caller confirming every mandatory section is
  present, not just the Verdict line. Pastura closes it for the unattended path in
  `queue-consumer` hard rule 6; the remedy is bound to a project-owned output contract, which is
  why the kit records it as an open gap instead of carrying one.

## Why the agents duplicate the budget

`code-reviewer.md` bails with `SCOPE_TOO_LARGE` before any `tool_use` when the soft budget is
exceeded; the kit-provided `claude-kit:critic` triages instead (highest-risk axes first, explicit
deferrals). Restating the caller-side budget inside the agents looks redundant and is not: a cap hit
usually shows up as nothing louder than a seam mid-report, so a second line of defense that fires
*before* the work starts is worth its duplication.

## Why `/code-review` cannot substitute

`code-reviewer` is the *sole* review gate on the unattended path (`/queue-consumer` overnight).
`/code-review` is a foreground interactive skill, never wired into a subagent slot, so on that path
nothing else runs at all.

Beyond wiring, the official skill leaves two gaps:

1. It names `CLAUDE.md` as its convention source, and path-scoped rules are **measured** not to
   reach it — so the `.claude/rules/` trap cheat sheet is invisible to it. The *cause* of that
   non-arrival is open (see the kit's `docs/code-review-path-scoped-rules.md`, and #1312 for this
   repo's own injection probes); do not reason forward from a mechanism for it.
2. Its false-positive rule discards generic code-quality / security / test-coverage findings unless
   `CLAUDE.md` demands them.

So Dependency Rules, which live in `CLAUDE.md`, may surface through either gate — but
`.claude/rules/` traps and generic secrets/coverage findings surface only through `code-reviewer`.
That asymmetry is why its general-quality, Swift-6-concurrency and secrets sections must not be
slimmed to "defer to `/code-review`".
