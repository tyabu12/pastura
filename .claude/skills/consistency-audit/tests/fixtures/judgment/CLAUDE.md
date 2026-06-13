# Judgment fixture

No authoritative sources accompany this fixture (the auditor must degrade
gracefully and report zero `auto_fixable` findings). Two distinct dead doc
links are expected as `needs_judgment` findings; the negatives below must NOT
fire.

- A dead doc link: [gone](docs/missing-a.md).
- Another dead doc link to a different target: [also gone](docs/missing-b.md).

Negatives (must not fire):

- A working link resolves: [foo](docs/foo.md).
- An external link is ignored: [repo](https://github.com/example/repo).
- A link on a reserved line is skipped: [future](docs/not-written.md) is
  reserved — not yet written.

```
[fenced](docs/missing-c.md) lives inside a code fence and must be skipped.
```
