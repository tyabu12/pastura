# code-health-audit digests

Per-run digest artifacts land here as `YYYY-MM-DD-<slug>.md`, ranked by leverage
(impact ÷ effort, weighted by confidence). Each finding carries `file:line`
evidence, impact, effort (S/M/L), confidence, and a counter-evidence /
"why a maintainer might reject this" line (Output Contract rule 2).

**These files are gitignored** — they are ephemeral local logs. So is
[`../ledger.md`](../ledger.md), the cross-run dedup memory: local-only, never
committed. The durable record is the filed issues a human opens when promoting a
digest finding by hand (see [`../README.md`](../README.md) § Promotion). Only this
README is tracked.
