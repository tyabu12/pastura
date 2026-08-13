# Context Budget — Always-Loaded Files

> Derived from [claude-kit](https://github.com/tyabu12/claude-kit) `rules/context-budget.md` —
> the generic core is canonical there; reconcile one-way (kit → Pastura) — rule-to-rule here, since
> this one is concept level with no volatile facts and no paired kit `docs/` file. Pastura-specific
> content lives only in this copy.

Always-loaded — see `CLAUDE.md` `## Context-Specific Rules` for the
loading-mode rationale. This rule applies to itself. Pairs with `knowledge-layering.md` (location choice across memory / rules / `CLAUDE.md` / `docs/**`); this rule covers content discipline within always-loaded files.

## Scope

Always-loaded files (loaded into every agent session / invocation) — every line is paid on every turn:

- `~/.claude/CLAUDE.md` and `~/.claude/rules/*.md` **without** `paths:` frontmatter (global — per-user, yet charged to *this* project's every session)
- `CLAUDE.md` (project top-level) and `.claude/rules/*.md` **without** `paths:`
- `~/.claude/agents/*.md` and project `.claude/agents/*.md`

The global tier is easy to forget because it is not in this repo — and a global file duplicating a
project file of the same name is paid **twice**.

Path-scoped files (`paths:` frontmatter) load only when a matching path is read — budget looser there.

## Principle

Each addition must support the agent's **next decision**, not serve as reference material for a human debugging an issue. Reference material belongs on-demand: `docs/**`, script header doc-comments, PR / issue history.

## Classifier

Before adding, classify each paragraph:

- **Keep**: lead claim + actionable command / path + one-line pointer to deeper doc.
- **Drop or relocate to `docs/**`**: enumerated lists findable via `grep`, performance benchmarks, multi-paragraph rationale, rare-event walkthroughs, anecdotal incident details, historical PR references, repeated file paths.

If a cheat-sheet entry balloons to 3× surrounding entries — or if it would fire correctly with just lead claim + actionable command + pointer — compact it.

## `(#NNN)` / issue attribution

- **Drop**: bare parentheticals tagging *which PR or issue introduced something* (e.g., `before xcodebuild ([#293])`).
- **Keep**: pointers directing the next reader *where to find missing context* (`see #N for the design discussion`, `ADR-007`).
- Do NOT treat existing inline-`(#NNN)` as precedent. Apply the rule to the new addition AND sweep neighboring violations if cheap.
