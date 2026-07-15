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
3. If the promoted content is mirrored elsewhere — the code-reviewer trap cheat sheet (`.claude/agents/code-reviewer.md`), a CLAUDE.md summary parenthetical — update every mirror in the same PR. Mirrors drift silently otherwise (e.g., swift-isolation gained Pattern 5 while two "4 traps" enumerations stayed behind).
4. After PR merges, locally `command rm ~/.claude/projects/.../memory/<source>.md` — the PR can't enforce memory deletion (it's per-user / per-machine); track via the rolling issue checklist.

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

**Detection** — new code must not add hits to this grep:

```
rg -n 'memory `[a-z_]+\.md`' --glob '!**/memory/**' --glob '!.git/**'
```

Known carve-outs (where inline rationale would be too dense to migrate):

- `Pastura/Pastura/Views/Components/ThoughtVisibilityToggle.swift` —
  ShapeStyle vs Color token trap rationale
- `Pastura/PasturaTests/App/LaunchPhaseCoordinatorTests.swift` —
  CI wallclock test bound rationale

See PR #420 for the motivating incident. Long-term, both carve-outs
should migrate to inline rationale or a public doc home.

## Rule-writing self-check

When adding a `.claude/rules/` section (or `CLAUDE.md` content) that includes an **executable assertion** — a grep command with an asserted hit count, a cited `file:line`, a `(PR #N)` claim, a cross-doc heading anchor — execute it against current main state **before commit**.

Pre-impl critic and code-reviewer reviews have repeatedly missed this class: they evaluate the *content* of the rule but rarely run the *check* the rule itself prescribes. The writer is the only one who reliably can.

The same "verify before you lock it" discipline extends past rule assertions to **any load-bearing claim a plan leans on**, checked **before plan-lock (Step 1b critic)**. `critic`'s axes are codebase-internal (dependency rules, phase scope, integration risk), so a claim that is *externally* false but internally plausible passes critic and surfaces only at code-review or in production — the plan author is the one positioned to check. Verify each against its authoritative source:

| Claim a plan leans on | Verify by |
|---|---|
| A header/doc comment asserting cross-file structure ("defined in M", "consumable by Y") | grep the actual symbol/type — comments can be aspirational, not descriptive |
| A `§"Heading"` cross-doc reference | grep the target for the exact heading **and read under it** to confirm the content matches; add a named heading if absent |
| "band-aid / hack / dead code" framing of a change | grep ALL producers + consumers across layers (esp. Engine/runtime), not just the layer the issue scopes — the target may be load-bearing |
| An external standard (SEO, RFC, sitemap/robots, OAuth, HTTP semantics) | WebSearch + WebFetch the authority (Google Search Central, the RFC, MDN); verbatim-cite before critic |
| Vendor feature availability (free/paid/plan tier) | WebFetch the canonical docs; verbatim-quote the "Who can use this feature" box — never infer from search snippets |

### Apply

For each load-bearing assertion in the draft:

1. Paste the command (`rg`, `find`, `gh pr view`) into Bash from the current worktree.
2. Compare observed output to what the rule asserts.
3. Reconcile divergence one of three ways:
   - **Sweep** — fix the violations in this PR if cheap.
   - **Reframe** — change the assertion to match observed state. The "Anti-pattern: memory refs" section above is itself an example: "new code must not add hits" + an inline carve-out list, rather than "should return 0 hits".
   - **Inline carve-out** — enumerate existing violations with `file:line`.

This applies to **non-grep claims** too: cited file paths (`find` to confirm existence), `(PR #N)` claims about PR body content (`gh pr view N` to verify), heading anchors in cross-doc refs (`grep` for the exact heading).

A 30-second self-check prevents 1–2 extra critic / code-reviewer rounds. Motivating incident: PR #462 round-3 critic.
