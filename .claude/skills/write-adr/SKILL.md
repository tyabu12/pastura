---
name: write-adr
description: Generate an Architecture Decision Record and save it to docs/decisions/.
allowed-tools: Read, Grep, Glob, Write, Edit, Agent
argument-hint: "<title>"
---

# /write-adr <title>

Generate an Architecture Decision Record for: $ARGUMENTS

See `.claude/rules/adr-writing.md` for the concepts that govern ADR drafting — fact-claim verification and mechanism contract over pinned thresholds. Apply both at draft time, not just at review time.

## Instructions

1. Determine the next ADR number by listing `docs/decisions/` and finding the highest existing number + 1.
2. Read `CLAUDE.md` for project conventions and context.
3. If the decision relates to a specific phase, read the relevant section from `docs/ROADMAP.md`.
4. Write the ADR in `docs/decisions/ADR-NNN.md` using the structure below.
5. Keep it concise and LLM-friendly — clear sections, explicit rationale.

## ADR Structure

Follow the format established by `ADR-001.md`:

```markdown
# ADR-NNN: <Title>

> **Status:** Accepted
> **Date:** YYYY-MM-DD
> **Context:** One-line summary of why this decision is needed.

## Context

What is the issue that we're seeing that is motivating this decision?

## Options

| Option | Pros | Cons |
|--------|------|------|
| **A** | ... | ... |
| **B** | ... | ... |

## Decision

What is the change that we're proposing and/or doing?

## Rationale

Why this option over the alternatives?

## Trade-offs

What becomes easier or more difficult because of this change?
```

Notes:
- Include an Options table when multiple alternatives were considered.
- The Options table may be omitted for decisions with no meaningful alternatives.
- Use `## Trade-offs` rather than `## Consequences` to match ADR-001 conventions.

## Review Loop

After writing the ADR:

1. Launch 2 parallel subagents to review the document (read-only — subagents must not modify any files):
   - Agent 1 (Accuracy): Apply `.claude/rules/adr-writing.md` § 1 — verify every cited `file:line` / rule section / SDK assertion before approving. Check that the Options table includes all discussed alternatives with clear reasons for rejection. Confirm filename follows `ADR-NNN.md`.
   - Agent 2 (Clarity): Review as a future reader — is the rationale self-contained? Could someone unfamiliar with the discussion understand the "why"? Are Trade-offs complete (both benefits and costs)? If the Decision section contains a DoD criterion like `≥ N% on model X`, flag it for mechanism-contract vs. pinned-threshold reconsideration per `.claude/rules/adr-writing.md` § 2.
2. If issues are found, revise the ADR and re-verify.
3. Repeat until no new issues. Hard limit: 3 iterations. Stop after 3 even if issues remain and report them as unresolved.
4. Report the final ADR with iteration count.
