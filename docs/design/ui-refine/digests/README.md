# ui-refine digests

Per-run output of the [`ui-refine`](../../../../.claude/skills/ui-refine/SKILL.md)
skill. Each run writes one dated file here:

```
YYYY-MM-DD-L<n>-<lens-slug>.md
```

A digest lists that run's survivor proposals (after the adversarial self-filter),
ranked, each with its design-system anchor and a concrete before → after. It is
the human's triage queue — promote the worthwhile ones to issues by hand (see
[../README.md](../README.md) § Promotion).

**The digest files are gitignored** (run artifacts, like
`docs/design/screenshots/` and `docs/design/motion/`). Only this README is
tracked. The durable, committed record is [`../ledger.md`](../ledger.md), not the
digests.
