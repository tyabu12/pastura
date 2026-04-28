# Subagent Usage Rules

Always-loaded — see `CLAUDE.md` `## Context-Specific Rules` for the
loading-mode rationale. Subagent calls can originate from any layer
(slash commands, `/orchestrate`, manual `Agent` tool invocations), so
this rule must stay visible regardless of which file is being edited.

## 1. Background

Claude Code subagents (anything launched via the `Agent` tool, including
custom `code-reviewer` / `critic` / `Explore` / `Plan`) run under a hard
**output-token cap**. The cap is NOT configurable via frontmatter
(`maxOutputTokens` does not exist) nor via `CLAUDE_CODE_MAX_OUTPUT_TOKENS`
(env var applies only to the main session, not subagent API calls).

GitHub issues tracking this:

- [#25569](https://github.com/anthropics/claude-code/issues/25569) — Closed as duplicate. Direct subagent report.
- [#10738](https://github.com/anthropics/claude-code/issues/10738) — Closed inactive (60 days).
- [#24055](https://github.com/anthropics/claude-code/issues/24055) — **OPEN, `oncall`**. Latest, Anthropic engineering aware.

The cap aligns with each model's spec maximum:

| Model | Max output tokens |
|-------|-------------------|
| Opus 4.x | **32,000** |
| Sonnet 4.x | **64,000** |
| Haiku 4.x | 8,192 |

So Opus subagents hit the cap at the model's spec limit; Sonnet subagents
have 2× the budget. The Issue #24055 fix (when it ships) may decouple
this from the model spec, at which point the heuristics below should be
revisited.

## 2. Caller-side scope discipline

When invoking a subagent, bound the work so the final report fits the
budget. Heuristics from PR #260 observations (see Appendix):

- **Soft budget** (split if over): ~800 changed lines OR ~8 changed
  files OR ~5 review axes per invocation, whichever is tighter.
- **Hard split** (always split): >1500 changed lines, >12 files, or
  >7 axes — these reliably truncate before the final report.

These are heuristics, not hard cutoffs. Actual budget consumption
depends on file size, output verbosity (e.g., a critic rubric's
per-axis Evidence + Recommendation can run 200-300 tokens each), and
the agent's self-determined depth. When numbers fall between soft and
hard, prefer splitting.

If splitting is impractical, see **§4. Sonnet override**.

## 3. Reviewer-model selection — delegated to orchestrate

Picking which model runs `code-reviewer` for a PR is
[`/orchestrate` skill's](.claude/skills/orchestrate/SKILL.md) responsibility
(see its **Coupling rule** and the Opus-required path list). This rule
does NOT duplicate that decision matrix — it only addresses the
budget-shaping side of subagent invocation.

The two domains interact at exactly one point: when scope splitting is
impractical, **§4. Sonnet override** can buy 2× cap headroom. The
override must satisfy both this rule's criteria AND orchestrate's
Coupling rule.

## 4. Sonnet override (escape valve)

`Agent(model: "sonnet")` overrides the agent's frontmatter `model: opus`
default and unlocks the 64K Sonnet budget. Use sparingly:

- **Acceptable**: scope-bound mechanical-checklist work that orchestrate's
  Coupling rule does NOT mark Opus-required. Example: a code review
  pass that is pure Hard-Rules / Dependency-Rules / Access-Modifier
  enforcement on a large mechanical diff (mass rename, code generation).
- **Not acceptable**: orchestrate Opus-required paths — project tooling
  (`.claude/{skills,agents,rules}/**`), AppRouter / navigation,
  dependency-rule boundaries, ADR/spec edits, etc.
- **`critic` non-recommendation**: `critic` makes judgement calls
  (pre-mortem axis generation, bias rebuttal). For plan critique on
  architectural decisions, prefer **Opus + scope-split** over Sonnet
  override. Sonnet's reasoning depth is acceptable for routine
  reviews but not for the cases where `critic` is most valuable.

## 5. Agent self-defense

Both `code-reviewer.md` and `critic.md` carry inline `## Scope Guidance`
and `## Output Discipline` sections (see those files). When the caller
exceeds the soft budget, the agent itself returns a single
`SCOPE_TOO_LARGE: ...` line **before any tool_use** to bail early.

This is the second layer — the caller-side discipline above is the
first. Both layers exist because subagent budget exhaustion is a
silent failure (intermediate text returned, final report missing), so
defense in depth matters more than for noisy failures.

## Appendix: PR #260 observation

The numbers above came from a single PR (#260, cellular download
consent dialog implementation, ~21 files, +1383/-495 lines, 8 review
axes). Observed during code review:

- `code-reviewer` on the full PR diff: consistently truncated at
  22-33 `tool_use` calls with intermediate "Let me check..." text
  returned instead of the final Verdict block. One run lasted 24
  minutes (33 tool_uses) before stopping.
- Splitting into 5 sub-scope invocations (each ≤6 files / ≤3 axes):
  every sub-scope completed with the full Verdict block.
- Raising frontmatter `maxTurns: 15 → 30 → 40` extended turn ceiling
  but did NOT change truncation — the cap is on output tokens, not
  turns. Exhausting the 32K output budget mid-investigation is the
  load-bearing failure mode.

When Issue #24055 ships a fix, the soft/hard numbers above need
revalidation. Until then, treat the heuristics as conservative
defaults and prefer splitting over override when in doubt.
