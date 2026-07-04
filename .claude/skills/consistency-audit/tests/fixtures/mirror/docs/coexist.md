# Coexistence

The mirror machinery must not disturb the other detectors when they share a
file with a mirrored block.

We pin Yams 1.0.0 in this table (drifts from the resolved pin).

See [the missing doc](missing.md) for the rationale.

Refer to ADR-099 for the original decision.

A drifted near-complete mirror of data/alpha.yaml, placed below the lines the
other detectors key on:

```yaml
id: alpha
name: Alpha scenario RENAMED
agents: 3
rounds: 2
personas:
  - name: One
    role: boss
  - name: Two
    role: follower
phase: speak_all
```
