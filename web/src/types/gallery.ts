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
