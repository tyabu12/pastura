---
name: simplify-doc
description: Prune the prose this branch added — compress or delete self-evident, redundant, or duplicated comments and documentation, behind verification gates that stop a deletion from breaking something load-bearing. Use when asked to simplify or compress docs or comments, trim what a branch added to .claude/rules, run a Context-economy pass, or 冗長なコメント / ドキュメントを削る.
allowed-tools: Read, Write, Edit, Bash, Agent
argument-hint: "[base-ref | dry-run]"
---

# /simplify-doc

One prune pass over **what this branch added**: enumerate → classify → verify →
apply → review → report.

It exists because the generation-side lever does not work: prose volume "tracks
the model rather than recency" (`.claude/rules/knowledge-layering.md`
§ "Anti-pattern: a comment written for the reviewer"), so thickening the
always-loaded rules that ask for restraint has no durable effect. Let generation
be verbose and make pruning an explicit pass instead. What this adds over an
ad-hoc "delete the redundant bits" prompt is **Step 3** — the checks that stop a
prune from silently breaking something load-bearing.

This file's **body** is not always-loaded — `.claude/skills/**` is in neither the
trim-nudge nor the footprint pathspec of
`scripts/hooks/check-claude-md-modified.sh` — so it costs nothing per turn and is
not a compression target for its own campaigns. The frontmatter `description:` is
the exception, in both directions: it sits in every session's skill listing so it
*is* paid per turn, and it is the routing surface, where a dropped trigger word
silently stops the skill being selected and raises no error. Compress it only
against that trade.

## What this is not

- **Not the official `/simplify`.** That one reworks *code* for reuse and
  simplification. This one touches prose only — comments, doc comments, markdown.
  They compose; neither substitutes.
- **Not a review gate.** `/code-review` and the `code-reviewer` subagent judge a
  diff against conventions. This judges whether prose earns its place.
- **Not a zero-base sweep.** See Step 0 item 5 and Step 1.
- **Not an unattended generator**, so `.claude/rules/automation-output-contract.md`
  does not bind: a human invokes this, watches it, and reviews the commit. It
  queues no artifact into anyone's review backlog.

## Where it runs

On a feature branch, normally just before `/orchestrate` Step 4 so the reviewer
sees the pruned diff. CLAUDE.md § "Implementation Entry Point" carves this skill
out of the `/orchestrate`-only rule and states the grounds. The three revocable
guards the carve-out names — Step 0's two refusals, and Step 4's explicit-path
staging — are the rest of the grant, so do not weaken them.

## Step 0 — Preflight (refuse, don't degrade)

1. **Not on the default branch.** `git branch --show-current` must differ from the
   default branch. Abort otherwise — this skill never edits the branch `main`
   protection exists to protect.
2. **Working tree clean.** `git status --porcelain` must be empty. Uncommitted
   changes may belong to a concurrent session in another worktree; a prune that
   commits them attributes another session's work to this one. Abort and report
   what is dirty rather than stashing it. This is a point measurement — Step 6
   re-checks before staging.
3. **Resolve the base.** Any argument that is not the literal `dry-run` is a
   base-ref and becomes `BASE`; with no argument, `git fetch origin main` then
   `BASE=$(git merge-base origin/main HEAD)`. **Abort if the fetch fails** — a
   stale `origin/main` passes every later check while moving the merge-base
   back, so the population silently gains prose other branches already merged
   to main: exactly the scope creep Step 1 forbids, in its quietest form.
   Either way validate the result before using it —
   `git rev-parse --verify "$BASE^{commit}"` — and abort on failure, so a typo
   fails here rather than as a raw git error in Step 1.
4. If the argument is `dry-run`, stop after Step 2 and report the table.
5. **If the request reads as zero-base** — "make `.claude/rules` carry only what
   it needs", or it names files this branch never touched — say so *before*
   starting, and offer the choice: diff-scoped now, diff-scoped plus a named
   follow-up campaign, or stop. Silently narrowing the ask is the failure mode
   here; the maintainer's habitual phrasing for this task often reads zero-base.

## Step 1 — Enumerate the population, then scope

Do not name files from memory or from what you happen to have open. Enumerate
first — a tool's output is a by-product of what you asked, not the population.

```bash
git diff --numstat "$BASE"...HEAD          # every file with added lines
```

Everything with a non-zero added count is a candidate; nothing else is in scope.
**Only lines this branch ADDED.** Pre-existing prose is out of scope even when it
is obviously worse than what you are pruning — that is a separate, deliberate
campaign, and mixing the two makes the diff unreviewable.

Two boundaries the diff alone will not settle:

- A `+`/`-` pair with **identical** content is a reflow — not new prose, leave
  it. A pair whose content **changed** is a rewrite, and its substance predates
  this branch: out of scope unless the branch authored the claim it now makes.
- A **whole new file** gets a file-level verdict first — does this belong in
  this tier at all (`knowledge-layering.md` § "Where knowledge belongs")? Check A
  is vacuous for one: nothing can cite what did not exist.

Split the candidates into three classes and enumerate each:

```bash
# agent-instruction files (strictest budget)
git diff --numstat "$BASE"...HEAD -- CLAUDE.md .claude/rules .claude/agents .claude/skills

# code comments — list them with their file/hunk context
git diff -U0 "$BASE"...HEAD -- '*.swift' '*.kt' '*.sh' '*.py' \
  | grep -E '^(\+\+\+|@@|\+[[:space:]]*(///|//|#|\*))'

# prose
git diff --numstat "$BASE"...HEAD -- docs README.md CONTRIBUTING.md
```

**The three classes are pathspecs, so they do not partition the population.**
Compute the remainder — every file the Step 1 `--numstat` names that none of
the three class commands matched (a YAML comment under `Resources/`, `web/`
prose, a CI workflow) — and carry it **by name** into Step 6's "not examined"
report. Without this a candidate in no class is invisible: it is not a skipped
file class, because it was never in one.

`.claude/skills/**` is in the first list so a prune can see it, but it is
budgeted per *invocation*, not per turn — apply the classifier there at a looser
bar than to a genuinely always-loaded file.

## Step 2 — Classify each candidate block

`.claude/rules/context-budget.md` (Keep / Drop / relocate) and
`.claude/rules/knowledge-layering.md` (§ "Anti-pattern: a comment written for the
reviewer", § "Where knowledge belongs") own the criteria, and both are
always-loaded — they are already in your context, so read them there rather than
re-deriving them. Weight three of theirs highest, because they are the ones a
prune gets wrong: count-before-length, the half-length rewrite past ~10 lines,
and the "no durable claim" test. Read those three at the source, not off this
sentence — each carries an exception that licenses a **Keep**, and an abbreviated
restatement here drops exactly those.

Produce a table before touching anything: file, block anchor, verdict
(Keep / Compress / Drop / Relocate), and one line of why. Present it. On
`dry-run`, stop here.

## Step 3 — Verify before deleting

The checks below are the reason this skill exists — back-references, duplicate
claims, mirrors, self-quoted numbers, machine-parsed prose. Each one has cost a
real incident; none is optional, and a zero result from any of them is only
trustworthy after its control has reddened.

### A. Back-references — grep a token that cannot be line-wrapped

Before deleting **or renaming** anything named — a section heading, a file path,
an identifier, a table row shape, a marker string — find who cites it. A rename
is a deletion plus an addition, so run this check on the **old** name; a retitled
heading breaks every back-reference while never looking like a deletion.

Grep a **space-free token**: a bare filename, an identifier, an ADR number, or a
single rare word. Never a quoted phrase or a full heading. Measured in this repo:
`git grep -l 'Verify before you lock it' -- '*.md'` does **not** list
`docs/agent-tooling/claim-verification.md`, which cites that section — the phrase
is hard-wrapped there. Normalizing whitespace (`tr '\n' ' '`) recovers that one
but not a wrap whose continuation line carries a `> ` blockquote marker, as
`knowledge-layering.md:6-7` does. A space-free token needs neither pass:
`git grep -lw lock` lists every citing file.

**Pick the rarest space-free token, not the first, and enumerate the result.**
Noise is the cost of the technique: `-lw lock` returns tens of files for a
heading cited from a handful, and for one whose distinctive words are all common
(`reviewer`) it is worse. **If the result set is too large to enumerate, that IS
the verdict: Keep**, or narrow with a second token. Never delete against a
superset you did not read. Same shape as check B — unproven ⇒ Keep.

**Run a positive control before trusting any zero result, and put the control in
the target's habitat**: a string cited from the same file class, in the wrapped
form you are worried about. A control that merely matches the pattern proves your
command has no typo and nothing else. `.claude/rules/ci-workflows.md` § "`grep`
is line-bound" records the same class of failure from the other direction.

### B. "This is a duplicate" is a claim, not an observation

Any verdict resting on "this already lives in X", "this is covered by Y", or
"this is redundant with Z" must be proven: `git grep` a space-free token from the
supposed other site, and confirm it actually says what you claim. **Historically
this claim is usually false.** Unproven ⇒ Keep.

### C. Mirrors and pairs

- **claude-kit mirrors — their shared core is out of scope entirely.** Enumerate
  them; do not work from a remembered list:

  ```bash
  git grep -l 'Derived from \[claude-kit\]'
  ```

  Reconciliation is one-way kit → Pastura, so compressing the shared core here
  makes the next reconcile read relocated text as deletions. CONTRIBUTING.md
  § "The claude-kit plugin" already states the norm: fix those upstream in
  `claude-kit`, never in the mirror. Lines *this branch* added to such a file are
  in scope only if the commit that added them is not itself a reconcile; resolve
  that per commit, not per branch.
- **Rule ↔ paired doc.** `subagent-usage.md` ↔
  `docs/agent-tooling/subagent-output-cap.md`, `knowledge-layering.md` ↔
  `docs/agent-tooling/claim-verification.md`. Each pair says to reconcile the
  two together; compressing one side alone makes them disagree.
- **CLAUDE.md ↔ README / CONTRIBUTING**, per CLAUDE.md § "Reference Documents".
  Note that § Development Workflow is **not** in the hook's mirrored-section
  list, so no nudge fires for it — check by hand.

### D. Numbers a file states about itself

If a file you compressed quotes its own size, line count, or a count of
something this pass changed, **re-measure on the final commit**
(`.claude/rules/knowledge-layering.md` § "Verify before you lock it"). The figure
you measured mid-pass is stale by construction — and a sentence that documents a
grep can itself satisfy that grep, so pin such a count with a self-excluding
pathspec or omit the number entirely.

### E. Some prose is parsed

Treat these as code, not prose. Each fails **open**, so breaking one costs no
error — only silence:

- **`CLAUDE.md`'s ADR roster** must stay one line alone in its paragraph, and the
  ADR-006 reservation row needs all three conjuncts of its table row. Both are
  read by `.claude/skills/consistency-audit/scripts/audit_docs.py`; a reflowed
  roster makes it skip per-ADR drift detection entirely.
- **A `.claude/rules/*.md` `paths:` block.** Compressing it changes what the rule
  fires on, *and* re-tiers the file in the trim nudge and footprint sum — both
  decide always-loaded vs path-scoped by looking for a `^paths:` line in the
  file's **first 14 lines only**, so padding the frontmatter past that window
  re-tiers the file as surely as deleting the block. A rules file whose
  frontmatter is touched also needs re-probing
  (`knowledge-layering.md` § "A rules file created mid-session never injects in
  that session").

`/consistency-audit` catches roster damage only after the fact — it is a
generator, not a gate.

## Step 4 — Apply

- **Move whole blocks, never clauses.** A backward-looking sentence is routinely
  what makes the forward rule intelligible; deleting it alone leaves a rule
  nobody can act on.
- **Compression is rewriting, so the old ledger stops applying.** After
  rewriting a block, re-check its own claims — an assertion that survived the
  rewrite in shortened form is a new assertion.
- **Grep the old shape after any bulk substitution** (CLAUDE.md § "Scope &
  Completeness Discipline"). A byte-exact multi-site replace silently skips
  occurrences differing only in indentation, and still reports success.
- **Stage explicit paths. Never `git add -A` or `git add -u`** — a concurrent
  Xcode session re-serializes `*.xcstrings`, and a broad add commits phantom keys
  under this pass's name.
- **Record a shortfall; never invent cuts to reach a number.** The realistic
  landing is far below what a first read makes it look like. "Examined 14 blocks,
  kept 11" is a complete and successful outcome.

## Step 5 — Review

Round 1: `code-reviewer` on the branch diff.

**If the pass touched `CLAUDE.md`, `.claude/rules/**`, `.claude/agents/**`,
`.claude/skills/**`, or any file whose comments guard a test assertion or a gate
(`scripts/**`), `code-reviewer` alone is not enough.** A conventions gate has no
higher convention to judge against when the artifact under review *is* the
conventions — a structural blind spot, not a quality one. Add
`/claude-kit:risk-review` (preferred; confirm the namespaced name resolves), or
fall back to `claude-kit:critic` — which CLAUDE.md § "Agent Tooling Dependency"
already declares as a hard dependency — with these axes stated explicitly:

1. Did a deletion remove the **only** statement of a norm, or its only worked
   example?
2. Does any surviving text now cite something this pass deleted?
3. Did a compression change what a rule **fires on** while appearing only to
   shorten it?
4. Is a mirrored pair now inconsistent?
5. Did the pass delete backward-looking prose that was making a forward rule
   intelligible?
6. Did a deletion remove the only warning protecting a fragile coupling? Check A
   protects what is *cited*; a comment nobody cites is invisible to it.

**Round 2 runs as a fresh subagent whose prompt carries only the diff and the
file paths — never round 1's output.** A second round that can see the first
reads its own prose instead of the files, and this repo has recorded runs where
three or four consecutive rounds found nothing but errors in text they had
themselves written. **Cap: 2 rounds.** Report what is unresolved rather than
opening a third.

## Step 6 — Commit and report

Immediately before staging, re-run `git status --porcelain` and confirm every
dirty path is one this pass edited — Step 0's check was a point measurement and a
concurrent session can dirty the tree mid-run. Then read `git diff --cached` and
confirm the staged content is what the Step 2 table approved. Commit with
`📝 docs:` (or `♻️ refactor:` when the pass restructures rather than removes),
staging explicit paths only.

Report:

- **The arithmetic**: enumerated / kept / compressed / dropped / relocated. An
  uncounted drop is indistinguishable from a candidate never examined.
- **What was not examined** — every file class skipped, Step 1's class
  remainder, and anything the request asked for that Step 0 item 5 put out of
  scope.
- **A ready-to-paste `Context-economy:` line** for the PR body, in the form the
  `gh pr create` nudge asks for:
  `Context-economy: kept N paragraphs, compressed/dropped M — <one-line rationale>`.
- If the pass shrank always-loaded files, the resulting total from
  `scripts/hooks/check-claude-md-modified.sh` § 4's measurement, so the operator
  can judge it. **Do not re-baseline `FOOTPRINT_CEILING_DEFAULT`** — that is a
  slim-campaign duty, and a diff-scoped prune only returns the branch toward its
  own starting point.
