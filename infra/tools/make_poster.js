// Turns a shop's booking URL into something you can print and leave behind.
//
// Output is one HTML file with two print pages: an A4 wall poster for beside
// the mirror, and a sheet of four A6 table stands. Open it, hit print — that
// is the whole kit. No fonts, images or scripts are fetched, so it renders the
// same on a shop's ancient laptop as on yours.
//
//   node infra/tools/make_poster.js \
//     --url https://schnittwerk.terminplaner.de \
//     --shop "Schnittwerk" --tagline "Friseur & Barbier" \
//     --primary 6E1A1F --secondary C9A961 \
//     --out build/schnittwerk/poster.html

import { writeFileSync, mkdirSync } from 'node:fs';
import { dirname } from 'node:path';

import { encodeQr, qrToSvg } from './qr.js';

// ─── colour ────────────────────────────────────────────────────────────────────

export function parseHex(raw) {
  const s = String(raw ?? '').trim().replace(/^#/, '');
  if (!/^[0-9a-fA-F]{6}$/.test(s)) return null;
  return {
    r: parseInt(s.slice(0, 2), 16),
    g: parseInt(s.slice(2, 4), 16),
    b: parseInt(s.slice(4, 6), 16),
    hex: `#${s.toUpperCase()}`,
  };
}

/// WCAG relative luminance.
export function luminance({ r, g, b }) {
  const channel = (v) => {
    const c = v / 255;
    return c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4;
  };
  return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b);
}

export function contrastRatio(a, b) {
  const la = luminance(a);
  const lb = luminance(b);
  const [light, dark] = la > lb ? [la, lb] : [lb, la];
  return (light + 0.05) / (dark + 0.05);
}

/// A QR code printed in a shop's brand colours is a nicer object than a black
/// square, but only while it still scans. Phone cameras binarise on luminance,
/// so a mid-tone brand colour on a cream ground is exactly the poster that
/// works on your phone in the shop and fails on a customer's in January.
///
/// The rule: use the brand colours when they clear 7:1, otherwise keep the
/// shop's paper and drop the modules to near-black. Prints stay on-brand
/// where that is safe, and legible where it is not.
export function chooseQrColors(primaryHex, surfaceHex) {
  const primary = parseHex(primaryHex) ?? parseHex('1A1A1A');
  const surface = parseHex(surfaceHex) ?? parseHex('FFFFFF');
  const ratio = contrastRatio(primary, surface);

  if (ratio >= 7) {
    return { dark: primary.hex, light: surface.hex, ratio, brandUsed: true };
  }
  const fallback = parseHex('141414');
  return {
    dark: fallback.hex,
    light: surface.hex,
    ratio: contrastRatio(fallback, surface),
    brandUsed: false,
  };
}

// ─── rendering ─────────────────────────────────────────────────────────────────

export function escapeHtml(value) {
  return String(value ?? '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

/// The URL without its scheme — what a person reads and types, as opposed to
/// what the QR carries.
export function displayUrl(url) {
  return String(url).replace(/^https?:\/\//, '').replace(/\/$/, '');
}

export function renderPoster(config) {
  const {
    url,
    shop,
    tagline = '',
    primary = '6E1A1F',
    secondary = 'C9A961',
    surface = 'FBF6EB',
    ink = '2A1810',
  } = config;

  if (!url) throw new Error('a booking URL is required');
  if (!shop) throw new Error('a shop name is required');

  const colors = chooseQrColors(primary, surface);

  // Error-correction level H on print: a poster beside a barber's chair gets
  // sprayed, taped over at the corner and sun-bleached, and H tolerates about
  // 30% of the symbol being unreadable. The URL is short, so the extra
  // redundancy costs a version bump and nothing else.
  const symbol = encodeQr(url, { ecl: 'H' });
  const qr = qrToSvg(symbol, {
    scale: 8,
    margin: 4,
    dark: colors.dark,
    light: colors.light,
  });

  const brand = {
    primary: parseHex(primary)?.hex ?? '#6E1A1F',
    secondary: parseHex(secondary)?.hex ?? '#C9A961',
    surface: parseHex(surface)?.hex ?? '#FBF6EB',
    ink: parseHex(ink)?.hex ?? '#2A1810',
  };

  const name = escapeHtml(shop);
  const sub = escapeHtml(tagline);
  const readable = escapeHtml(displayUrl(url));

  const card = () => `
      <div class="card">
        <div class="card-name">${name}</div>
        <div class="card-qr">${qr}</div>
        <div class="card-cta">Termin online buchen</div>
        <div class="card-url">${readable}</div>
      </div>`;

  return `<!doctype html>
<html lang="de">
<head>
<meta charset="utf-8">
<title>${name} — Aushang &amp; Tischaufsteller</title>
<style>
  :root {
    --primary: ${brand.primary};
    --secondary: ${brand.secondary};
    --surface: ${brand.surface};
    --ink: ${brand.ink};
  }

  * { box-sizing: border-box; margin: 0; padding: 0; }

  body {
    font-family: "Helvetica Neue", Helvetica, Arial, sans-serif;
    color: var(--ink);
    background: #6b6b6b;
  }

  .page {
    width: 210mm;
    height: 297mm;
    margin: 8mm auto;
    background: var(--surface);
    position: relative;
    overflow: hidden;
    page-break-after: always;
  }

  /* ── A4 wall poster ── */

  .poster {
    display: flex;
    flex-direction: column;
    align-items: center;
    text-align: center;
    padding: 22mm 18mm 16mm;
  }

  .rule {
    width: 28mm;
    height: 1.4mm;
    background: var(--secondary);
    margin: 6mm 0;
  }

  .shop {
    font-size: 15mm;
    font-weight: 700;
    letter-spacing: -0.4mm;
    color: var(--primary);
    line-height: 1.05;
  }

  .tagline {
    font-size: 5mm;
    letter-spacing: 1.6mm;
    text-transform: uppercase;
    margin-top: 3mm;
    opacity: 0.65;
  }

  .headline {
    font-size: 11mm;
    font-weight: 700;
    line-height: 1.15;
    margin-top: 2mm;
  }

  /* The SVG carries the standard's four-module quiet zone already, so the
     padding here is framing, not clearance — keep it small or the code ends
     up small. */
  .qr {
    margin: 8mm 0 7mm;
    padding: 3mm;
    background: ${colors.light};
    border: 0.8mm solid var(--secondary);
  }

  .qr svg { display: block; width: 100mm; height: 100mm; }

  .steps {
    display: flex;
    gap: 8mm;
    margin-bottom: 8mm;
  }

  .step {
    flex: 1;
    font-size: 4.4mm;
    line-height: 1.35;
  }

  .step-num {
    display: block;
    font-size: 7mm;
    font-weight: 700;
    color: var(--secondary);
    margin-bottom: 1.5mm;
  }

  .url {
    font-size: 5.4mm;
    font-weight: 600;
    letter-spacing: 0.2mm;
    padding: 3mm 6mm;
    border: 0.5mm solid var(--primary);
    color: var(--primary);
  }

  .footnote {
    margin-top: auto;
    font-size: 4mm;
    opacity: 0.6;
  }

  /* ── A6 table stands, four to a sheet ── */

  .cards {
    display: grid;
    grid-template-columns: 1fr 1fr;
    grid-template-rows: 1fr 1fr;
  }

  .card {
    border: 0.3mm dashed rgba(0, 0, 0, 0.25);
    padding: 10mm 8mm;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    text-align: center;
    gap: 4mm;
  }

  .card-name {
    font-size: 7mm;
    font-weight: 700;
    color: var(--primary);
  }

  .card-qr svg { display: block; width: 46mm; height: 46mm; }

  .card-cta { font-size: 4.6mm; font-weight: 600; }

  .card-url { font-size: 3.8mm; opacity: 0.7; }

  @page { size: A4; margin: 0; }

  @media print {
    body { background: none; }
    .page { margin: 0; }
  }
</style>
</head>
<body>

<section class="page poster">
  <div class="shop">${name}</div>
  ${sub ? `<div class="tagline">${sub}</div>` : ''}
  <div class="rule"></div>
  <h1 class="headline">Termin online buchen</h1>

  <div class="qr">${qr}</div>

  <div class="steps">
    <div class="step"><span class="step-num">1</span>Code scannen</div>
    <div class="step"><span class="step-num">2</span>Uhrzeit wählen</div>
    <div class="step"><span class="step-num">3</span>Fertig</div>
  </div>

  <div class="url">${readable}</div>

  <p class="footnote">Keine App, kein Konto — einfach mit der Kamera scannen.</p>
</section>

<section class="page cards">
  ${[0, 1, 2, 3].map(() => card()).join('')}
</section>

</body>
</html>
`;
}

// ─── CLI ───────────────────────────────────────────────────────────────────────

export function parseArgs(argv) {
  const args = {};
  for (let i = 0; i < argv.length; i++) {
    const token = argv[i];
    if (!token.startsWith('--')) continue;
    const eq = token.indexOf('=');
    if (eq !== -1) {
      args[token.slice(2, eq)] = token.slice(eq + 1);
    } else {
      args[token.slice(2)] = argv[i + 1];
      i++;
    }
  }
  return args;
}

const USAGE = `
Usage: node make_poster.js --url <booking-url> --shop <name> [options]

  --url        Booking URL the QR points at            (required)
  --shop       Shop name printed on the poster         (required)
  --tagline    Line under the name                     (optional)
  --primary    Brand colour, hex                       (default 6E1A1F)
  --secondary  Accent colour, hex                      (default C9A961)
  --surface    Paper colour, hex                       (default FBF6EB)
  --ink        Body text colour, hex                   (default 2A1810)
  --out        File to write            (default build/<shop>/poster.html)
`.trim();

function main(argv) {
  const args = parseArgs(argv);

  if (args.help !== undefined || !args.url || !args.shop) {
    console.error(USAGE);
    process.exit(args.url && args.shop ? 0 : 1);
  }

  const html = renderPoster(args);
  const slug = args.shop.toLowerCase().replace(/[^a-z0-9]+/g, '-')
    .replace(/^-|-$/g, '');
  const out = args.out ?? `build/${slug}/poster.html`;

  mkdirSync(dirname(out), { recursive: true });
  writeFileSync(out, html, 'utf8');

  const colors = chooseQrColors(args.primary ?? '6E1A1F',
    args.surface ?? 'FBF6EB');
  console.log(`Wrote ${out}`);
  console.log(`  QR contrast ${colors.ratio.toFixed(1)}:1 ` +
    `(${colors.brandUsed ? 'brand colour' : 'near-black fallback'})`);
  console.log('  Open it in a browser and print — page 1 is the A4 wall ' +
    'poster, page 2 is four table stands.');
}

if (import.meta.url === `file://${process.argv[1]}`) {
  main(process.argv.slice(2));
}
