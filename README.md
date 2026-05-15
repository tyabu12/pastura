<div align="center">

# 🐑 Pastura

*AIgazing. Like stargazing, but for local LLMs.*  
Running local LLM multi-agent simulations on-device.

[![CI](https://github.com/tyabu12/pastura/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/tyabu12/pastura/actions/workflows/ci.yml)

</div>

> 🚧 Pastura is under active development. The YAML format and on-device
> data layout may still change. The first App Store submission is in
> preparation.

## What is Pastura

Pastura is a closed pasture for AI agents on your device. Watch as the agents act out the scenarios you've written.

You write a YAML scenario (or build it in the visual editor), pick a
local LLM, and watch the agents talk, vote, and score themselves.
Nothing leaves the device.

For the product story, design philosophy, and faq, head to
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

- **Language and platform**
  - Swift 6.x
  - SwiftUI
  - iOS 17.0 minimum deployment target
- **Libraries**
  - [Yams](https://github.com/jpsim/Yams) 6.2.1 for YAML parsing
  - [GRDB](https://github.com/groue/GRDB.swift) 7.10 for SQLite
- **LLM backends** (selected per build configuration)
  - **`LlamaCppService`** via [llama.swift](https://github.com/mattt/llama.swift). On-device llama.cpp with Metal GPU. The shipping backend for Release builds.
  - **LiteRT-LM iOS SDK**. Planned target backend, blocked on Google's Swift SDK + GPU support. See [ADR-002](docs/decisions/ADR-002.md).
  - **`OllamaService`** via OpenAI-compatible API. Used in Debug builds and on the Simulator.
  - **`MockLLMService`**. Deterministic stub for unit tests only.

## Supported LLM models

Bundled in
[`Pastura/Pastura/App/ModelRegistry.swift`](Pastura/Pastura/App/ModelRegistry.swift).
Both are GGUF Q4_K_M quants, downloaded on first launch.

| Model                                                                | Vendor  | Size    | Notes                                                       |
|----------------------------------------------------------------------|---------|---------|-------------------------------------------------------------|
| [Gemma 4 E2B](https://huggingface.co/unsloth/gemma-4-E2B-it-GGUF)    | Google  | ~3.1 GB | Default. Conversational, plays well with most scenarios.    |
| [Qwen 3 4B](https://huggingface.co/Qwen/Qwen3-4B-GGUF)               | Alibaba | ~2.5 GB | Reasoning-leaning. Good for scenarios that need deduction.  |

Add more by appending a `ModelDescriptor` to `ModelRegistry.catalog`.
The descriptor pins download URL, file size, and SHA-256 at compile
time. The trade-offs are documented in
[ADR-002](docs/decisions/ADR-002.md).

## Prerequisites

- Swift 6 (Xcode that supports it; CI runs on `macos-26`)
- iOS 17.0 deployment target
- iPhone 15 Pro or newer for on-device LLM testing (around 8 GB RAM)
- [Ollama](https://ollama.com) (optional) if you want non-mock LLM
  inference in Debug or on the Simulator

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
pastura/
├── Pastura/
│   ├── Pastura/             # iOS app source
│   │   ├── PasturaApp.swift
│   │   ├── App/             # App state, navigation, ViewModels
│   │   ├── Engine/          # Scenario engine (phases, scoring)
│   │   ├── LLM/             # Inference backends (llama.cpp, Ollama, Mock)
│   │   ├── Data/            # GRDB / SQLite persistence
│   │   ├── Models/          # Domain types, depends on nothing
│   │   ├── Views/           # SwiftUI screens and components
│   │   ├── Utilities/
│   │   └── Resources/       # Bundled presets, demo replays, blocklist
│   ├── PasturaTests/        # Unit and integration tests
│   └── PasturaUITests/      # UI tests
├── docs/
│   ├── ROADMAP.md           # Phase scope and Go / No-Go criteria
│   ├── decisions/           # Architecture Decision Records
│   ├── specs/               # Feature specifications
│   ├── design/              # Design system, reference assets
│   ├── i18n/                # Localization workflow
│   └── blocklist/           # ContentBlocklist source + build script
├── pages/                   # The pastura.app site (deployed via GitHub Pages)
└── scripts/                 # Build, lint, content-blocklist helpers
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
