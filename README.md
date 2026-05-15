<div align="center">

# 🐑 Pastura

**iOS app for running AI multi-agent simulations on-device.**

Local LLMs, scenario YAML, no servers.\
For the user-facing pitch, see [pastura.app](https://pastura.app).

[![CI](https://github.com/tyabu12/pastura/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/tyabu12/pastura/actions/workflows/ci.yml)

</div>

> 🚧 Pastura is under active development. The YAML format and on-device
> data layout may still change. The first App Store submission is in
> preparation.

## What's in this repo

You write a YAML scenario (or build it in the visual editor), pick a
local LLM, and watch the agents talk, vote, and score themselves.
Nothing leaves the device.

This README is for people who want to read or modify the source code.
For the product story, design philosophy, and screenshots, head to
[pastura.app](https://pastura.app) instead.

## Architecture

The app is split into five layers.

```
Views → App / ViewModel → Engine + Data → LLM → Models
```

- **Models** has no dependencies and holds the YAML and domain types.
- **Engine** consumes **LLM** and **Models** only. It never imports
  **Data**.
- **Data** persists turn records into SQLite via GRDB.
- **LLM** abstracts the inference backend behind `LLMService`.
- **Views** and **App** are SwiftUI.

The full layer diagram and rationale live in
[`docs/decisions/ADR-001.md`](docs/decisions/ADR-001.md). The strict
dependency direction is preparation for a future SPM module split.

## Tech stack

| Component        | Choice                                            |
|------------------|---------------------------------------------------|
| Language         | Swift 6                                           |
| UI               | SwiftUI                                           |
| Minimum iOS      | 17.0                                              |
| YAML parser      | [Yams](https://github.com/jpsim/Yams) 6.2.1       |
| Local SQLite     | [GRDB](https://github.com/groue/GRDB.swift) 7.10  |
| LLM (current)    | llama.cpp via [llama.swift](https://github.com/mattt/llama.swift) |
| LLM (planned)    | LiteRT-LM iOS SDK                                 |
| LLM (dev)        | Ollama via OpenAI-compatible API                  |
| LLM (testing)    | `MockLLMService`                                  |
| Bundled models   | Gemma 4 E2B (~3 GB), Qwen 3 4B Q4_K_M (~2.5 GB)   |

The LLM backend choice and the planned LiteRT-LM migration are recorded
in [`docs/decisions/ADR-002.md`](docs/decisions/ADR-002.md).

## Prerequisites

- macOS with Xcode 16 or later.
- An iPhone 15 Pro or newer for on-device testing. The bundled models
  need around 8 GB of RAM. The simulator works for everything except
  real LLM inference, which falls back to a mock.

## Build and run

Open the project in Xcode and Run.

```bash
open Pastura/Pastura.xcodeproj
```

From the command line:

```bash
# Test
scripts/xcodebuild.sh test

# Build only (no tests)
scripts/xcodebuild.sh build

# Narrow to a single suite during TDD
scripts/xcodebuild.sh test -only-testing PasturaTests/SimulationRunnerTests
```

The wrapper takes care of simulator selection, derived-data paths, and
the localization-catalog sync step. See
[`.claude/rules/xcodebuild-cli.md`](.claude/rules/xcodebuild-cli.md) for
the full playbook.

## Project layout

```
Pastura/Pastura/
├── PasturaApp.swift
├── App/         # App state, navigation, ViewModels
├── Engine/      # Scenario engine (phases, scoring)
├── LLM/         # Inference backends (llama.cpp, Ollama, Mock)
├── Data/        # GRDB / SQLite persistence
├── Models/      # Domain types, depends on nothing
├── Views/       # SwiftUI screens and components
├── Utilities/
└── Resources/   # Bundled presets, demo replays, blocklist

PasturaTests/    # Unit and integration tests
PasturaUITests/  # UI tests

docs/
├── ROADMAP.md          # Phase scope and Go / No-Go criteria
├── decisions/          # Architecture Decision Records
├── specs/              # Feature specifications
├── design/             # Design system, reference assets
├── i18n/               # Localization workflow
└── blocklist/          # ContentBlocklist source + build script

pages/                  # The pastura.app site (deployed via GitHub Pages)
scripts/                # Build, lint, content-blocklist helpers
```

## Documentation

- [`docs/ROADMAP.md`](docs/ROADMAP.md) for phase status and what ships
  next.
- [`docs/decisions/`](docs/decisions/) for Architecture Decision Records
  (ADR-001 through ADR-010).
- [`docs/specs/`](docs/specs/) for MVP and feature specifications.
- [`docs/design/design-system.md`](docs/design/design-system.md) for
  design tokens, components, and philosophy.
- [`CLAUDE.md`](CLAUDE.md) for hard rules, Swift conventions, and the
  context AI agents use. Humans can read it too.
- [`CONTRIBUTING.md`](CONTRIBUTING.md) for sending a PR.

## License

[MIT](LICENSE)
