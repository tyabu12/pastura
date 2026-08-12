---
paths:
  - ".claude/skills/**"
---

# Output Contract for unattended generators

> Derived from [claude-kit](https://github.com/tyabu12/claude-kit) `docs/automation-output-contract.md` —
> the generic core is canonical there; reconcile one-way (kit → Pastura). Pastura-specific content
> lives only in this copy. A consumer copy must never become the source.

**Path-scoped, and that scoping has a sharp edge.** `paths:` fires when a matching path is **read**
(a human authoring a skill under `.claude/skills/**` reads it; an edit reads it first) — **not** when
a generator *runs*. A generator run reads and writes `docs/**` and `Pastura/**`, never its own skill
file, and drives its own scripts through Bash rather than reading them. So
every skill governed by this contract carries an imperative "read this file before Step 0" pointer;
that pointer, not the frontmatter, is what puts the contract in context at runtime. It is not
always-loaded because an always-loaded file must earn its per-turn cost by supporting the *next*
decision (see `context-budget.md`), and this binds only inside the generator family.

A **generator** is any skill that runs unattended (scheduled or one-shot) and produces artifacts a
human must review — a docs-fix PR, an issue, a digest. The scarce resource it spends is not compute
but **the reviewer's attention**. This contract is what keeps a generator from bankrupting it.

The skills bound by this contract are the ones that say so in their own body — today
`consistency-audit` (auto-fix Draft PRs + issues), `queue-consumer` (feature-implementation Draft
PRs), and the digest-only `triage-guardian` / `code-health-audit` / `ui-refine`. A new generator
joins by adding the imperative pointer described above, not by being listed here. Family membership
alone does not bind: `scenario-factory` / `scenario-refine` write only gitignored local digests, so
nothing of theirs reaches the review queue this contract rations.

## The contract

0. **PRs are always Draft, and a generator never actuates.** It opens Drafts (`--draft` as the
   first flag), never marks one ready, never merges, never closes an issue, never pushes to a
   default branch, never force-pushes. **This is an invariant to enforce mechanically** — a guard
   hook, an allowlist that omits the actuating commands — not an intention. Rule 3's exemption
   below rests on it, so a generator that can mark its own PR ready has silently left the contract.
1. **Mechanically-determined fix → one batched Draft PR.** A finding is auto-fixable only when the
   correct value is *uniquely determined by an authoritative source* (a version from a lockfile, a
   deployment target from a build setting). Batch every such fix from one run into a **single**
   Draft PR.
2. **Judgment-needed → issue only, never an auto-fix.** Anything whose fix requires a human
   decision is filed as an issue whose body carries a **confidence score** and an explicit
   **counter-evidence / "why this might be wrong"** section — both produced back at detection, not
   composed at filing time (rule 6). This applies to every judgment output a generator emits,
   including recommendations to discard work.
3. **The auto-fix path edits authoritative-source-computed values only — never free-form prose —
   and splices at the detected token's exact offset, not by free-text replace.** This bound is what
   makes omitting a code-review pass safe (see below). A detector that wants to auto-fix something
   non-mechanical re-introduces a mandatory reviewer pass. **Precondition**: a detector that cannot
   report the exact offset of what it found does not qualify for the auto-fix path at all —
   "replace the first match" is the free-text replace this rule bans, however mechanical the value.
4. **Backpressure.** Each generator caps its own work-in-progress, and the family carries an
   **aggregate ceiling** across generators. Both values are project-owned: each generator's own cap
   is canonical in that generator's own skill (e.g. `consistency-audit`'s "at most one open
   `audit/*` Draft"), and the ceiling is canonical in
   `.claude/skills/triage-guardian/SKILL.md` § "Backpressure — canonical definition (single source of truth)". See § Backpressure.
5. **Manual-first.** Detectors run dry-run by default. Trust the output only after a human has
   eyeballed it for a given repo state — and never let a skill self-register its own schedule;
   scheduling is a separate, deliberate human act.
6. **Conservative *output*, exhaustive detection — filter at the output stage and account for the
   drops.** **Changed 2026-08-12**: this rule used to read *"Conservative detection wins. Prefer a
   miss over a wrong flag"*, putting the filter in the **detection** stage. The precision bias stays
   — a wrong auto-fix PR, a false issue, a wrong "ready to merge" (which a human may rubber-stamp),
   or a wrong "discard this" (which destroys queued work) each spend reviewer attention *and* erode
   trust in the generator, while a miss only defers work. What it must **not** do is move upstream
   into the detector (§ Why detection must not self-filter). Split the pass in two:
   - **Detection is for coverage — do not filter here.** Enumerate every candidate; anything routing
     to rule 2 carries a **confidence**, an **estimated severity** and a **counter-evidence** line
     from the moment it is found, so the output stage has a rank key and rule 2's fields are the
     detector's finding rather than an afterthought at filing time. (Rule 1's mechanical lane needs
     none of them — its value has exactly one correct answer.) A model-driven detector nearing its
     coverage ceiling **stops and says so** rather than truncating quietly. The only legitimate
     suppression here is **mechanical**, and each form owes a count of what it removed:
     - an enumerated **by-design / do-not-flag roster**, handed to the detector verbatim;
     - an **evidence precondition** — no exact anchor, no concrete before → after ⇒ not a finding;
     - a **quota**, meaning *rank-then-truncate over an already-enumerated list* — never a cap on
       generating candidates: a cap that stops the search cannot name what it excluded, and it
       reduces `found` in the arithmetic below to the cap itself.

     A deterministic detector — a script, not a model — may hold its predicate in code, reviewable
     at source; that exempts it from the ban on judgment, not from the count. Pastura's one
     instance is `.claude/skills/consistency-audit/scripts/audit_docs.py`. A near-miss tally is the
     cheapest evidence there is that a bar sits too tight.
   - **The output stage filters, conservatively, and leaves a trail.** Vet, dedup and rank here;
     when evidence is short of decisive, route to the human-judgment bucket rather than up to
     "ready" or down to "discard". Publish the arithmetic — **found / filtered / deduped /
     surfaced**, plus whatever was capped or never reached — into a channel the run already writes;
     never mint an artifact just to carry it. Keep each rejection and its reason where the *next* run
     can see it. **The medium is project-owned and already differs by generator**: `code-health-audit`
     uses a local ledger, `consistency-audit` its open-issue set, and `triage-guardian` — which
     deliberately writes nothing — its run log. A generator that rejects nothing owes nothing. An
     uncounted drop is indistinguishable from a finding never made: the next run re-derives it, drops
     it again, and nobody learns the filter is too tight.

**Generator bodies still carrying the pre-2026-08-12 wording** are tracked in
[#1432](https://github.com/tyabu12/pastura/issues/1432) (`consistency-audit` hard rule 4;
`ui-refine`'s generation-side quota). Until that lands this rule is the canonical text and their
duplicates are stale — reconcile them, do not follow them.

### Why detection must not self-filter

Rule 6's split is a model-behaviour fact, not a style preference, and it is recent. Claude 5-series
models apply a filtering instruction literally. **Sonnet 5's guide, § "Code review harnesses"**, on
a review prompt that says *"only report high-severity issues"* or *"be conservative"*: the model
"may investigate the code just as thoroughly, identify the bugs, and then not report findings it
judges to be below your stated bar. […] Precision typically rises, but measured recall can fall even
though the model's underlying bug-finding ability has improved." (`[…]` elides one intervening
sentence.) That section's recommended finding-stage prompt instead asks for coverage, and for "your
confidence level and an estimated severity so a downstream filter can rank them" — two of the three
fields rule 6 requires at detection; counter-evidence is this contract's addition, because rule 2
files on it. **Opus 5's guide** ("Code review and bug-finding") gives the remedy in one line: "ask
it to report everything and filter in a separate pass instead."

The loss is **invisible** — three surfaced findings look the same whether the detector found three
or thirty — and it is worst on a harness carried over from an older model, where the conservative
wording once bought a genuinely shallower pass. A generator that truly has only one pass takes the
guides' fallback: state the bar as a concrete predicate (their example: any bug that could cause
incorrect behavior, a test failure, or a misleading result, omitting only nits like pure style or
naming), never as a qualitative "important".

Verified 2026-08-12 against
[prompting-claude-opus-5](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-opus-5.md)
and
[prompting-claude-sonnet-5](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-sonnet-5.md).
**This block is dated on purpose** — re-check on a model-generation change: the rule survives a
stale citation, the citation should not outlive its generation unnoticed.

### Why an auto-fix PR may skip a code-review pass

Not because the diff is small. The safety rests on two things: the PR is always **Draft** so a
human merge is the review gate, and rule 3 bounds the edit to a value with exactly one correct
answer — there is nothing for a reviewer to assess on a one-token swap. **If rule 3 is relaxed,
restore the reviewer pass.** A generator that writes arbitrary code (a feature implementer such as
`queue-consumer`) never qualifies for this exemption.

## Backpressure

Per-generator caps bound each *lane*; nothing watches the *sum*. As generators are added, each stays
within its local cap while the aggregate of unreviewed Drafts climbs past what one human absorbs.
The aggregate ceiling is that missing sum-level guard.

The **aggregate** ceiling is advisory — the per-generator hard caps remain the real bound, so *its*
read-then-act race (two generators both observe `n` and both proceed to `n+2`) is benign. Wire it in
before it binds: the next generator then inherits backpressure for free instead of being retrofitted.

**A per-generator cap is a different matter — do not inherit that benignity.** A cap of "at most one
open Draft" assumes a single writer; two overlapping runs can each observe zero and both open one.
Either serialize runs (never schedule a generator so it can overlap itself) or re-check after
acting — push the branch, re-query for a sibling, and abandon without opening a PR if one won the
race.

**The judgment lane is the one nothing here bounds.** Both caps count open Draft PRs; rule 2's
issues are outside that accounting, and rule 6's exhaustive detection lands its increment precisely
there. Cap issues per run as well — the number is project-owned by the same test as the ceiling: it
rests on one maintainer's review attention, so it is *retuned* per repo, never recomputed from
upstream. **Pastura has not set one** — until it is set, a run that would file an unusual number of
issues stops and reports instead.

**The ceiling value (`AUTOMATION_WIP_CEILING`) and the branch predicate that identifies
automation-origin PRs are project-owned and canonical in
`.claude/skills/triage-guardian/SKILL.md` § "Backpressure — canonical definition (single source of truth)"** — not here, and not in the kit. Every
file that mirrors either must be changed together with that section.

## `gh` read-surface traps (Draft-triage automation)

Empirically derived; each cost a debugging round.

- **`gh pr checks <N>` exits non-zero on pending (8) and failing (1)** — that is, on exactly the PRs
  a triage pass most needs to classify, so a bare call aborts a `set -e` loop. Use the JSON form,
  which exits 0 across states:
  ```bash
  gh pr checks <N> --json bucket --jq '[.[].bucket] | group_by(.) | map({(.[0]): length}) | add'
  ```
  Read: all `pass`/`skipping` ⇒ green; any `fail`/`cancel` ⇒ red; any `pending` ⇒ still running.
- **A PR with zero checks yields `null`** from that `add` over an empty array. `null` is
  *unknown*, **not** green — never promote it to a ready/mergeable bucket.
- **`mergeable` or `mergeStateStatus` can be `UNKNOWN`** — GitHub computes merge state lazily, only
  when a merge is contemplated, so an untouched Draft may return it. It is not an error. Treat
  **either** field being `UNKNOWN` as unknown and route to human judgment. When neither is:
  `DIRTY` = conflicts, `BEHIND` = behind base, `CLEAN`/`UNSTABLE` = mergeable (`UNSTABLE` means
  non-required checks are failing or pending — still mergeable).
  ```bash
  gh pr view <N> --json mergeable,mergeStateStatus
  ```

**Verification status.** Verified 2026-07-18 against **`gh 2.95.0`**, by negative control on public
repos rather than by the success case (a green PR exits 0 either way and proves nothing):

| Claim | Evidence |
|---|---|
| bare `gh pr checks` exits **1** on failing | `cli/cli#13870` → exit 1; `--json bucket` → exit 0, `{"fail":2,"pass":7,"skipping":12}` |
| bare `gh pr checks` exits **8** on pending | `microsoft/vscode#326424` → exit 8; `--json` → exit 0 |
| zero checks ⇒ `null` | property of `add` over an empty array: `echo '[]' \| jq '[.[].bucket]\|group_by(.)\|map({(.[0]):length})\|add'` → `null`. No PR needed |
| Draft merge state | **not** reliably `UNKNOWN`: three open Drafts in `microsoft/vscode` all returned `MERGEABLE`/`BLOCKED`. Hence the softened wording above — the conservative *handling* is what matters and holds either way |

These are version-dependent CLI behaviours; re-check on a `gh` upgrade. Probing needs no local PR —
`gh pr checks -R <public/repo> <N>` reaches any public repository read-only.
