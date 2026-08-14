# Claim verification — which source settles which claim

Paired with the always-loaded rule `.claude/rules/knowledge-layering.md` § "Verify before you lock
it", which carries the discipline and the three moments it fires at. This file carries the per-shape
checks, the worked failures, and the promotion mechanics.

**Reconcile as a pair.** The kit counterpart is [claude-kit](https://github.com/tyabu12/claude-kit)
`docs/claim-verification.md`; its rule is `rules/knowledge-layering.md`. Diffing either half alone
reads relocated depth as a deletion. Nothing here is version-dependent, so there is no
re-measurement trigger — it accretes as new failure shapes appear.

**Why this is a doc and not a `paths:`-scoped rule.** A path-scoped rule would also leave the
always-loaded budget, but it injects only on a `Read` matching its globs — and the Authoring moment
fires in *any* file: Swift, a script, an ADR, a rule. No glob covers "any". So the trigger stays in
the always-loaded rule and the evidence lives here; the cost is that this file loads only when
something reads it, which is why the rule's pointers to it are imperative rather than "see also".

## Why the author is the only checker

**A claim is checked by whoever authors it, or by nobody.** A reviewer checks whether the code is
correct and whether a rule's content is sensible — not whether the check a rule prescribes actually
passes, and not whether the stated reason for a mechanism is true. A plan critique tests internal
consistency, not external truth: `claude-kit:critic`'s axes are codebase-internal (dependency rules,
phase scope, integration risk), so a claim that is externally false but internally plausible passes
it and surfaces only at code-review or in production.

A 30-second self-check prevents 1–2 extra critic / code-reviewer rounds.

## The claim table

Verify each against its authoritative source *before* the plan locks.

| Claim a plan leans on | Verify by |
|---|---|
| A header/doc comment asserting cross-file structure ("defined in M", "consumable by Y") | grep the actual symbol/type — comments can be aspirational, not descriptive |
| A `§"Heading"` cross-doc reference | grep the target for the exact heading **and read under it** to confirm the content matches; add a named heading if absent |
| "band-aid / hack / dead code" framing of a change | grep ALL producers + consumers across layers (esp. Engine/runtime), not just the layer the issue scopes — the target may be load-bearing |
| A documented defect framed as **live** ("X `would` flow into Y — i.e. fabrication") | grep every **writer** of the value, not just the reader — an upstream guard may already make it unreachable, in which case the comment is that guard's rationale, not a bug report. Subjunctive mood is the tell (#1151) |
| Two UI surfaces asserted to show "the same metric" | grep both value sources before claiming equivalence — layout/label similarity ≠ value identity; a static estimate and a measured count can read as "matching" yet diverge silently |
| An external standard (SEO, RFC, sitemap/robots, OAuth, HTTP semantics) | WebSearch + WebFetch the authority (Google Search Central, the RFC, MDN); verbatim-cite before critic |
| Vendor feature availability (free/paid/plan tier) | WebFetch the canonical docs; verbatim-quote the "Who can use this feature" box — never infer from search snippets |
| A subagent's verdict on an external platform fact (SDK annotation, threading contract, API availability) | Re-derive it yourself — a verdict that *dismisses* a risk ends inquiry and is the expensive one to get wrong. Then run the prescribed check against a **known-positive control**; `.claude/rules/swift-isolation.md` § Pattern 7 is the worked instance |
| A claim **inherited from existing text** — carried into a new file, summary, or INDEX entry from a doc/rule/ADR that already states it | grep the always-loaded `.claude/rules/**` for a **retraction**, not only the source you copied from. Checking the source agrees *by construction*, so that check cannot see that another document has since withdrawn the claim — and it returns a confident "verified". #1439 is the worked instance: a probe-methodology cause was carried out of ADR-028 while Pattern 8 had already retracted it |

This applies to **non-grep claims** too: cited file paths (`find` to confirm existence), `(PR #N)`
claims about PR body content (`gh pr view N` to verify), heading anchors in cross-doc refs (`grep`
for the exact heading).

## Authored claims — the four shapes in full

Authored at implementation *or review-fix* time, and executed by nobody. The rule carries the
one-line version of each; the elaborations are what get missed.

- **Why-comment on a mechanism** → delete the mechanism and run the tests. Green means the claim is
  false, or the tests never covered it. Its *destination* is a separate question — see § "A comment
  written for the reviewer" below.
- **A detector / guard / gate** → construct the thing it claims to catch and confirm it fires. A
  guard's success case proves nothing; only a negative control does. Scope it to the claim it
  defends: a check narrower than that claim (a files-only loop behind a files-and-directories
  completeness claim), or one that silently skips its exemptions instead of declaring them, passes
  by construction. And a control whose fixture a **sibling arm** can also reach reddens for the
  wrong reason — read *which* message fired, not the exit code, and re-key the fixture until only
  the guard can reach it.
- **A classification or count built on an earlier claim** → when you fix that claim, grep what cited
  it. Fixing one authored claim can *invalidate* another you authored earlier, and nothing points
  back at it; a concessive clause propping up a category ("it belongs here, just differently") is
  the tell that it already broke.
- **A gap list — and the remedy you prescribe for it** → each is an enumeration, inheriting the
  blind spot of whatever it was drawn from. A residue record drawn from the section naming one
  *kind* of gap cannot see the other kinds, and "re-run §X" is unpayable when §X never listed half
  the items. Re-derive from what changed, then check the remedy actually reaches it. Two sets
  written in sequence also read as a **partition** — state the overlap, or the reader does the
  arithmetic wrong, in the direction that understates residue.

When a check is too expensive to run, say the cause was not isolated. A reader can act on an
acknowledged gap; a wrong cause they can only inherit.

## A comment written for the reviewer

Backs the rule's § "Anti-pattern: a comment written for the reviewer". A comment whose only content
is what *this* change did addresses the reviewer, not the next editor.

**The form that survived a negative control**: flag a block only when *every* sentence in it is a
backward-looking report, or when it restates a figure with a canonical site elsewhere. Over 169
comment blocks from two model generations of this repo's own history (#1479), that caught every true
instance with no false positives. **`code-reviewer` ships the second arm narrower** — only when the
comment *itself* names the owning site — for the split-review reason below, so the zero-false-
positive figure covers the form measured here, not the predicate that gate applies.

**Do not key it on wording instead.** Tense is the tempting discriminator — "must stay identical to
X" constrains, "was left identical to X" reports — and on that corpus it had to decide 17 blocks and
got 4 wrong. It reads the grammatical head, not the payload:

- `GameHeader.swift`'s "…lives in `LeafIcon.swift`, which owns the 9pt default this file used to
  apply" (stale move record) and `LLMCaller.swift`'s "…live in `LLMCaller+Logging.swift` to keep
  this file under SwiftLint's `file_length` budget" (live breadcrumb) have identical grammar.
- Duplication is invisible to it — a measured GGUF figure copy-pasted from `ModelRegistry.swift`
  into the harness's `ModelProfile.swift` is the defect, and every word of it is a legitimate
  present-tense fact.
- It strips backward-looking clauses a forward rule depends on (`GalleryHighlight.swift`'s "any
  required key added *after that* bumps the version").

Those 4 outright wrong answers are the floor, not the cost: per-clause flagging *misfires* on ~7% of
the corpus's load-bearing blocks — a wider set, since a block also breaks when a correct flag is
acted on clause-wise — and worst on the longest. The four-site negative control shows why the block
is the unit: three were unambiguous keeps, and the fourth (`PlaybackSpeed.swift:8-9`) is a keep
whose cited sentence *alone* reads as a move record — it differs from a true instance by a following
sentence turning the history into a live constraint, **a payload, not a tense**.

**Word the trigger as an absence, and state precedence.** Running the drafted `code-reviewer` bullet
over six real blocks caught two more defects, both invisible on re-reading. "Flag when *every*
sentence merely reports" cannot be audited — an agent cannot point at what convinced it — whereas
"flag when *no* sentence states a durable claim" makes the saving sentence citable, and a one-
sentence block silently degenerates under the first form since clause and block coincide. And a rule
carrying both a trigger and a "never cut a load-bearing clause" safeguard must say which wins, or a
block that fires the trigger while holding a live pointer yields either a deleted pointer or an
unactionable finding. Both trials — the four control sites and the six blocks, per site and per
verdict — are the ledger comment on #1479.

The duplicated-figure shape needs a **repo-side grep**, not a review agent. `code-reviewer` bails
`SCOPE_TOO_LARGE` above ~800 lines or ~8 files, and every commit that motivated this rule exceeded
the file bound — so the diff gets split and no shard sees all the sites. Frame it as *new code must
not add hits*, existing count as an acknowledged baseline (the *reframe* disposition); #1477 is the
open instance.

**Length is the commoner defect.** In that corpus one generation wrote ~45% more comment lines per
block and ~47% more blocks per commit at an unchanged A/B/C/D distribution — same content, longer.
Compressing it loses nothing, and is safer than any rule that deletes a category of content.

## Reading a probe's outcome

It gets misread in both directions.

**Assert that the mutation's anchor matched.** A `replace` that silently no-ops leaves the original
behaviour and reads as verified. Make the script fail loudly on a miss rather than reporting
success — during this repo's own evacuation work, an anchor-asserting replace caught a pointer
rewrite whose search string had drifted by a line break, which a plain `replace` would have skipped
while printing nothing.

**Treat a probe that stays green as a finding about the *fixtures*, not a redundant guard.** A suite
only reddens on states its fixtures build, so name the state the guard defends and confirm something
constructs it before concluding anything.

## The rule-assertion case

A rule file is where authored claims concentrate, because a rule *is* a set of assertions about the
repo — and unlike a why-comment, the next reader runs them. Two consequences behind the rule's
one-line version: a self-quoted byte/line delta is re-measured on the **final** commit because
review fixes move it, and a diverged assertion left silently in place is the one wrong answer,
because the reader who finds it is the one relying on it.

A detector a rule *ships* is the sharpest case, because it runs against the file that defines it.
The memory-ref detector in § "Anti-pattern: memory refs in repo-tracked files" flagged that
section's own prose example of the banned form — the *form being defined*, not a reference. The three
dispositions are not equally cheap here: an inline carve-out adds a line to an **always-loaded**
file *and* is itself a `file:line` assertion that re-breaks whenever the line moves, and narrowing
the pattern to dodge one example is brittle by construction. Rewriting the example with a `<name>`
placeholder takes the detector back to its carve-out baseline without weakening it. If a later edit writes a concrete
lowercase filename back in, the grep fires and the next editor picks a disposition again — the
mechanism working, not a regression.

**The file set matters more than the pattern.** The detector's first form recursed with `rg`, which
skips hidden directories, so `.claude/**` — rules, skills, agents — went unscanned. `--hidden` closes
that one instance and leaves the class open: a recursive grep answers "which files lie here" while
the rule asks "which are repo-tracked", and the two diverge both ways (a tracked file under an
ignored directory is missed; never-committed scratch is falsely flagged). Enumerating with
`git ls-files --cached --others --exclude-standard` is what actually matches the claim. Measured in
this repo before the placeholder rewrite: the `rg` version returned 2 hits, the enumerating version
3 — the third being the rule's own prose example. **When a detector's file set is not the claim's
file set, no flag fixes it.**

Scope the negative control to the claim's *habitat*, not just its pattern: a control placed at the
repo root sits inside the old detector's existing reach and reddens without testing the question.
The control that settles it puts the violation inside `.claude/`.

## Promotion mechanics

The rule carries the triggers and the two steps nothing else enforces. The full sequence:

1. File a rolling tracking issue collecting candidate sections.
2. `/orchestrate` a PR landing the additions to `.claude/rules/` (or `CLAUDE.md` for project-wide
   rules), at the concept-level drafting bar. That bar is **not** promotion-specific — it governs
   any rules addition — so it lives in the rule itself (`knowledge-layering.md` § "Procedure"),
   not here. One copy on purpose.
3. Strip `Source memory: feedback_*` provenance lines from drafts before commit — a repo-tracked
   file referring to per-user memory by name is a dead link for other contributors.
4. Update **every mirror** of the promoted fact in the same PR — the `code-reviewer` trap cheat
   sheet (`.claude/agents/code-reviewer.md`), a `CLAUDE.md` summary parenthetical. Mirrors drift
   silently otherwise: `swift-isolation.md` gained Pattern 5 while two "4 traps" enumerations
   stayed behind.
5. After the PR merges, locally `command rm ~/.claude/projects/.../memory/<source>.md`. A repo PR
   cannot enforce a per-machine deletion, so it belongs on the rolling issue's checklist.

Dispositions and the approval flow for the triage itself: the `claude-kit:promote-memories` skill,
§ "Step 1: Triage".

## Motivating incidents

PR #420 (memory refs in repo-tracked files); PR #462 round-3 critic (rule self-check); PR #1152
round-1 review; PR #1299 rounds 1–3; #1312 rounds 1–4; PR #1303 rounds 1–3; PR #1314; PR #1334;
PR #1365 / #1370 (authored-claim shapes); tyabu12/claude-kit#30 / #32 / #33 (the detector's file
set).
