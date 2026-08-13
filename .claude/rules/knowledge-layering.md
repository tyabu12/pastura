# Knowledge Layering & Promotion

> Derived from [claude-kit](https://github.com/tyabu12/claude-kit) `rules/knowledge-layering.md` —
> the generic core is canonical there; reconcile one-way (kit → Pastura). Pastura-specific
> content lives only in this copy.

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

  A global rule **adds** a personal baseline, never **replaces** what a shared repo must carry — § "Anti-pattern" below.

**User-preference carve-out**: feedback flavored as personal preference (e.g., "this user wants critic limited to 2/PR") stays in memory regardless of Pastura-specificity — it's `user_*`-flavored even when the trigger event was project work.

## Promotion & retirement

Three triggers for a triage pass (promotion **and** retirement), ordered by fire-rate reliability:

1. **Periodic triage** (most reliable, user-initiated) — run a full triage when total memory files >80 or total memory content >~250KB (`cat memory/*.md | wc -c`; the built-in MEMORY.md *index*-size warning fires far too late — index lines are one-liners, so it badly understates true content — don't wait for it), or every several months. Top-N largest memories → promotion candidates; SHIPPED trackers → retire candidates. A persistent `feedback_*>40` signals a *promotion* backlog specifically (retirement never deletes `feedback_*`).
2. **During `/orchestrate`** (rule-aware bundling) — if the current session created new feedback memories and the active PR is already touching `.claude/rules/`, bundle the rule addition in. Cheaper than a separate cleanup PR.
3. **At memory-save time** (best-effort nudge, expect drift) — for new `feedback_*` saves, apply the quick test above. If it routes to rules, prefer creating a `.claude/rules/` PR alongside (and optionally instead of) the memory entry. The memory is the rapid-capture form; the rule is the durable form.

**Retire, don't only promote.** A triage pass also *removes* memory. A `project_*` tracker whose work has fully SHIPPED — no open follow-ups, outcome now derivable from code/git/docs — is **DELETED**; one with a shipped bulk plus a few live items is **TRIMMED** to the open-tracking stub. Promotion and retirement compose: run the quick test **first** to promote any durable lesson, then delete/trim the residue — a memory can be promoted *and* deleted the same round. **Prefer deletion**: when promoting, or when tracked work completes, actively check whether the memory can go rather than keeping it. (Operational classification: `/claude-kit:promote-memories` § "Step 1: Triage" — the plugin-provided skill; Pastura keeps no local copy.)

## Procedure

This procedure is for **PROMOTE**; retirement (DELETE / TRIM) is memory-direct and needs no PR.

File a rolling tracking issue collecting candidate sections, then `/orchestrate` a PR that:

1. Lands additions to `.claude/rules/` (or `CLAUDE.md` for project-wide rules), drafted at **concept level** — WHY + the invariant + a durable pointer, not the exhaustive HOW (grep blocks, enumerations, step lists). This holds for **path-scoped** targets too, where `context-budget.md`'s always-loaded discipline stops; expand a section only when a reviewer shows the omitted detail is load-bearing for the rule to fire.
2. Strips `Source memory: feedback_*` provenance lines from drafts before commit — repo-tracked files referring to per-user memory by name are dead links for other contributors.
3. If the promoted content is mirrored elsewhere — the code-reviewer trap cheat sheet (`.claude/agents/code-reviewer.md`), a CLAUDE.md summary parenthetical — update every mirror in the same PR. Mirrors drift silently otherwise (e.g., swift-isolation gained Pattern 5 while two "4 traps" enumerations stayed behind).
4. After PR merges, locally `command rm ~/.claude/projects/.../memory/<source>.md` — the PR can't enforce memory deletion (it's per-user / per-machine); track via the rolling issue checklist.

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

**Detection** — new code must not add hits. A recursive grep answers "which
files lie here" while the rule asks "which are **repo-tracked**", and the two
diverge both ways (dot-dirs like `.claude/` go unscanned; tracked-but-ignored
files are missed) — so enumerate, don't recurse. `-H` is required: without it
`grep` drops the filename on a single match and the `file:line` breaks.

```sh
git ls-files -z --cached --others --exclude-standard \
  | xargs -0 grep -nHE 'memory `[a-z_]+\.md`'
```

Known carve-outs (where inline rationale would be too dense to migrate):

- `Pastura/Pastura/Views/Components/ThoughtVisibilityToggle.swift` —
  ShapeStyle vs Color token trap rationale
- `Pastura/PasturaTests/App/LaunchPhaseCoordinatorTests.swift` —
  CI wallclock test bound rationale

See PR #420 for the motivating incident. Long-term, both carve-outs
should migrate to inline rationale or a public doc home.

## Verify before you lock it

One discipline, three moments where a claim becomes load-bearing and nobody downstream will check it. A reviewer evaluates a rule's *content*, not the check the rule prescribes; the Step 1b `claude-kit:critic` tests internal consistency, not external truth. The author is the only one positioned to run it.

- **Rule-commit** — a `.claude/rules/` or `CLAUDE.md` addition carrying an **executable assertion** (an asserted grep hit count, a cited `file:line`, a `(PR #N)` claim, a cross-doc heading anchor, **or a self-quoted byte/line delta** — re-measure that one on the *final* commit) is run against current main state **before commit**. Dispositions: § "Apply (verification table)".
- **Plan-lock** — every load-bearing claim a plan leans on is verified against its authoritative source **before** Step 1b. The critic's axes are codebase-internal (dependency rules, phase scope, integration risk), so an externally-false but internally-plausible claim passes it and surfaces only at code-review or in production. Per-shape checks: the table below.
- **Authoring** — a why-comment, guard, count, or gap list *you write* asserts behaviour that nobody executes. § "Claims you author are assertions too".

| Claim a plan leans on | Verify by |
|---|---|
| A header/doc comment asserting cross-file structure ("defined in M", "consumable by Y") | grep the actual symbol/type — comments can be aspirational, not descriptive |
| A `§"Heading"` cross-doc reference | grep the target for the exact heading **and read under it** to confirm the content matches; add a named heading if absent |
| "band-aid / hack / dead code" framing of a change | grep ALL producers + consumers across layers (esp. Engine/runtime), not just the layer the issue scopes — the target may be load-bearing |
| A documented defect framed as **live** ("X `would` flow into Y — i.e. fabrication") | grep every **writer** of the value, not just the reader — an upstream guard may already make it unreachable, in which case the comment is that guard's rationale, not a bug report. Subjunctive mood is the tell (#1151) |
| Two UI surfaces asserted to show "the same metric" | grep both value sources before claiming equivalence — layout/label similarity ≠ value identity; a static estimate and a measured count can read as "matching" yet diverge silently |
| An external standard (SEO, RFC, sitemap/robots, OAuth, HTTP semantics) | WebSearch + WebFetch the authority (Google Search Central, the RFC, MDN); verbatim-cite before critic |
| Vendor feature availability (free/paid/plan tier) | WebFetch the canonical docs; verbatim-quote the "Who can use this feature" box — never infer from search snippets |
| A subagent's verdict on an external platform fact (SDK annotation, threading contract, API availability) | Re-derive it yourself — a verdict that *dismisses* a risk ends inquiry and is the expensive one to get wrong. Then run the prescribed check against a **known-positive control**; `swift-isolation.md` § Pattern 7 is the worked instance |

### Apply (verification table)

For each load-bearing assertion in the draft:

1. Paste the command (`rg`, `find`, `gh pr view`) into Bash from the current worktree.
2. Compare observed output to what the rule asserts.
3. Reconcile divergence one of three ways:
   - **Sweep** — fix the violations in this PR if cheap.
   - **Reframe** — change the assertion to match observed state. The "Anti-pattern: memory refs" section above is itself an example: "new code must not add hits" + an inline carve-out list, rather than "should return 0 hits".
   - **Inline carve-out** — enumerate existing violations with `file:line`.

This applies to **non-grep claims** too: cited file paths (`find` to confirm existence), `(PR #N)` claims about PR body content (`gh pr view N` to verify), heading anchors in cross-doc refs (`grep` for the exact heading).

A 30-second self-check prevents 1–2 extra critic / code-reviewer rounds. Motivating incident: PR #462 round-3 critic.

### Claims you author are assertions too

A **why-comment you write** asserts runtime or library behaviour as the reason a mechanism exists — the same kind of claim as the table's, but authored at implementation *or review-fix* time and executed by nobody. Reviewers check whether the *code* is correct, not whether the *stated reason* is true, so a false one ships and the next reader inherits it as fact. Four shapes, none expressible as a `Verify by` lookup:

- **Why-comment on a mechanism** → delete the mechanism and run the tests. Green means the claim is false, or the tests never covered it.
- **A detector / guard / gate** → construct the thing it claims to catch and confirm it fires. A guard's success case proves nothing; only a negative control does. Scope it to the claim it defends: a check narrower than that claim (a files-only loop behind a files-and-directories completeness claim), or one that silently skips its exemptions instead of declaring them, passes by construction. And a control whose fixture a **sibling arm** can also reach reddens for the wrong reason — read *which* message fired, not the exit code, and re-key the fixture until only the guard can reach it.
- **A classification or count built on an earlier claim** → when you fix that claim, grep what cited it. Fixing one authored claim can *invalidate* another you authored earlier, and nothing points back at it; a concessive clause propping up a category ("it belongs here, just differently") is the tell that it already broke.
- **A gap list — and the remedy you prescribe for it** → each is an enumeration, inheriting the blind spot of whatever it was drawn from. A residue record drawn from the section naming one *kind* of gap cannot see the other kinds, and "re-run §X" is unpayable when §X never listed half the items. Re-derive from what changed, then check the remedy actually reaches it. Two sets written in sequence also read as a **partition** — state the overlap, or the reader does the arithmetic wrong, in the direction that understates residue.

**A probe's outcome gets misread in both directions.** Assert that the mutation's anchor matched — a `replace` that silently no-ops leaves the original behaviour and reads as verified. And treat a probe that stays **green** as a finding about the *fixtures*, not a redundant guard: a suite only reddens on states its fixtures build, so name the state the guard defends and confirm something constructs it before concluding anything.

When a check is too expensive to run, say the cause was not isolated. A reader can act on an acknowledged gap; a wrong cause they can only inherit.

Motivating incidents: PR #1152 round-1 review; PR #1299 rounds 1–3; #1312 rounds 1–4; PR #1303 rounds 1–3; PR #1314; PR #1334; PR #1365 / #1370.

### A rules file created mid-session never injects in that session

However correct its `paths:`, a working glob and a broken one look identical in the authoring session — both simply absent. The *effect* is measured; the mechanism is not, and an **edit** to an existing rule was never probed, so don't extend it there.

**Apply**: verify a new or re-scoped rule from fresh subagent probes, one `Read` each, with a **positive** control. Probes, mechanism caveat and scope limits: #1312.
