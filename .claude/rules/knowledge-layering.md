# Knowledge Layering & Promotion

Always-loaded — see `CLAUDE.md` `## Context-Specific Rules`. Pairs with `context-budget.md` (content discipline within always-loaded files); this rule covers location choice across all storage tiers.

## Where knowledge belongs

Knowledge can live in 4 places. Choose by **who needs to read it** and **how stable it is**:

| Location | Audience | Edit cycle |
|---|---|---|
| `~/.claude/projects/.../memory/` | This user, this machine | Per-session writable by Claude |
| `CLAUDE.md` | All contributors, every session | PR-reviewed |
| `.claude/rules/*.md` | All contributors, scoped sessions | PR-reviewed |
| `docs/**` | All contributors, on-demand reading | PR-reviewed |

Memory `feedback_*` / `project_*` / `reference_*` entries belong in `.claude/rules/` (path-scoped if domain-specific) or `CLAUDE.md` (project-wide) when the lesson is **non-obvious and won't be re-derived**. Memory `user_*` always stays in memory.

**Quick test before saving a memory**: *"Would a new contributor with no prior context reliably arrive at the same advice from first principles?"*

- **Yes** → memory (rapid-capture only — the lesson is derivable from code / docs / tooling on demand)
- **No** → `.claude/rules/` or `CLAUDE.md` (the advice is non-obvious and needs to be loaded into context to fire correctly)

**User-preference carve-out**: feedback flavored as personal preference (e.g., "this user wants critic limited to 2/PR") stays in memory regardless of Pastura-specificity — it's `user_*`-flavored even when the trigger event was project work.

## Promotion: memory → rules

Three triggers for considering promotion, ordered by fire-rate reliability:

1. **Periodic triage** (most reliable, user-initiated) — when MEMORY.md size warning fires (>24.4KB index) or every several months, run a full memory triage. Top-N largest memories become promotion candidates.
2. **During `/orchestrate`** (rule-aware bundling) — if the current session created new feedback memories and the active PR is already touching `.claude/rules/`, bundle the rule addition in. Cheaper than a separate cleanup PR.
3. **At memory-save time** (best-effort nudge, expect drift) — for new `feedback_*` saves, apply the quick test above. If it routes to rules, prefer creating a `.claude/rules/` PR alongside (and optionally instead of) the memory entry. The memory is the rapid-capture form; the rule is the durable form.

## Procedure

File a rolling tracking issue collecting candidate sections, then `/orchestrate` a PR that:

1. Lands additions to `.claude/rules/` (or `CLAUDE.md` for project-wide rules).
2. Strips `Source memory: feedback_*` provenance lines from drafts before commit — repo-tracked files referring to per-user memory by name are dead links for other contributors.
3. After PR merges, locally `command rm ~/.claude/projects/.../memory/<source>.md` — the PR can't enforce memory deletion (it's per-user / per-machine); track via the rolling issue checklist.

## Anti-pattern: memory refs in repo-tracked files

Auto-memory at `~/.claude/projects/<workspace>/memory/` is **per-user /
per-machine**. Any reference of the form `` memory `foo.md` `` inside a
repo-tracked file (CLAUDE.md, CONTRIBUTING.md, ADRs, source comments,
script header docs) is a **dead link** for everyone except the
maintainer who wrote the memory.

**Apply** — for rationale in any repo-tracked file, prefer inline summary
+ PR / issue / ADR pointer (`#410`, `ADR-007`, etc.). Memory refs are
acceptable **only** in never-committed places (`~/.claude/CLAUDE.md`,
conversational scratch).

**Detection** — should return 0 hits:

```
rg -n 'memory `[a-z_]+\.md`' --glob '!**/memory/**' --glob '!.git/**'
```

Documented carve-outs exist where inline rationale would be too dense —
see PR #420 for the current carve-out list and the motivating incident.
