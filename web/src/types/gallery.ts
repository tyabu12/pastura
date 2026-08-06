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
  source_field: string;
  text: string;
}

export interface ScenarioHighlight {
  schema_version: number;
  source: { model: string; run_id: string; generated_at: string };
  excerpt: HighlightExcerptEntry[];
  yaml_hook: { fragment: string; caption: string };
  teaser: string;
}
