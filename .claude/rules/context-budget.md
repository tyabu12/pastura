# Context Budget — Always-Loaded Files

Always-loaded — see `CLAUDE.md` `## Context-Specific Rules` for the
loading-mode rationale. This rule applies to itself.

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
