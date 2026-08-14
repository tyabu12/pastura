# Knowledge Layering & Promotion

> Derived from [claude-kit](https://github.com/tyabu12/claude-kit) `rules/knowledge-layering.md` —
> the generic core is canonical there; reconcile one-way (kit → Pastura) **rule + doc as a pair**:
> since kit#24 the kit's rules carry firing conditions only, so diffing one alone reads relocated
> depth as deletions. Kit-side pair: `docs/claim-verification.md` (backs § "Verify before you lock
> it"), plus `docs/code-review-path-scoped-rules.md` for the mid-session non-injection probes — that
> one gets no Pastura counterpart on purpose, #1312 holds this repo's. Pastura-specific content
> lives only in this copy.

Always-loaded — see `CLAUDE.md` `## Context-Specific Rules`. Pairs with `context-budget.md` (content discipline within always-loaded files); this rule covers location choice across all storage tiers.

## Where knowledge belongs

Knowledge can live in 5 places. Choose by **who needs to read it** and **how stable it is**:

| Location | Audience | Edit cycle |
|---|---|---|
| `~/.claude/projects/.../memory/` | This user, this machine | Per-session writable by Claude |
| `~/.claude/CLAUDE.md` + `~/.claude/rules/*.md` | This user, **every project** on this machine | Hand-edited in dotfiles, versioned |
| `CLAUDE.md` | All contributors, every session | PR-reviewed |
| `.claude/rules/*.md` | All contributors, scoped sessions | PR-reviewed |
| `docs/**` | All contributors, on-demand reading | PR-reviewed |

Memory `feedback_*` / `project_*` / `reference_*` entries belong in a rules file when the lesson is **non-obvious and won't be re-derived**. Memory `user_*` always stays in memory.

**Quick test before saving a memory**: *"Would a new contributor with no prior context reliably arrive at the same advice from first principles?"*

- **Yes** → memory (rapid-capture only — the lesson is derivable from code / docs / tooling on demand)
- **No** → a rules file. **Then pick the tier by audience**:
  - a lesson true across *all my projects* (a tool's quirk, a personal workflow rule) → **global `~/.claude/rules/`**, not this repo — writing it here burdens Pastura contributors with a rule that is not about Pastura.
  - a lesson specific to *this project* → Pastura's `.claude/rules/` (path-scoped if domain-specific), or `CLAUDE.md` when it is project-wide.

  A global rule **adds** a personal baseline, never **replaces** what a shared repo must carry — § "Anti-pattern: memory refs in repo-tracked files" below.

**User-preference carve-out**: feedback flavored as personal preference (e.g., "this user wants critic limited to 2/PR") stays in memory regardless of Pastura-specificity — it's `user_*`-flavored even when the trigger event was project work.

## Promotion & retirement

Trigger a triage pass on memory **count** or **total content size** (`cat memory/*.md | wc -c`) — >80 files or >~250KB, or every several months. Never wait for the built-in MEMORY.md *index*-size warning: index lines are one-liners, so it badly understates true content and fires far too late. Two cheaper triggers ride along: during `/orchestrate`, if this session created feedback memories and the PR already touches `.claude/rules/`, bundle the rule addition in; and at memory-save time, apply the quick test above and prefer opening the rules PR alongside the entry.

**Retire, don't only promote.** A pass *removes* memory as well. A `project_*` tracker whose work has fully SHIPPED — no open follow-ups, outcome derivable from code/git/docs — is **DELETED**; one with a shipped bulk plus a few live items is **TRIMMED** to its open-tracking stub. The two compose: run the quick test first to promote any durable lesson, then delete or trim the residue — the same memory can be promoted *and* retired in one round. **Prefer deletion.** A persistent `feedback_*>40` signals a *promotion* backlog specifically (retirement never deletes `feedback_*`). Dispositions and the approval flow: the `claude-kit:promote-memories` skill (plugin-provided; Pastura keeps no local copy).

## Procedure

**Any** rules addition — promoted from memory or not — is drafted at **concept level**: WHY + the invariant + a durable pointer, not the exhaustive HOW (grep blocks, enumerations, step lists). This holds for **path-scoped** targets too, where `context-budget.md`'s always-loaded discipline stops and its "budget looser there" does *not* license a dump; expand a section only when a reviewer shows the omitted detail is load-bearing for the rule to fire.

Promotion specifically is PROMOTE-only — retirement is memory-direct and needs no PR. Two steps nothing else enforces, so they belong on the rolling issue's checklist: **update every mirror** of the promoted fact in the same PR (the `code-reviewer` trap cheat sheet, a `CLAUDE.md` parenthetical — mirrors drift silently otherwise), and **delete the source memory only after the rule lands**, since a repo PR cannot enforce a per-machine `command rm`. **Read [`docs/agent-tooling/claim-verification.md`](../../docs/agent-tooling/claim-verification.md) § "Promotion mechanics" before starting one** — it has the full sequence, including the provenance-line strip.

## Anti-pattern: memory refs in repo-tracked files

Auto-memory at `~/.claude/projects/<workspace>/memory/` is **per-user /
per-machine**. Any reference of the form `` memory `<name>.md` `` inside a
repo-tracked file (CLAUDE.md, CONTRIBUTING.md, ADRs, source comments,
script header docs) is a **dead link** for everyone except the
maintainer who wrote the memory.

**This is also why a repo-tracked rule must stay self-contained** — do not
slim a project's `.claude/rules/` down to "see the maintainer's global
rule": that global file does not exist for other contributors or in CI.
Global rules *add* a personal baseline; they never *replace* what a shared
repo needs to carry itself.

**Apply** — for rationale in any repo-tracked file, prefer inline summary
+ PR / issue / ADR pointer (`#410`, `ADR-007`, etc.). Memory refs are
acceptable **only** in never-committed places (`~/.claude/CLAUDE.md`,
conversational scratch).

**Detection** — new code must not add hits. Enumerate, don't recurse: a
recursive search answers "which files lie here", not "which are
**repo-tracked**", and misses either way depending on the searcher (`rg` skips
dot-dirs without `--hidden` — how `.claude/**` went unscanned — and tracked
files staged under an ignored directory; plain `grep -r` flags ignored scratch).
`-H` is required, or `grep` drops the filename on a single match.

```sh
git ls-files -z --cached --others --exclude-standard \
  | xargs -0 grep -nHE 'memory `[a-z_]+\.md`'
```

Known carve-outs (where inline rationale would be too dense to migrate):

- `Pastura/Pastura/Views/Components/ThoughtVisibilityToggle.swift` —
  ShapeStyle vs Color token trap rationale
- `Pastura/PasturaTests/App/LaunchPhaseCoordinatorTests.swift` —
  CI wallclock test bound rationale

See PR #420 for the motivating incident. Why the prose example above is
written with a `<name>` placeholder rather than carved out, and why the file
set matters more than the pattern: the doc's § "The rule-assertion case".

## Anti-pattern: a comment written for the reviewer

Same misfiling, one tier down. A comment is read by the **next editor**, so a
block where *no* sentence states a durable claim — only provenance, the diff's
own argument, a figure a canonical site already states — belongs in the PR body
or an ADR. Move the whole block, never a clause: a backward-looking sentence is
routinely what makes the forward rule intelligible. But **volume** is the
commoner defect, tracks the model rather than recency, and is fixed by
rewriting shorter, not deleting — so watch the count before the length. Past
~10 lines (the concise baseline's top tenth) rewrite once at half length and
**the rewrite wins**, unless it dropped a forward-looking fact, which a `///`
block of measured values usually would. Rates, three refuted gate designs, the
duplicated-figure grep: the doc's § "A comment written for the reviewer".

## Verify before you lock it

One discipline, three moments where a claim becomes load-bearing and nobody downstream will check it — the author is the only one positioned to run it.

- **Rule-commit** — a `.claude/rules/` or `CLAUDE.md` addition carrying an **executable assertion** (an asserted grep hit count, a cited `file:line`, a `(PR #N)` claim, a cross-doc heading anchor, **or a self-quoted byte/line delta** — re-measure that one on the *final* commit) is run against current main state **before commit**. Dispositions: § "Dispositions when an assertion diverges".
- **Plan-lock** — every load-bearing claim a plan leans on is verified against its authoritative source **before** Step 1b. **Read the doc's § "The claim table"** — it maps each claim shape to the source that settles it, and the shapes are not guessable (a defect framed with `would`; two UI surfaces called "the same metric"; a subagent verdict that *dismisses* a risk; a claim **inherited from existing text**).
- **Authoring** — a why-comment, guard, count, or gap list *you write* asserts behaviour that nobody executes. § "Claims you author are assertions too".

### Dispositions when an assertion diverges

Run the command from the current worktree, compare against what the draft asserts, then reconcile one of three ways — never leave the divergence:

- **Sweep** — fix the violations in this PR if cheap.
- **Reframe** — change the assertion to match observed state. § "Anti-pattern: memory refs in repo-tracked files" above is itself an example: "new code must not add hits" + a carve-out list, rather than "should return 0 hits".
- **Inline carve-out** — enumerate existing violations with `file:line`.

Non-grep claims count too: cited paths (`find`), `(PR #N)` claims about PR body content (`gh pr view N`), heading anchors (`grep` for the exact heading).

### Claims you author are assertions too

A why-comment, guard, count or gap list asserts behaviour as the reason a mechanism exists — the same kind of claim the Plan-lock table covers, but authored at implementation *or review-fix* time, so no `Verify by` lookup applies and nobody executes it. Four shapes:

- **Why-comment on a mechanism** → delete the mechanism and run the tests. Green means the claim is false, or the tests never covered it.
- **A detector / guard / gate** → construct what it claims to catch and confirm it fires. A guard's success case proves nothing; only a negative control does, and it must sit in the claim's *habitat*, not merely match its pattern.
- **A classification or count built on an earlier claim** → when you fix that claim, grep what cited it. Nothing points back at the dependent one.
- **A gap list — and the remedy you prescribe for it** → an enumeration inherits the blind spot of whatever it was drawn from. Re-derive from what changed, then check the remedy actually reaches it.

**A probe's outcome gets misread in both directions.** Assert that the mutation's anchor matched — a `replace` that silently no-ops reads as verified. And treat a **green** probe as a finding about the *fixtures*, not a redundant guard. When a check is too expensive to run, say the cause was not isolated: a reader can act on an acknowledged gap; a wrong cause they can only inherit.

**Before writing a guard, a negative control, or a why-comment you cannot cheaply test, read the doc's § "Authored claims — the four shapes in full" and § "Reading a probe's outcome".** Each shape's elaboration — the sibling arm that reddens a control for the wrong reason, the concessive clause marking an already-broken category, two sets that read as a partition — is where it actually goes wrong.

### A rules file created mid-session never injects in that session

However correct its `paths:`, a working glob and a broken one look identical in the authoring session — both simply absent. The *effect* is measured; the mechanism is not, and an **edit** to an existing rule was never probed, so don't extend it there.

**Apply**: verify a new or re-scoped rule from fresh subagent probes, one `Read` each, with a **positive** control. Probes, mechanism caveat and scope limits: #1312.
