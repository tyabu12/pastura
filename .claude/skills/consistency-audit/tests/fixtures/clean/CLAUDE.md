# Clean fixture

Every reference here is consistent — the auditor must report ZERO findings.
This fixture doubles as the "must-NOT-fire" regression set for the three
active detectors (dependency_version, min_ios, dead_link). The deferred
detectors (file:line, ADR-missing, anchors) are not exercised here.

## Tech Stack

| Component   | Choice | Version |
|-------------|--------|---------|
| YAML parser | Yams   | 6.2.2   |
| SQLite      | GRDB   | 7.11.0  |
| Min iOS     | 17.0   |         |
| Language    | Swift  | 6.x     |

Swift is intentionally written as `6.x` (a range) while the build pins
`SWIFT_VERSION = 6.0` — the auditor must NOT treat this as drift (Swift
version is excluded).

## Prose that must not fire

- iOS 26 Liquid Glass is mentioned here, but this line has no "min", so the
  min-iOS detector must skip it.
- The explanatory line "Yams ships 6.2.2 and 6.2.2 again" has two semver
  tokens, so the dependency detector must skip it as ambiguous.
- A working doc link: [foo](docs/foo.md).
- A working nested doc link: [adr](docs/decisions/ADR-001.md).
- A reserved-line link is skipped: [future](docs/not-written.md) — reserved,
  not yet written.

## Fenced block (must be skipped)

```
[broken](docs/does-not-exist.md)
| stale | Yams | 1.0.0 |
```

The references inside the fence above must be skipped.
