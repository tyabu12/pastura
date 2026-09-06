---
paths:
  - "Pastura/Pastura/**/*.swift"
  - "Pastura/Pastura/PasturaApp.swift"
  - "Pastura/PasturaTests/**"
  - "Pastura/PasturaUITests/**"
  - "tools/harness/**"
  - "Pastura/Pastura/App/KMP/**"
---

# Build & Lint Traps

No gate can pick your filename, remove the *need* for a directive, or read a sentence. That residue is all the sections carry.

| Trap | Gate |
|---|---|
| Duplicate base filename within one target | `scripts/duplicate-basename-gate.sh` — pre-commit sub-gate 17, CI shell-tests |
| Directive inside a `///` doc comment — a silent no-op | `.swiftlint.yml` custom rule `swiftlint_directive_in_doc_comment` |
| Directive between the doc comment and the declaration | stock `orphaned_doc_comment` |
| Prose about a directive parsed as one | **none** — silent in some shapes, and not separable from legitimate prose by regex |
| `swiftlint --path <file>` reads as "clean" | none, deliberately |

## Duplicate base filename → `.stringsdata` collision

`PBXFileSystemSynchronizedRootGroup` auto-includes every file under `Pastura/`, so a name can collide **cross-layer** with a file you never opened. Rename to something distinct — and rename the type too if it also clashes.

## SwiftLint directive placement around a `///` doc comment

Both placements fail, so remove the *need* for the directive: `function_body_length` → extract a helper (`BundledDemoReplaySource.loadOne` → `buildSourceOrSkip`); `identifier_name` on a short domain identifier → an `.swiftlint.yml` `identifier_name.excluded` entry. A `disable`/`enable` pair inside a block only splits it into an `orphaned_doc_comment`.

## Prose ABOUT a directive is parsed AS one

The parser honours a directive **mid-sentence**, so a `//` comment quoting a directive's literal text applies it — the rule really is disabled, build and lint green. Name the directive rather than spelling it. The examples here are spelled out only because Markdown is not scanned; that asymmetry is the trap, not licence to quote one in a `.swift` file.

## `swiftlint --path <file>` is not an option, and its error reads as "clean"

`swiftlint lint --path X` exits `Error: Unknown option '--path'`, so a probe grepping that output for a rule name concludes the rule did not fire. Put the fixture **inside** `.swiftlint.yml`'s `included:` tree and run `swiftlint lint --strict`. Two things suppress a rule while reading as "not enabled": a fixture outside `included:` (path-independent rules still fire there, so the run looks live), and a file-level disable directive already in the file.
