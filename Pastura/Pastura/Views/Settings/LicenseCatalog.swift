import Foundation

/// One row in the Licenses screen (#506).
///
/// `name` and `licenseName` are proper nouns and deliberately NOT wrapped
/// in `String(localized:)`. `text` carries verbatim license text (or the
/// model-license notice) — legal text must not be machine-translated, so
/// it ships English-only by design.
struct LicenseEntry: Identifiable {
  let id: String
  /// Project / model display name (proper noun, untranslated).
  let name: String
  /// License display line, e.g. "MIT License" (proper noun, untranslated).
  let licenseName: String
  /// Upstream project page or model card.
  let url: URL?
  /// Verbatim license text (libraries) or license notice (models).
  let text: String
  /// Supplemental tappable links (license texts, policy documents).
  /// Labels are formal document titles — untranslated like `licenseName`.
  let links: [LicenseLink]
  /// Set on model entries; `LicenseCatalogTests` cross-checks the set of
  /// ids against `ModelRegistry.catalog` so a future model cannot ship
  /// without a license entry.
  let modelID: ModelID?

  init(
    id: String,
    name: String,
    licenseName: String,
    url: URL?,
    text: String,
    links: [LicenseLink] = [],
    modelID: ModelID? = nil
  ) {
    self.id = id
    self.name = name
    self.licenseName = licenseName
    self.url = url
    self.text = text
    self.links = links
    self.modelID = modelID
  }
}

/// A named supplemental link rendered as a tappable `Link` on the license
/// detail screen — used for legally meaningful documents (the Gemma
/// policies, canonical Apache 2.0 text) that would otherwise be
/// untappable plain text.
struct LicenseLink: Identifiable {
  let label: String
  let url: URL?
  var id: String { label }
}

/// Static acknowledgements data backing `LicensesSheet`.
///
/// Library texts are verbatim copies of the LICENSE files at the exact
/// revisions pinned in `Package.resolved` (see each entry's comment).
/// When bumping a dependency, re-check its LICENSE for copyright-line
/// changes — `LicenseCatalogTests.libraryTextsAreVerbatimMIT` pins the
/// holder lines.
enum LicenseCatalog {

  // MARK: - Libraries

  static let libraries: [LicenseEntry] = [
    // mattt/llama.swift @ c22686c (2.8694.0) — LICENSE.md
    LicenseEntry(
      id: "llama-swift",
      name: "llama.swift",
      licenseName: "MIT License",
      url: URL(string: "https://github.com/mattt/llama.swift"),
      text: """
        Copyright 2025 Mattt (https://mat.tt)

        Permission is hereby granted, free of charge, to any person obtaining a \
        copy of this software and associated documentation files (the "Software"), \
        to deal in the Software without restriction, including without limitation \
        the rights to use, copy, modify, merge, publish, distribute, sublicense, \
        and/or sell copies of the Software, and to permit persons to whom the \
        Software is furnished to do so, subject to the following conditions:

        The above copyright notice and this permission notice shall be included in \
        all copies or substantial portions of the Software.

        THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS \
        OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, \
        FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE \
        AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER \
        LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING \
        FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER \
        DEALINGS IN THE SOFTWARE.
        """),
    // ggml-org/llama.cpp — vendored by llama.swift; attributed separately.
    LicenseEntry(
      id: "llama-cpp",
      name: "llama.cpp",
      licenseName: "MIT License",
      url: URL(string: "https://github.com/ggml-org/llama.cpp"),
      text: """
        MIT License

        Copyright (c) 2023-2026 The ggml authors

        Permission is hereby granted, free of charge, to any person obtaining a copy \
        of this software and associated documentation files (the "Software"), to deal \
        in the Software without restriction, including without limitation the rights \
        to use, copy, modify, merge, publish, distribute, sublicense, and/or sell \
        copies of the Software, and to permit persons to whom the Software is \
        furnished to do so, subject to the following conditions:

        The above copyright notice and this permission notice shall be included in all \
        copies or substantial portions of the Software.

        THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR \
        IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, \
        FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE \
        AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER \
        LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, \
        OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE \
        SOFTWARE.
        """),
    // groue/GRDB.swift @ 9ed8c84 (7.11.0) — LICENSE
    LicenseEntry(
      id: "grdb",
      name: "GRDB.swift",
      licenseName: "MIT License",
      url: URL(string: "https://github.com/groue/GRDB.swift"),
      text: """
        Copyright (C) 2015-2025 Gwendal Roué

        Permission is hereby granted, free of charge, to any person obtaining a copy \
        of this software and associated documentation files (the "Software"), to deal \
        in the Software without restriction, including without limitation the rights \
        to use, copy, modify, merge, publish, distribute, sublicense, and/or sell \
        copies of the Software, and to permit persons to whom the Software is \
        furnished to do so, subject to the following conditions:

        The above copyright notice and this permission notice shall be included in \
        all copies or substantial portions of the Software.

        THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR \
        IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, \
        FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE \
        AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER \
        LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING \
        FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER \
        DEALINGS IN THE SOFTWARE.
        """),
    // jpsim/Yams @ a27b21e (6.2.2) — LICENSE
    LicenseEntry(
      id: "yams",
      name: "Yams",
      licenseName: "MIT License",
      url: URL(string: "https://github.com/jpsim/Yams"),
      text: """
        The MIT License (MIT)

        Copyright (c) 2016 JP Simard.

        Permission is hereby granted, free of charge, to any person obtaining a copy \
        of this software and associated documentation files (the "Software"), to deal \
        in the Software without restriction, including without limitation the rights \
        to use, copy, modify, merge, publish, distribute, sublicense, and/or sell \
        copies of the Software, and to permit persons to whom the Software is \
        furnished to do so, subject to the following conditions:

        The above copyright notice and this permission notice shall be included in all \
        copies or substantial portions of the Software.

        THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR \
        IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, \
        FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE \
        AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER \
        LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, \
        OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE \
        SOFTWARE.
        """)
  ]

  // MARK: - Models

  /// Model licenses are summarized notices with canonical links rather
  /// than full texts: both models are Apache License 2.0 (verified on the
  /// Hugging Face model cards 2026-06-12), whose full text is ~10× the
  /// MIT texts above and lives at a stable canonical URL. The models are
  /// downloaded from Hugging Face at the user's request — Pastura does
  /// not redistribute them.
  static let models: [LicenseEntry] = [
    LicenseEntry(
      id: "model-gemma-4-e2b",
      name: "Gemma 4 E2B",
      licenseName: "Apache License 2.0",
      url: ModelRegistry.gemma4E2B.modelInfoURL,
      text: """
        Gemma 4 is released by Google under the Apache License 2.0. \
        Additional Google policies apply to use of the model, including \
        the Gemma Prohibited Use Policy and the Intended Use Statement.

        The model file is downloaded from Hugging Face \
        (unsloth/gemma-4-E2B-it-GGUF) at your request; Pastura does not \
        redistribute it.
        """,
      links: [
        LicenseLink(
          label: "Apache License 2.0",
          url: URL(string: "https://www.apache.org/licenses/LICENSE-2.0")),
        LicenseLink(
          label: "Gemma 4 license",
          url: URL(string: "https://ai.google.dev/gemma/docs/gemma_4_license")),
        LicenseLink(
          label: "Gemma Prohibited Use Policy",
          url: URL(string: "https://ai.google.dev/gemma/prohibited_use_policy"))
      ],
      modelID: ModelRegistry.gemma4E2B.id),
    LicenseEntry(
      id: "model-qwen-3-4b",
      name: "Qwen 3 4B",
      licenseName: "Apache License 2.0",
      url: ModelRegistry.qwen34B.modelInfoURL,
      text: """
        Qwen 3 is released by Alibaba Cloud under the Apache License 2.0.

        The model file is downloaded from Hugging Face (Qwen/Qwen3-4B-GGUF) \
        at your request; Pastura does not redistribute it.
        """,
      links: [
        LicenseLink(
          label: "Apache License 2.0",
          url: URL(string: "https://www.apache.org/licenses/LICENSE-2.0"))
      ],
      modelID: ModelRegistry.qwen34B.id)
  ]
}
