# ADR Writing Guide — inter-citation consistency

On-demand companion to [`.claude/rules/adr-writing.md`](../../.claude/rules/adr-writing.md).

The rule file keeps the three things that must be in context automatically or
must reach a subagent: §1 (verify each fact-claim at write time), §2 (mechanism
contract over pinned model thresholds), and §4 (numbering facts). Those are
cited by name from a dozen ADRs and are the payload the `/claude-kit:write-adr`
skill forwards to its reviewers via `ADR_RULES_PATH` — they stay put.

This checklist is the part nothing cites and nothing routes: a mechanical pass
you run **once, after drafting**, so it costs nothing to keep out of every
ADR-reading session. Read it when you are writing or amending an ADR, spec, or
decision record.

## Inter-citation consistency — dates, SHAs, arithmetic

Distinct from `adr-writing.md` §1 (verify each *individual* citation). This is
**cross-citation**: when the same fact appears in N places, all N must agree,
and any arithmetic *derived* from a citation must match the cited dates / SHAs.
Critic and code-reviewer subagents evaluate framing and rule-compliance, not
mechanical cross-citation arithmetic — so the writer is the only reliable check.

After drafting an ADR / spec / decision record:

1. **Grep every date** (`YYYY-MM-DD`). Sort mentally; cross-check each span
   claim ("predates by N months", "over a year", "X older than Y") against the
   actual gap. (An ADR once shipped "predates by over a year" while its own
   cited commit dates were ~32 days apart — passed two critic rounds + one
   code-reviewer; caught by a third-party cross-reference.)
2. **Grep every short SHA.** Each must resolve in `git log` and its subject
   match the cited claim.
3. **Grep every `file:line`.** Read each; confirm the cited content is there.
4. **Grep period words** (`year` / `month` / `week` / `day`) and recompute the
   span from the dates you cited.

Two recurring variants beyond plain arithmetic:

- **Projection vs measurement.** When a metric appears across a *series* of
  checkpoints (weekly spikes, CI readings, perf runs), cite the **latest
  measured** value — not a superseded earlier **projection**. The rosy early
  estimate is the trap: an evidence-synthesis ADR written from memory reaches
  for it. (ADR-004 §9.3 once cited a week-1 CI *projection* with ~14 min
  headroom as the cold-pipeline evidence; the later week-3 *measurement* was
  17m40s with ~2m20s headroom and a flagged ceiling breach.)
- **Status-flip staleness.** When amending an ADR to record that a condition
  flipped (a migration trigger fired, a dependency became available, something
  got deprecated), the original present-tense rationale ("X is unavailable",
  "no SDK", status tables) now contradicts the new section. Grep every
  present-tense claim about the flipped condition and reframe to **dated
  past-tense + a forward pointer** — do not delete (it's the original decision
  rationale). A section's date header doesn't cover present-tense bullets/rows
  below it (a reader landing mid-section misses it). The **cherry-port variant**
  is worse: porting docs authored *before* a later decision spreads stale
  framing far beyond the renamed heading, and one decision can fork a single
  term into two axes needing separate replacement vocab — full-doc grep the old
  plan's vocabulary, not just the section you renamed.
