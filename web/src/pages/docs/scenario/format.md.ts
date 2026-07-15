import type { APIRoute } from 'astro';
import raw from '../../../content/scenario-format.en.md?raw';

// Raw Markdown endpoint at /docs/scenario/format.md — the LLM-friendly source
// the in-app "Copy Gen Prompt" points at (#1120). Same Markdown file the
// format.astro page renders as HTML, so the two views cannot drift.
// `prerender: true` keeps this a static file under the default (static) build.
export const prerender = true;

export const GET: APIRoute = () =>
  new Response(raw, {
    headers: { 'content-type': 'text/markdown; charset=utf-8' },
  });
