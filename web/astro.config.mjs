// @ts-check
import { defineConfig } from 'astro/config';
import sitemap from '@astrojs/sitemap';

// Public pastura.app site. Behavior-preserving migration of the former
// hand-written `pages/` tree (issue #475).
//
// - `trailingSlash: 'always'` + `build.format: 'directory'` reproduce the
//   GitHub Pages directory-index URL shape the old site relied on
//   (`/support/`, `/ja/legal/privacy-policy/`). The ported pages keep their
//   original *relative* nav links verbatim, so the output directory nesting
//   must stay byte-identical for those links to resolve — these two settings
//   pin that nesting.
// - i18n: English at the root (no prefix), Japanese under `/ja/`, matching the
//   current URL layout. `site` drives canonical/OGP absolute URLs.
export default defineConfig({
  site: 'https://pastura.app',
  trailingSlash: 'always',
  build: {
    format: 'directory',
  },
  i18n: {
    defaultLocale: 'en',
    locales: ['en', 'ja'],
    routing: {
      prefixDefaultLocale: false,
    },
  },
  markdown: {
    // Markdown code fences (the `<Content />`-rendered scenario-format pages)
    // default to Shiki's `github-dark`, whose light tokens wash out on the
    // light `--page` background the prose shell forces. Pin `github-light` so
    // fences match the scenario guide, which highlights its YAML with an
    // explicit `<Code theme="github-light">` (#1120 follow-up).
    shikiConfig: {
      theme: 'github-light',
    },
  },
  integrations: [
    sitemap({
      // Preserve the deliberately-minimal `<url><loc>…</loc></url>` form the
      // hand-written sitemap.xml used (#473): no `lastmod` (Google ignores
      // inaccurate build-date lastmod — anti-pattern), no `changefreq` /
      // `priority` (ignored by Google). `serialize` strips everything but loc.
      //
      // The integration's `i18n` option is intentionally NOT passed: it would
      // inject `<xhtml:link rel="alternate" hreflang=…>` into the XML, but the
      // per-page HTML <head> is the single source of truth for language
      // variants (#473) — duplicating into XML adds drift risk with no gain.
      serialize: (item) => ({ url: item.url }),
    }),
  ],
});
