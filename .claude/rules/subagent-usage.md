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

Tracked upstream in [anthropics/claude-code#24055](https://github.com/anthropics/claude-code/issues/24055) (OPEN) — revalidate the heuristics below when it ships.

Per-model output cap:

| Model | Max output tokens |
|-------|-------------------|
| Opus 4.x | **32,000** |
| Sonnet 4.x | **64,000** |
| Haiku 4.x | 8,192 |

Raising frontmatter `maxTurns` does not help — the cap is on output tokens, not turns.

## 2. Caller-side scope discipline

When invoking a subagent, bound the work so the final report fits the
budget:

- **Soft budget** (split if over): ~800 changed lines OR ~8 changed
  files OR ~5 review axes per invocation, whichever is tighter.
- **Hard split** (always split): >1500 changed lines, >12 files, or
  >7 axes — these reliably truncate before the final report.

Actual usage depends on file size and output verbosity — when numbers
fall between soft and hard, prefer splitting. If splitting is
impractical, see **§3. Sonnet override**.

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
- **`critic` non-recommendation**: `critic` makes judgement calls
  (pre-mortem axis generation, bias rebuttal). For plan critique on
  architectural decisions, prefer **Opus + scope-split** over Sonnet
  override. Sonnet's reasoning depth is acceptable for routine
  reviews but not for the cases where `critic` is most valuable.

## 4. Agent self-defense

`code-reviewer.md` and `critic.md` carry inline `Scope Guidance` /
`Output Discipline` sections that bail with `SCOPE_TOO_LARGE` before any
tool_use when the soft budget is exceeded. Defense in depth: subagent
budget exhaustion is silent (intermediate text returned, final report
missing), so the duplication with §2 is intentional.
