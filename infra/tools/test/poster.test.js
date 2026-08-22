// The poster is the thing you hand a shop owner, so the failure that matters
// is a code that does not scan. The contrast guard is what stands between a
// brand-coloured poster and an unscannable one, and it is what these tests
// spend most of their effort on.

import test from 'node:test';
import assert from 'node:assert/strict';

import {
  chooseQrColors,
  contrastRatio,
  displayUrl,
  escapeHtml,
  luminance,
  parseArgs,
  parseHex,
  renderPoster,
} from '../make_poster.js';

test('parseHex accepts what a build flag carries and rejects the rest', () => {
  assert.deepEqual(parseHex('6E1A1F'),
    { r: 0x6e, g: 0x1a, b: 0x1f, hex: '#6E1A1F' });
  assert.equal(parseHex('#c9a961').hex, '#C9A961');
  assert.equal(parseHex(''), null);
  assert.equal(parseHex('nope'), null);
  assert.equal(parseHex('#12345'), null);
  assert.equal(parseHex(undefined), null);
});

test('contrast ratio matches the WCAG reference points', () => {
  const white = parseHex('FFFFFF');
  const black = parseHex('000000');

  assert.equal(luminance(white), 1);
  assert.equal(luminance(black), 0);
  assert.equal(contrastRatio(white, black), 21);
  assert.equal(contrastRatio(white, white), 1);
  // Order must not matter.
  assert.equal(contrastRatio(black, white), contrastRatio(white, black));
});

test('a dark brand colour is kept for the QR modules', () => {
  // Oxblood on ivory — the house brand, comfortably past 7:1.
  const chosen = chooseQrColors('6E1A1F', 'FBF6EB');

  assert.equal(chosen.brandUsed, true);
  assert.equal(chosen.dark, '#6E1A1F');
  assert.equal(chosen.light, '#FBF6EB');
  assert.ok(chosen.ratio >= 7);
});

test('a mid-tone brand colour falls back to near-black', () => {
  // The poster that scans on your phone in the shop and fails on a
  // customer's in bad light. Antique gold on ivory is about 2:1.
  const chosen = chooseQrColors('C9A961', 'FBF6EB');

  assert.equal(chosen.brandUsed, false);
  assert.equal(chosen.dark, '#141414');
  assert.equal(chosen.light, '#FBF6EB', 'the shop keeps its paper colour');
  assert.ok(chosen.ratio >= 7, 'the fallback itself clears the bar');
});

test('the guard holds across a sweep of brand colours', () => {
  const surface = 'FFFFFF';
  for (const hex of ['000000', '6E1A1F', 'C9A961', 'FFFF00', '1A73E8',
    '888888', 'E8E8E8', '2A1810', '4CAF50']) {
    const chosen = chooseQrColors(hex, surface);
    const dark = parseHex(chosen.dark);
    const light = parseHex(chosen.light);

    assert.ok(contrastRatio(dark, light) >= 7,
      `${hex} produced a ${chosen.ratio.toFixed(1)}:1 code`);
  }
});

test('a malformed colour does not produce an unreadable poster', () => {
  const chosen = chooseQrColors('not-a-colour', undefined);
  assert.ok(chosen.ratio >= 7);
  assert.equal(chosen.light, '#FFFFFF');
});

test('displayUrl strips what a person would not read aloud', () => {
  assert.equal(displayUrl('https://schnittwerk.terminplaner.de'),
    'schnittwerk.terminplaner.de');
  assert.equal(displayUrl('http://example.de/'), 'example.de');
});

test('shop names are escaped, not injected', () => {
  assert.equal(escapeHtml('Schmitt & Söhne'), 'Schmitt &amp; Söhne');
  assert.equal(escapeHtml('<script>'), '&lt;script&gt;');

  const html = renderPoster({
    url: 'https://example.de',
    shop: 'Schmitt & Söhne <b>',
  });
  assert.ok(!html.includes('<b>'), 'raw markup must not reach the page');
  assert.ok(html.includes('Schmitt &amp; Söhne &lt;b&gt;'));
});

test('the poster carries both print pages and no external requests', () => {
  const html = renderPoster({
    url: 'https://schnittwerk.terminplaner.de',
    shop: 'Schnittwerk',
    tagline: 'Friseur & Barbier',
    primary: '1A3A5C',
    secondary: 'C9A961',
  });

  assert.ok(html.startsWith('<!doctype html>'));
  assert.match(html, /@page \{ size: A4; margin: 0; \}/);
  assert.match(html, /class="page poster"/);
  assert.match(html, /class="page cards"/);
  assert.match(html, /Termin online buchen/);
  assert.match(html, /schnittwerk\.terminplaner\.de/);

  // Five symbols: one on the poster, four on the table stands.
  assert.equal(html.match(/<svg /g).length, 5);

  // Nothing may be fetched at print time — a shop's laptop is often offline
  // and a half-rendered poster is worse than a plain one.
  assert.ok(!/https?:\/\/(?!schnittwerk|www\.w3\.org)/.test(
    html.replace(/schnittwerk\.terminplaner\.de/g, '')),
  'no external assets');
  assert.ok(!html.includes('<script'), 'no scripts');
});

test('a poster needs a URL and a name', () => {
  assert.throws(() => renderPoster({ shop: 'Schnittwerk' }), /URL is required/);
  assert.throws(() => renderPoster({ url: 'https://example.de' }),
    /name is required/);
});

test('parseArgs handles both --flag value and --flag=value', () => {
  assert.deepEqual(
    parseArgs(['--url', 'https://example.de', '--shop=Schnittwerk',
      '--tagline', 'Friseur']),
    { url: 'https://example.de', shop: 'Schnittwerk', tagline: 'Friseur' });
});
