# `/orchestrate` ↔ claude-kit template — reconciliation ledger

Paired with the `generated-from:` stamp at the top of
[`.claude/skills/orchestrate/SKILL.md`](../../.claude/skills/orchestrate/SKILL.md). The skill keeps
the stamp and a three-line pointer; this file holds the ledger, so the enumeration is not paid on
every `/orchestrate` invocation (`.claude/rules/context-budget.md`). Read it when
`/claude-kit:orchestrate-creator` proposes a back-port — that is the only moment it fires.

## Why the stamp exists

Pastura's `/orchestrate` predates `/claude-kit:orchestrate-creator` and was never generated from its
template. Without a stamp, Step U-1 classifies the file as hand-written and produces a read-only
report, so no template improvement can ever reach it. That is why the routing redesign (kit#19/#23)
sat unapplied for a generation: kit deliberately leaves *suboptimal-but-not-wrong* changes to ride
along on each project's next upgrade run, and Pastura's never fired. The stamp records the template
revision the content was last reconciled with — a reconcile, not a generation — so a re-run reaches
Step U-3's principle-level proposals. Background: #1453.

**Step U-4 rewrites the stamp line on every upgrade.** Nothing that must survive can live in it.

## Read "up to date" narrowly

Step U compares hashes first. An unchanged template reports "up to date", which means *no template
change since the reconcile* — **not** that this file matches the template. It deliberately does not.

## The ledger

**This list is hand-maintained and nothing prompts an author to append to it.** No hook fires on
`.claude/skills/orchestrate/SKILL.md`, no `/consistency-audit` detector reads the stamp, no test
asserts these entries. An entry may also be stale — a *correction* entry goes false the moment
upstream fixes the defect. So judge a back-port proposal on its merits; this list's silence is not
evidence that a change is safe. (Same posture CLAUDE.md takes for the ADR roster.)

Most divergences are **additions**, which an upgrade proposal cannot silently undo. The entries
below are the ones a plausible-sounding back-port *would* undo.

### Adaptations — stable, no retirement condition

1. **Step 1.3's "do not add a blanket 'when in doubt, go up a tier'" guardrail is not in the
   template's Step 1.** A *negative* instruction: nothing around it looks wrong once it is gone, and
   it is the direct fix for the defect this file was reconciled to repair. Reject any proposal to
   adopt the template's Step 1 wording that drops it.
2. **The Step 4 reviewer prompt omits the template's selective `.claude/rules/*.md` read.**
   `.claude/agents/code-reviewer.md`'s Review Process step 3 owns that logic here. Do not add it in
   both places — but if that agent ever loses it, this prompt must gain it, or path-scoped review
   coverage vanishes silently.
3. **The Step 3 🎵 prompt roots paths at `{WORKTREE_ROOT}` but does *not* adopt the template's "run
   tests/git via `-C {WORKTREE_ROOT}` (or `cd` there first)".** `-C` applies to `git` only;
   `scripts/xcodebuild.sh` must stay a bare cwd-relative call, because a `cd … &&` prefix, an
   absolute path, or a leading env assignment misses the allowlist entry and stalls the delegated
   subagent on an approval prompt (`.claude/rules/xcodebuild-cli.md` § "Canonical invocation"). The
   template's stronger-sounding wording would reintroduce that stall. Reasoning is inline in the
   skill next to the 🎵 prompt.
4. **The template's inlined subagent output-cap / split-budget note is omitted, and its "Project
   parameters (baked at generation)" table has no counterpart.** `.claude/rules/subagent-usage.md`
   is always-loaded here, so inlining pays twice per turn (`.claude/rules/context-budget.md`); and
   this file's parameters are inline at each step and richer than the table's cells.

### Corrections — delete the entry once upstream lands

A correction of a template *defect* is reported upstream and its entry names the tracking issue and
dies with it. That keeps this category from growing without bound.

5. **Pre-flight check 3's degraded-mode `DEFAULT_BRANCH` fallback deliberately differs from the
   template's.** The template's `git symbolic-ref refs/remotes/origin/HEAD` returns
   `refs/remotes/origin/main` — a full ref, not a branch name — which breaks the `git fetch`,
   `git rev-list`, `git pull`, and `git switch` that consume it. Do not adopt the template's shorter
   form. **Upstream: [claude-kit#34](https://github.com/tyabu12/claude-kit/issues/34). Delete this
   entry once that lands and the template is re-reconciled.**

## Known gaps, tracked elsewhere

- `.claude/agents/code-reviewer.md` runs its own `git diff HEAD` and `head -14 .claude/rules/*.md`
  cwd-relative; the Step 4 prompt roots only the diff. On a branch editing `.claude/rules/**`, a
  reviewer whose cwd resolved to the main checkout would sweep the pre-change rule set.
- `.claude/rules/xcodebuild-cli.md`'s "the allowlist match is on the literal command prefix" is
  unscoped and reads as a claim about the matcher generally; `git -C <path> diff` has been observed
  to run unprompted under an equally bare `Bash(git diff*)`. The narrower "Both are exact-prefix
  literal matches" a few lines above is correctly bound to its two named entries.
