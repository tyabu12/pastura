// Shape of an entry in the curated gallery index (docs/gallery/gallery.json),
// narrowed to the fields the share landing pages consume. The JSON carries
// more fields (category, author, yaml_url, …) — this is a structural subset,
// which is all `getStaticPaths` and ScenarioLanding need (#1071).
export interface GalleryScenario {
  id: string;
  title: string;
  description: string;
  agent_count: number;
  rounds: number;
  language: string;
}

export interface GalleryIndex {
  scenarios: GalleryScenario[];
}

// Shape of a curated highlight file (docs/gallery/highlights/<id>.json,
// ADR-029 Decision 1), narrowed to the fields the web landing page renders.
// The file carries more (scenario_ref, window_override, content_filter_applied)
// which only the repo-side gallery gate and the app consume. The web build
// reads repo state that already passed the gate, so it does not re-validate
// the spoiler rules or the hashes (ADR-029 Decision 2 / Decision 5).
export interface HighlightExcerptEntry {
  agent: string;
  round: number;
  phase: string;
  phase_index: number;
  // The speaker's index in the scenario's `personas:` list, which is what a real
  // run resolves the avatar colour slot from. Carried in the file rather than
  // inferred here — see the `toneFor` comment in ScenarioLanding.astro.
  persona_index: number;
  source_field: string;
  text: string;
}

export interface ScenarioHighlight {
  schema_version: number;
  source: { model: string; run_id: string; generated_at: string };
  excerpt: HighlightExcerptEntry[];
  // `kind` is `persona` or `raw` (ADR-029 Decision 1). The web renders every
  // hook as YAML regardless — it has no editor to show a persona fragment's
  // meaning in, which is the whole reason the app diverges here
  // (§ Amendment 2026-08-08). Nothing on this side branches on it, and
  // `loadHighlight`'s runtime guard does not check it either, so this field is
  // documentation of the on-disk shape rather than a verified property of the
  // parsed value — the repo-side gate is what makes it true.
  yaml_hook: { kind: string; fragment: string; caption: string };
  teaser: string;
}
