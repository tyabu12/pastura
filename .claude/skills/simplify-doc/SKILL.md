---
name: simplify-doc
description: Prune this branch's own added prose — compress or delete self-evident, redundant, or duplicated comments and documentation, with the back-reference, duplicate-claim, and mirror checks that make a deletion safe. Use when the user asks to simplify or compress docs or comments, trim a .claude/rules addition, run a Context-economy pass, or 冗長なコメント / ドキュメントを削る.
allowed-tools: Read, Write, Edit, Grep, Glob, Bash, Agent
argument-hint: "[base-ref | dry-run]"
---

# /simplify-doc

One prune pass over **what this branch added**: enumerate → classify → verify →
apply → review → report.

It exists because the generation-side lever does not work. Comment and prose
volume "tracks the model rather than recency"
(`.claude/rules/knowledge-layering.md` § "Anti-pattern: a comment written for the
reviewer"), so thickening the always-loaded rules that ask for restraint has no
durable effect. The working design is the opposite: let generation be verbose,
and make pruning an explicit pass with its own verification. What this skill adds
over an ad-hoc "delete the redundant bits" prompt is **Step 3** — the checks that
stop a prune from silently breaking something load-bearing.

Skill files are not always-loaded (`.claude/skills/**` is outside both the
footprint sum and the trim-nudge pathspec in
`scripts/hooks/check-claude-md-modified.sh`), so this file costs nothing per
turn. It is not a compression target for its own campaigns.

## What this is not

- **Not the official `/simplify`.** That one reworks *code* for reuse and
  simplification. This one touches prose only — comments, doc comments, markdown.
  They compose; neither substitutes.
- **Not a review gate.** `/code-review` and the `code-reviewer` subagent judge a
  diff against conventions. This judges whether prose earns its place.
- **Not a zero-base sweep.** See Step 1.
- **Not an unattended generator**, so `.claude/rules/automation-output-contract.md`
  does not bind: a human invokes this, watches it, and reviews the commit. It
  queues no artifact into anyone's review backlog.

## Where it runs

On a feature branch, normally just before `/orchestrate` Step 4 so the reviewer
sees the pruned diff. CLAUDE.md § "Implementation Entry Point" carves this skill
out of the `/orchestrate`-only rule; Step 0's guards are what earn that carve-out,
so do not weaken them.

## Step 0 — Preflight (refuse, don't degrade)

1. **Not on the default branch.** `git branch --show-current` must differ from the
   default branch. Abort otherwise — this skill never edits the branch `main`
   protection exists to protect.
2. **Working tree clean.** `git status --porcelain` must be empty. Uncommitted
   changes may belong to a concurrent session in another worktree; a prune that
   commits them attributes another session's work to this one. Abort and report
   what is dirty rather than stashing it.
3. **Resolve the base**: `BASE=$(git merge-base origin/main HEAD)` (or the
   `base-ref` argument). `git fetch origin main` first if the branch is old.
4. If the argument is `dry-run`, stop after Step 2 and report the table.

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

A comment that a reformat merely **reflowed** appears as a `+`/`-` pair with the
same content. It is not new prose; leave it alone.

## Step 2 — Classify each candidate block

`.claude/rules/context-budget.md` (Keep / Drop / relocate) and
`.claude/rules/knowledge-layering.md` (§ "Anti-pattern: a comment written for the
reviewer", § "Where knowledge belongs") own the criteria. **Both are
always-loaded, so they are already in your context** — apply them, do not re-read
or restate them here. Three points they make that this pass most often needs:

- **Volume is the commoner defect, and it is spread across how many blocks you
  write as well as how long each is.** Count before length.
- Past ~10 lines, rewrite once at half length; **the rewrite wins** unless it
  dropped a forward-looking fact.
- A block where *no* sentence states a durable claim — only provenance, the
  diff's own argument, or a figure a canonical site already states — belongs in
  the PR body, not the file.

Produce a table before touching anything: file, block anchor, verdict
(Keep / Compress / Drop / Relocate), and one line of why. Present it. On
`dry-run`, stop here.

## Step 3 — Verify before deleting

The checks below are the reason this skill exists. Each one has cost a real
incident; none is optional, and a zero result from any of them is only
trustworthy after its control has reddened.

### A. Back-references — grep a token that cannot be line-wrapped

Before deleting anything **named** — a section heading, a file path, an
identifier, a table row shape, a marker string — find who cites it. Grep a
**space-free token**: a bare filename, an identifier, an ADR number, or a single
rare word. Never a quoted phrase or a full heading.

This is not a style preference. Measured in this repo: `git grep 'Verify before
you lock it' -- '*.md'` finds three files and **misses the real citation** in
`docs/agent-tooling/claim-verification.md`, because the phrase is hard-wrapped
across two lines. Normalizing whitespace does not fix it either — the
continuation line starts with a `> ` blockquote marker, so a `tr '\n' ' '` pass
still misses it. A space-free token cannot be split across a line break, so the
whole failure mode disappears: `git grep -lw lock` finds every citing file.
Accept the noise. A superset you triage by hand beats a false green on a
deletion.

**Run a positive control before trusting any zero result.** Use the same command
shape against a string you know is cited. If the control does not produce hits,
your command is broken and the zero means nothing —
`.claude/rules/ci-workflows.md` § "`grep` is line-bound" records the same class
of failure from the other direction.

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
  already states the norm: "Fix those upstream in claude-kit, never in the
  mirror." Lines *this branch* added to such a file are in scope only if the
  branch is not itself a reconcile — check its commits before assuming.
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
you measured mid-pass is stale by construction.

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

**If the pass touched `CLAUDE.md`, `.claude/rules/**`, `.claude/agents/**`, or
`.claude/skills/**`, `code-reviewer` alone is not enough.** A conventions gate
has no higher convention to judge against when the artifact under review *is* the
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

**Round 2 runs as a fresh subagent whose prompt carries only the diff and the
file paths — never round 1's output.** A second round that can see the first
reads its own prose instead of the files, and this repo has recorded runs where
three or four consecutive rounds found nothing but errors in text they had
themselves written. **Cap: 2 rounds.** Report what is unresolved rather than
opening a third.

## Step 6 — Commit and report

Commit with `📝 docs:` (or `♻️ refactor:` when the pass restructures rather than
removes), staging explicit paths only.

Report:

- **The arithmetic**: enumerated / kept / compressed / dropped / relocated. An
  uncounted drop is indistinguishable from a candidate never examined.
- **What was not examined** — every file class skipped and why.
- **A ready-to-paste `Context-economy:` line** for the PR body, in the form the
  `gh pr create` nudge asks for:
  `Context-economy: kept N paragraphs, compressed/dropped M — <one-line rationale>`.
- If the pass shrank always-loaded files, the resulting total from
  `scripts/hooks/check-claude-md-modified.sh` § 4's measurement, so the operator
  can judge it. **Do not re-baseline `FOOTPRINT_CEILING_DEFAULT`** — that is a
  slim-campaign duty, and a diff-scoped prune only returns the branch toward its
  own starting point.
