# Context Budget — Always-Loaded Files

Always-loaded — see `CLAUDE.md` `## Context-Specific Rules` for the
loading-mode rationale. This rule applies to itself.

## Where knowledge belongs

Knowledge can live in 4 places. Choose by **who needs to read it** and **how stable it is**:

| Location | Audience | Edit cycle |
|---|---|---|
| `~/.claude/projects/.../memory/` | This user, this machine | Per-session writable by Claude |
| `CLAUDE.md` | All contributors, every session | PR-reviewed |
| `.claude/rules/*.md` | All contributors, scoped sessions | PR-reviewed |
| `docs/**` | All contributors, on-demand reading | PR-reviewed |

Memory `feedback_*` / `project_*` / `reference_*` entries that apply to **every Pastura contributor** belong in `.claude/rules/` (path-scoped if domain-specific) or `CLAUDE.md` (project-wide), NOT in memory. Memory `user_*` always stays in memory.

Quick test before saving a memory: *"Would a new contributor running into this same situation benefit from the same advice?"* If yes → rules (or `CLAUDE.md`). If no → memory.

## Promotion: memory → rules

Three triggers for considering promotion:

1. **At memory-save time** — for new `feedback_*` saves, ask the quick test above. Yes → prefer creating a `.claude/rules/` PR instead of (or alongside) the memory entry. The memory is the rapid-capture form; the rule is the durable form.
2. **During `/orchestrate`** — if the current session created new feedback memories and the active PR is already touching `.claude/rules/`, bundle the rule addition in. Cheaper than a separate cleanup PR.
3. **Periodic triage** — when MEMORY.md size warning fires (>24.4KB index) or every several months, run a full memory triage. Top-N largest memories become promotion candidates.

Procedure: file a rolling tracking issue collecting candidate sections, then `/orchestrate` a PR that lands the additions to `.claude/rules/` and deletes the source memory entries. Strip `Source memory: feedback_*` provenance lines from drafts before commit — repo-tracked files referring to per-user memory by name are dead links for other contributors.

## Scope

Always-loaded files (loaded into every agent session / invocation):

- `CLAUDE.md` (project top-level)
- `.claude/rules/*.md` **without** `paths:` frontmatter
- `.claude/agents/*.md`

Path-scoped files (`paths:` frontmatter) load only on matching edits — budget looser there.

## Principle

Each addition must support the agent's **next decision**, not serve as reference material for a human debugging an issue. Reference material belongs in on-demand docs (`docs/**`), script header doc-comments, or PR history.

## Classifier

Before adding, classify each paragraph:

- **Keep**: lead claim + actionable command / path + one-line pointer to deeper doc.
- **Drop or relocate to `docs/**`**: enumerated lists findable via `grep`, performance benchmarks, multi-paragraph rationale, rare-event walkthroughs, anecdotal incident details, historical PR references, repeated file paths.

If a cheat-sheet entry balloons to 3× surrounding entries — or if it would fire correctly with just lead claim + actionable command + pointer — compact it.

## `(#NNN)` historical attribution

- **Drop**: bare parentheticals tagging *which PR introduced something* (e.g., `before xcodebuild ([#293])`).
- **Keep**: pointers directing the next reader *where to find missing context* (e.g., `see #N for the design discussion`).
- Do NOT treat existing inline-`(#NNN)` as precedent. Apply the rule to the new addition AND sweep neighboring violations if cheap.
