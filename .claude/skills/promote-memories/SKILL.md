---
name: promote-memories
description: Triage per-user memory — promote durable entries into .claude/rules/ AND retire (delete/trim) SHIPPED trackers — select candidates, classify, draft at concept level, self-check, hand off to /orchestrate for the promotion PR.
allowed-tools: Read, Grep, Glob, Bash, Write, Edit, Agent
argument-hint: "[focus cluster | (empty for full triage)]"
---

# /promote-memories

Run a memory triage round — **promote** durable lessons to rules and
**retire** (delete/trim) SHIPPED trackers. The **canonical procedure lives
in `.claude/rules/knowledge-layering.md`** (§ Where knowledge belongs,
§ Promotion & retirement, § Procedure, § Rule-writing self-check) — read it
first and follow it as the source of truth. This skill adds only the
operational steps around that procedure; if the two ever disagree, the rule
wins.

Typical trigger: total memory files >80 or total content >~250KB (see
knowledge-layering § Promotion & retirement), or a user-requested periodic
triage. `$ARGUMENTS` may name a focus cluster (e.g. "xcstrings", "kmp") to
skip the full triage.

## Step 1: Triage

1. Size-rank the memory files:
   ```bash
   ls -S ~/.claude/projects/<workspace>/memory/*.md | xargs wc -c | sort -rn | head -25
   ```
2. For each candidate, apply knowledge-layering.md's quick test
   ("would a new contributor re-derive this?") and its user-preference
   carve-out (`user_*`-flavored feedback stays in memory).
3. **Classify each into a disposition** — run the promotion quick-test
   *first*, so one memory can be both promoted and then retired:
   - **PROMOTE** — durable, non-derivable lesson → extract to rules (Steps 2-4).
   - **DELETE** — a `project_*` tracker whose work has fully SHIPPED (no open
     items, outcome now derivable from code/git/docs) → retire the file.
     Extract any durable lesson via PROMOTE first, then delete the residue.
   - **TRIM** — shipped bulk plus a few live items → rewrite to the
     open-tracking stub, keeping only the open work.
   - **KEEP** — active tracking with open work → leave as-is.
4. For **PROMOTE** candidates: cluster by target rules file (prefer
   path-scoped; always-loaded targets route through
   `.claude/rules/context-budget.md`'s classifier first), and **grep the
   target before drafting** — entries may already be partially covered;
   promote only the delta. Defer clusters whose target file does not exist yet.
5. Present the disposition slate to the user (PROMOTE / DELETE / TRIM / KEEP,
   with reasons; defer + tracking-issue note where relevant). Wait for
   approval. Then: **PROMOTE** → Steps 2-4 (rules PR); **DELETE / TRIM** →
   operate on memory directly in-session (per-user, no PR needed; on DELETE,
   prune the file's MEMORY.md index line and fix any `[[wikilink]]` that
   pointed to it).

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
   <200 chars each) — this relieves the built-in >24.4KB *index* warning
   specifically; the primary triage triggers, though, are file-count +
   content-size (knowledge-layering § Promotion & retirement), which
   retirement (DELETE / TRIM) addresses directly.
3. Re-check the triage triggers (file-count / content-size). If still over,
   queue the next round from the deferred clusters recorded in the tracking issue.
