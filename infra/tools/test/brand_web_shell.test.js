// The shell is the part of a demo nobody checks and everybody sees: the
// browser tab, the link preview, the install prompt. These tests run against
// the real stock Flutter template from web/, so they fail if a Flutter upgrade
// changes the shape of the file the branding relies on.

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

import {
  brandIndexHtml,
  brandManifest,
  faviconSvg,
  initialOf,
} from '../brand_web_shell.js';

const TEMPLATE_HTML = readFileSync(
  new URL('../../../web/index.html', import.meta.url), 'utf8');
const TEMPLATE_MANIFEST = readFileSync(
  new URL('../../../web/manifest.json', import.meta.url), 'utf8');

const SHOP = {
  shop: 'Schnittwerk',
  tagline: 'Friseur & Barbier',
  primary: '1A3A5C',
  surface: 'F5F1E8',
};

test('the tracked template is still the shape the branding expects', () => {
  // If a Flutter upgrade rewrites these, the replacements below silently do
  // nothing and every shop ships the stock shell again.
  assert.match(TEMPLATE_HTML, /<title>[\s\S]*?<\/title>/);
  assert.match(TEMPLATE_HTML, /<meta name="description" content="[^"]*">/);
  assert.match(TEMPLATE_HTML,
    /<meta name="apple-mobile-web-app-title" content="[^"]*">/);
  assert.match(TEMPLATE_HTML, /<meta charset="UTF-8">/);
  assert.doesNotThrow(() => JSON.parse(TEMPLATE_MANIFEST));
});

test('index.html carries the shop, not the reference deployment', () => {
  const out = brandIndexHtml(TEMPLATE_HTML, SHOP);

  assert.match(out, /<title>Schnittwerk<\/title>/);
  assert.ok(!out.includes('babassam'), 'no trace of the reference shop');
  assert.ok(!out.includes('A new Flutter project'),
    'the stock description is gone');
  assert.match(out, /<meta name="description" content="Schnittwerk —/);
  assert.match(out,
    /<meta name="apple-mobile-web-app-title" content="Schnittwerk">/);
  assert.match(out, /<meta name="theme-color" content="#1A3A5C">/);
  assert.match(out, /<link rel="icon" type="image\/svg\+xml"/);
  // The PNG stays as the fallback rather than being replaced.
  assert.match(out, /<link rel="icon" type="image\/png"/);
});

test('branding twice changes nothing the second time', () => {
  const once = brandIndexHtml(TEMPLATE_HTML, SHOP);
  const twice = brandIndexHtml(once, SHOP);
  assert.equal(once, twice);
});

test('a shop name with markup in it is escaped', () => {
  const out = brandIndexHtml(TEMPLATE_HTML,
    { ...SHOP, shop: 'Schmitt & Söhne <b>' });

  assert.ok(!out.includes('<b>'), 'raw markup must not reach the shell');
  assert.match(out, /<title>Schmitt &amp; Söhne &lt;b&gt;<\/title>/);
});

test('manifest.json drives the install prompt', () => {
  const manifest = JSON.parse(brandManifest(TEMPLATE_MANIFEST, SHOP));

  assert.equal(manifest.name, 'Schnittwerk');
  assert.equal(manifest.short_name, 'Schnittwerk');
  assert.match(manifest.description, /^Schnittwerk — Friseur & Barbier/);
  assert.equal(manifest.theme_color, '#1A3A5C');
  assert.equal(manifest.background_color, '#F5F1E8');
  // Whatever else the template carries must survive.
  assert.equal(manifest.display, 'standalone');
  assert.ok(Array.isArray(manifest.icons) && manifest.icons.length > 0);
});

test('a missing tagline does not leave a dangling dash', () => {
  const manifest = JSON.parse(
    brandManifest(TEMPLATE_MANIFEST, { ...SHOP, tagline: undefined }));
  assert.equal(manifest.description, 'Schnittwerk — Termin online buchen.');
});

test('the favicon initial comes from the first word', () => {
  assert.equal(initialOf('Schnittwerk'), 'S');
  assert.equal(initialOf('Schnitt & Werk'), 'S');
  assert.equal(initialOf("BaBa'Ssam"), 'B');
  assert.equal(initialOf('  ätherisch'), 'Ä');
  assert.equal(initialOf(''), '?');
});

test('the favicon is self-contained SVG in the brand colours', () => {
  const svg = faviconSvg(SHOP);

  assert.ok(svg.startsWith('<svg'));
  assert.match(svg, /fill="#1A3A5C"/);
  assert.match(svg, /fill="#F5F1E8"/);
  assert.match(svg, />S<\/text>/);
  // The xmlns is a namespace identifier, not a request. Anything that would
  // actually be fetched arrives via href, src or url().
  assert.ok(!/(href|src)\s*=|url\(/.test(svg), 'nothing fetched');
});
