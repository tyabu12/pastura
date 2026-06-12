---
name: promote-memories
description: Triage per-user memory and promote durable entries into .claude/rules/ — select candidates, draft at concept level, self-check, and hand off to /orchestrate for the PR.
allowed-tools: Read, Grep, Glob, Bash, Write, Edit, Agent
argument-hint: "[focus cluster | (empty for full triage)]"
---

# /promote-memories

Run a memory → rules promotion round. The **canonical procedure lives in
`.claude/rules/knowledge-layering.md`** (§ Where knowledge belongs,
§ Promotion, § Procedure, § Rule-writing self-check) — read it first and
follow it as the source of truth. This skill adds only the operational
steps around that procedure; if the two ever disagree, the rule wins.

Typical trigger: the MEMORY.md size warning (>24.4KB index), or a
user-requested periodic triage. `$ARGUMENTS` may name a focus cluster
(e.g. "xcstrings", "kmp") to skip the full triage.

## Step 1: Triage

1. Size-rank the memory files:
   ```bash
   ls -S ~/.claude/projects/<workspace>/memory/*.md | xargs wc -c | sort -rn | head -25
   ```
2. For each candidate, apply knowledge-layering.md's quick test
   ("would a new contributor re-derive this?") and its user-preference
   carve-out (`user_*`-flavored feedback stays in memory).
3. Cluster candidates by target rules file. Prefer path-scoped targets;
   additions to always-loaded files route through
   `.claude/rules/context-budget.md`'s classifier first.
4. **Grep the target rules file before drafting** — entries may already be
   partially covered; promote only the delta. Defer clusters whose natural
   target file does not exist yet (e.g. a layer that hasn't landed on main).
5. Present the slate to the user: promote now / defer (with the reason and
   a tracking-issue note) / keep in memory. Wait for approval.

## Step 2: Draft

- **Concept register** — compress the narrative, keep the invariant and a
  pointer. But PRESERVE non-derivable negative claims verbatim in spirit:
  anti-pattern / "wrong fixes" lists, crash-class disambiguations,
  "don't do X" caveats. Those are usually the entire value of the memory.
- Strip per-user provenance and memory references per knowledge-layering.md
  (§ Procedure step 2, § Anti-pattern).
- Mirror-sync per § Procedure step 3 (code-reviewer cheat sheet, CLAUDE.md
  parentheticals).

## Step 3: Self-check (before handing off)

Execute every load-bearing assertion in the drafts per knowledge-layering.md
§ Rule-writing self-check — against the current state of `main`, not the
memory's snapshot:

- `gh pr view N` for every `(PR #N)` cite. Annotate CLOSED / reverted PRs
  as such in the draft (a future self-check must not mistake CLOSED for a
  broken cite); prefer adding the durable home (ADR, issue) alongside.
- Run every grep / path / line-anchor the draft asserts. Memories age:
  bundle IDs get renamed, files move, spike-branch facts never landed on
  main. Reframe the draft to match observed state.

## Step 4: PR via /orchestrate

This skill does not edit repo files itself. Hand the approved slate +
drafts to `/orchestrate` (issue, worktree, commits, review, PR). The
reviewer is Opus — `.claude/rules/**` is an Opus-required path.

## Step 5: Post-merge local cleanup (operator checklist)

Gate: `gh pr view <N> --json state` reports `MERGED`. Then **print** this
checklist — never execute the deletions yourself:

1. Deletion list, one `command rm` line per promoted memory file
   (`command rm` because the operator's interactive `rm` is aliased to
   `rm -i` and silently no-ops in non-interactive shells). Show the list
   for confirmation before the operator runs it.
2. Shorten remaining over-long MEMORY.md index lines (one line,
   <200 chars each) — index-line length, not file count, drives the
   >24.4KB warning, so this is the primary size-relief action.
3. Re-check MEMORY.md size. If still over the limit, queue the next round
   from the deferred clusters recorded in the tracking issue.
