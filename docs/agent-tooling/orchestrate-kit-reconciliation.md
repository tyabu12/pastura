# `/orchestrate` ↔ claude-kit template — reconciliation ledger

Paired with the `generated-from:` stamp at the top of
[`.claude/skills/orchestrate/SKILL.md`](../../.claude/skills/orchestrate/SKILL.md). The skill keeps
the stamp and a short pointer; the enumeration lives here so it is not paid on every `/orchestrate`
invocation (`docs/agent-tooling/context-budget.md`). It fires at one moment: when
`/claude-kit:orchestrate-creator` proposes a back-port.

## Why the stamp exists

Pastura's `/orchestrate` predates `/claude-kit:orchestrate-creator` and was never generated from its
template. Without a stamp, Step U-1 classifies the file as hand-written and only reports, so no
template improvement can ever reach it — which is why the routing redesign (kit#19/#23) sat
unapplied for a generation: kit leaves *suboptimal-but-not-wrong* changes to ride along on a
project's next upgrade run, and Pastura's never fired. The stamp records the template revision the
content was last *reconciled* with — a reconcile, not a generation — so a re-run reaches Step U-3's
principle-level proposals. Background: #1453.

Two consequences. **Step U-4 rewrites the stamp line on every upgrade**, so nothing that must
survive can live in it. And Step U compares hashes first, so its "up to date" means *no template
change since the reconcile* — **not** that this file matches the template. It deliberately does not.

## The ledger

**Hand-maintained, and nothing prompts an author to append to it** — no hook fires on
`.claude/skills/orchestrate/SKILL.md`, no `/consistency-audit` detector reads the stamp, no test
asserts these entries. An entry may also be stale: a *correction* goes false the moment upstream
fixes the defect. So judge a back-port proposal on its merits; this list's silence is not evidence
that a change is safe.

Most divergences are **additions**, which an upgrade proposal cannot silently undo. The entries
below are the ones a plausible-sounding back-port *would* undo.

### Adaptations — stable, no retirement condition

1. **Step 1.3's "do not add a blanket 'when in doubt, go up a tier'" guardrail is not in the
   template's Step 1.** Being a *negative* instruction, nothing around it looks wrong once it is
   gone — and it is the direct fix for the defect this file was reconciled to repair. Reject any
   proposal to adopt the template's Step 1 wording that drops it.
2. **The Step 4 reviewer prompt omits the template's selective `.claude/rules/*.md` read.**
   `.claude/agents/code-reviewer.md`'s Review Process step 3 owns that logic here — do not add it in
   both places. But if that agent ever loses it, this prompt must gain it, or path-scoped review
   coverage vanishes silently.
3. **The Step 3 🎵 prompt roots paths at `{WORKTREE_ROOT}` without adopting the template's "run
   tests/git via `-C {WORKTREE_ROOT}` (or `cd` there first)".** `-C` is git-only;
   `scripts/xcodebuild.sh` must stay a bare cwd-relative call, or the delegated subagent stalls on
   an approval prompt (`.claude/rules/xcodebuild-cli.md` § "Canonical invocation"). The template's
   stronger-sounding wording would reintroduce that stall. Reasoning is inline in the skill next to
   the 🎵 prompt.
4. **The template's inlined subagent output-cap / split-budget note is omitted, and its "Project
   parameters (baked at generation)" table has no counterpart.** `docs/agent-tooling/subagent-usage.md`
   is always-loaded here, so inlining pays twice per turn (`docs/agent-tooling/context-budget.md`); and
   this file's parameters are inline at each step and richer than the table's cells.
5. **Step 1.3 routes on two independent axes — *tier* (`🎵` Sonnet / `🎭` `🧠` Opus) and *locus*
   (`🎵` `🎵 (tb)` `🎭` delegated / `🎵 (main)` `🧠` in the main session) — where the template keeps
   one two-icon label whose `🎭` decides both at once.** Step 3 gains a `🎭` branch dispatching
   `claude-kit:implementer` at Opus, and Step 2a emits `Routing: v2` so Step 0 reads a pre-split
   plan comment under its original semantics. This diverges from a **deliberate** upstream design
   (kit#19/#23, live in the template today), not a defect — so it stays out of Corrections and no
   upstream fix retires it; if the template ever adopts a tier/locus split, reconcile against it
   rather than deleting. The template carries no `(tb)` marker at all, so a back-port adopting its
   Step 1 wording drops `(tb)` and silently disarms the two gates that consume it — Step 1.4's
   strictly-simple reviewer test and Step 0's all-Sonnet-tier resumption re-check.

   Motivating baseline: of 250 plan items across the 52 `<!-- pastura-plan -->` comments in the
   then-last 70 issues, 221 (88%) were `🎭`, 37 of 52 plans were 100% `🎭`, and `Session: Opus`
   held 57 of 57 — the all-🎵 cost lever had never fired. Re-derive rather than trust it: for each
   recent issue, `gh api repos/tyabu12/pastura/issues/<N>/comments --jq '.[].body'`, keep the
   bodies containing the plan marker, then count `- [ ]` / `- [x]` item lines per icon (count each
   icon with its own `grep -o -F` — an alternation over these emoji miscounts).

   **That 88% is retired, not a comparand**: `🎭` now means *delegated*, so an unchanged 88% would
   mean everything is delegated — complete success. What tracks the defect is the `🧠` share (work
   still pinned to the main session), the delegated share (`🎭` + `🎵` + `🎵 (tb)`), and the
   `claude-kit:implementer` invocation count, which was ~0 before.

   Two accepted consequences. `claude-kit:implementer` pins `effort: medium` and `Agent` has no
   `effort` parameter, so a `🎭` item runs at Opus/medium where the template's in-session `🎭` ran
   at the session's Opus/high — accepted because Step 1.3's Q2 already requires the item to be
   fully specifiable, the condition that agent is built for; if fix rounds rise, escalate to a
   general Opus subagent at session effort (the ladder the `🎵` fallback documents) or bump the
   pin. And `🎵 (main)` — Sonnet-tier work not worth a delegation prompt — **keeps its Sonnet
   tier**, where the template promotes it to `🎭` and so forces an Opus reviewer and session.
   Pastura's own pre-split Step 1.3 — reconciled from that wording — spelled the promotion's reason
   out as "intended since the orchestrator implements the item directly": a locus-based
   justification for a tier decision, the same conflation in miniature. The template states the
   promotion without that clause, so the reason is Pastura's, not upstream's; do not re-attribute
   it. Template claims here were checked against `skills/orchestrate-creator/` at kit 0.4.7 — the
   promotion is at `orchestrate-template.md` "Also promote a 🎵 to 🎭 when subagent + verify
   overhead exceeds the work itself", and `(tb)` appears zero times in that directory.

### Corrections — delete the entry once upstream lands

A template *defect* is reported upstream; its entry names the tracking issue and dies with it.

6. **Pre-flight check 3's degraded-mode `DEFAULT_BRANCH` fallback deliberately differs from the
   template's.** The template's `git symbolic-ref refs/remotes/origin/HEAD` yields a full ref, not a
   branch name, which breaks the `git fetch`, `git rev-list`, `git pull`, and `git switch` that
   consume it (the shapes are spelled out inline at that check). Do not adopt the template's shorter
   form. **Upstream: [claude-kit#34](https://github.com/tyabu12/claude-kit/issues/34) — delete this
   entry once that lands and the template is re-reconciled.**

## Known gaps, tracked elsewhere

- `.claude/agents/code-reviewer.md` runs its own `git diff HEAD` and `head -14 .claude/rules/*.md`
  cwd-relative; the Step 4 prompt roots only the diff. On a branch editing `.claude/rules/**`, a
  reviewer whose cwd resolved to the main checkout would sweep the pre-change rule set.
