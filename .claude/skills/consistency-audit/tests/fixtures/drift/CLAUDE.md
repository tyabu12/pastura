# Drift fixture

The version strings below disagree with the authoritative sources, so the
auditor must report three `auto_fixable` findings, and `--fix` must rewrite
them to match.

| Component | Choice | Version |
|-----------|--------|---------|
| YAML parser | Yams | 6.2.1 |
| SQLite | GRDB | 7.10.0 |
| Min iOS | 16.0 | |

The explanatory bullets below mention both the stale and the correct value on
one line, so the detector must skip them (two versions on a line is
ambiguous) and fire only on the single-version table rows above:

- Yams resolves to 6.2.2 (doc table says 6.2.1).
- GRDB resolves to 7.11.0 (doc table says 7.10.0).
- The build targets iOS 17.0 (doc Min iOS says 16.0).
