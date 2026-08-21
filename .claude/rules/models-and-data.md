---
paths:
  - "Pastura/Pastura/Models/**"
  - "Pastura/Pastura/Data/**"
---

# Models & Data Layer Rules

## GRDB FK & migration traps

### `PRAGMA foreign_keys = OFF` is ignored inside a transaction

SQLite silently ignores `PRAGMA foreign_keys` toggles mid-transaction — no error,
no effect. GRDB's `dbWriter.write { }` is always a transaction, so the pragma is
a no-op and the following `INSERT` trips the FK (`SQLite error 19`). To plant
FK-violating orphan rows in a test, use `writeWithoutTransaction { }`:

```swift
try await dbWriter.writeWithoutTransaction { db in   // autocommit, not a transaction
  try db.execute(sql: "PRAGMA foreign_keys = OFF")   // ... restore = ON before exit
}
```

### Changing a column's FK action / nullability needs a table rebuild

SQLite can't `ALTER` an existing column's FK action or nullability in place —
rebuild the table (`create new_x` → `INSERT … SELECT` → `drop x` → `rename`).
**Don't hand-roll `PRAGMA foreign_keys = OFF`** around it: it is the no-op above,
and `registerMigration` already defaults to `foreignKeyChecks: .deferred`, so a
plain `registerMigration("vN") { … }` is safe. The migration test must assert
**child-row survival** across the rebuild — one checking only the new columns
passes while children were cascade-deleted. Reference:
`Data/DatabaseManager+Migrations.swift`.

## `Data(contentsOf:)` loads the whole file into RAM

`Data(contentsOf: url)` without options reads the **entire file into memory** —
it does not mmap, and there is no diagnostic. For multi-GB files (model
downloads) that is a jetsam kill. Use `.mappedIfSafe` for read-only mmap (the
backing file must outlive the `Data`), or stream via
`FileHandle.readData(ofLength:)` + `autoreleasepool`. Reference:
`App/ModelManager.swift` `computeSHA256(of:)`.

## Required-arg additions to a core model init cascade to the test target

Adding a required named argument to a widely-used `init` (`Scenario.init`,
`Phase.init`, …) must land the whole cohort in **one commit**: the signature,
every production callsite, the fixture helper (`ScenarioFixture.make`), and every
test callsite. The pre-commit hook and CI's commit gate build the **App scheme
only**, never the test target, so a commit touching production callsites alone
passes the hook and leaves the test target broken until the next `xcodebuild
test`. Measure the blast radius at plan time
(`rg -c '\bScenario\s*\(' --type swift Pastura/PasturaTests`), and never stage a
temporary default where an ADR forbids one.
