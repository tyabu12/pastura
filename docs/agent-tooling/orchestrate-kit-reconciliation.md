# `/orchestrate` ↔ claude-kit template — reconciliation ledger

Paired with the `generated-from:` stamp at the top of
[`.claude/skills/orchestrate/SKILL.md`](../../.claude/skills/orchestrate/SKILL.md). It is read at one
moment: when `/claude-kit:orchestrate-creator` proposes a back-port.

## Why the stamp exists

Pastura's `/orchestrate` predates the creator and was never generated from its template. Without a
stamp, Step U-1 classifies the file as hand-written and only reports, so no template improvement
could reach it. The stamp records the template revision the content was last *reconciled* with.
**Step U-4 rewrites the stamp line on every upgrade**, so nothing durable lives in it; and Step U
compares hashes first, so its "up to date" means *no template change since the reconcile* — not that
the file matches the template. It deliberately does not.

## The ledger

Hand-maintained; no hook or audit reads it, so judge a back-port on its merits — silence here is not
evidence that a change is safe. Most divergences are additions, which a proposal cannot silently
undo. The entries below are the ones a plausible-sounding back-port *would* undo.

### Adaptations — stable, no retirement condition

1. **The Step 4 reviewer prompt omits the template's selective `.claude/rules/*.md` read.**
   `.claude/agents/code-reviewer.md` Review Process step 3 owns that logic here — do not add it in
   both places. If that agent ever loses it, this prompt must gain it, or path-scoped review coverage
   vanishes silently.
2. **The Step 3 prompt roots paths at `{WORKTREE_ROOT}` but does not adopt the template's "run
   tests/git via `-C {WORKTREE_ROOT}` (or `cd` there first)".** `-C` is git-only; a `cd` prefix
   takes `scripts/xcodebuild.sh` off the allowlist and stalls the subagent on an approval prompt
   (`.claude/rules/xcodebuild-cli.md`).
3. **The template's inlined subagent output-cap / split-budget note is omitted.** The budget lives
   in `.claude/agents/code-reviewer.md` (mirrored from `docs/agent-tooling/subagent-usage.md` §2),
   and Pastura's counts **added** lines where the template counts changed lines — adopting the
   template's note would reintroduce changed-line counting and re-shard deletion-heavy PRs.
4. **Step 4 is one review round, not the template's review-verify-fix loop** (verify agent + scoped
   re-review × 3). Reviewer → main-session triage → one fix → at most one fix-diff re-review; no
   verification subagent; rejected findings go to the PR body's `## Review`. Decided in #1519: a
   round ≥ 2 on self-authored prose attacks the previous round's fix prose at ~100k tokens a round.
   A back-port of the template's Step 4 reinstates the loop.
5. **Step 5 passes the PR body with `--body-file`, never the template's inline heredoc** — the
   push-protection hook's body scan trips on an inline heredoc (CLAUDE.md § Git Conventions).
6. **Step 1 routes on two axes — *tier* (`🎵` Sonnet / `🎭` `🧠` Opus) and *locus* (`🎵`
   `🎵 (tb)` `🎭` delegated / `🎵 (main)` `🧠` in-session) — where the template's one two-icon
   label decides both at once.** Step 3 gains a `🎭` branch dispatching `claude-kit:implementer` at
   Opus. This diverges from a deliberate upstream design (kit#19/#23), not a defect; if the
   template ever adopts a split, reconcile against it rather than deleting. The template has no
   `(tb)` marker, so adopting its Step 1 wording disarms the two gates that consume it (Step 1.3's
   strictly-simple reviewer test and Step 0's all-Sonnet-tier re-check).

   Two accepted consequences: `claude-kit:implementer` pins `effort: medium`, so a `🎭` item runs
   at Opus/medium (escalate to a general Opus subagent if fix rounds rise); and `🎵 (main)` keeps
   its Sonnet tier where the template promotes in-session work to `🎭`.

   **Sunset clause.** The split exists to move work off the main context; before it, 88% of plan
   items were in-session. After ~10 `/orchestrate` runs from 2026-08-21, count labels across those
   plan comments (`gh api repos/tyabu12/pastura/issues/<N>/comments --jq '.[].body'`, keep bodies
   with the plan marker, `grep -o -F` per icon) and `claude-kit:implementer` invocations (OTel). If
   the `🧠` share is still ≥ 80% and implementer calls ≈ 0, revert Step 1.2 to the template's
   two-icon label by deleting the table — add no prose.

   **Break-even.** A delegation's fixed cost is ≈ 52k tokens (2026-08-21: one-turn, zero-tool Haiku
   subagent, harness included; measured before #1520 cut always-loaded 91 → 29 KB, so re-measure).
   An in-session item instead leaves its tool output `X` in the main context, re-read from cache on
   every later turn. At ~10% cache-read pricing and ~20 remaining turns, in-session costs ≈ 3X and
   delegation ≈ 52k + X, so delegation is cheaper in tokens only when X ≳ 25k — about three or four
   mid-size Swift files read plus a test run. Below that, `🎵 (main)` / `🧠` is cheaper; what
   delegation buys there is peak-context headroom, not dollars.

### Corrections — delete the entry once upstream lands

7. **Pre-flight check 3's degraded-mode `DEFAULT_BRANCH` fallback differs from the template's.**
   The template's `git symbolic-ref refs/remotes/origin/HEAD` yields a full ref, which breaks the
   `git fetch` / `rev-list` / `pull` / `switch` that consume it. **Upstream:
   [claude-kit#34](https://github.com/tyabu12/claude-kit/issues/34) — delete this entry once it
   lands and the template is re-reconciled.**

## Known gaps, tracked elsewhere

- `.claude/agents/code-reviewer.md` runs its own `git diff HEAD` and `head -14 .claude/rules/*.md`
  cwd-relative; the Step 4 prompt roots only the diff. On a branch editing `.claude/rules/**`, a
  reviewer whose cwd resolved to the main checkout would sweep the pre-change rule set.
