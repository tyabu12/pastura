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
| Sonnet 4.x / 5 | **64,000** |
| Haiku 4.x | 8,192 |
| Fable 5 | **undocumented** — see note below |

Raising frontmatter `maxTurns` does not help — the cap is on output tokens, not turns.

**Fable 5 note**: `fable` is a valid `Agent(model:)` / frontmatter
alias, but its subagent cap is undocumented (2026-06-11) — treat a
`fable` override as a quality lever; Sonnet 64K stays the only known
**budget** escape valve (§3). `code-reviewer.md` / `critic.md` keep
`model: opus` deliberately (§2 / §4 are 32K-calibrated); skills omit
`model:` and inherit the session model (a pin would downgrade the main
loop; re-pin only if the session model ever drops below Opus-class).
Docs: [sub-agents](https://code.claude.com/docs/en/sub-agents.md),
[model-config](https://code.claude.com/docs/en/model-config.md).

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
| `critic` | plans / ADRs / design — **not a diff** | subagent — `/orchestrate` Step 1b | — |

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
