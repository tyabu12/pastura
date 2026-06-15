// @ts-check
import { defineConfig } from 'astro/config';

// Public pastura.app site. Behavior-preserving migration of the former
// hand-written `pages/` tree (issue #475). The @astrojs/sitemap integration
// is wired in a later commit.
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
});
