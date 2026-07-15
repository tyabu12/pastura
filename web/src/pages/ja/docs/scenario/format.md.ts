import type { APIRoute } from 'astro';
import raw from '../../../../content/scenario-format.ja.md?raw';

// Raw Markdown endpoint at /ja/docs/scenario/format.md — JA mirror of the raw
// source the in-app "Copy Gen Prompt" points at (#1120). Same Markdown file the
// ja format.astro page renders as HTML, so the two views cannot drift.
export const prerender = true;

export const GET: APIRoute = () =>
  new Response(raw, {
    headers: { 'content-type': 'text/markdown; charset=utf-8' },
  });
