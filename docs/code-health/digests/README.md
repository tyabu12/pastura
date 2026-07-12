# code-health-audit digests

Per-run digest artifacts land here as `YYYY-MM-DD-<slug>.md`, ranked by leverage
(impact ÷ effort, weighted by confidence). Each finding carries `file:line`
evidence, impact, effort (S/M/L), confidence, and a counter-evidence /
"why a maintainer might reject this" line (Output Contract rule 2).

**These files are gitignored** — they are ephemeral local logs. The durable
cross-run record is the git-tracked [`../ledger.md`](../ledger.md); a human
promotes a digest finding to an issue and updates the ledger by hand (see
[`../README.md`](../README.md) § Promotion). Only this README is tracked.
