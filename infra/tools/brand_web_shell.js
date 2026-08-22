// Brands the HTML shell around a built Flutter web app.
//
// `flutter build web` copies web/index.html and web/manifest.json verbatim, and
// those are still the stock template: the title is "babassam", the description
// is "A new Flutter project." and the theme colour is Flutter blue. The Dart
// side of a shop build is fully branded while the shell is not, so a prospect
// scans their own QR code, gets their own colours — and a browser tab that says
// someone else's shop name. Link previews and the PWA install prompt read from
// exactly these fields.
//
// Post-processing the output rather than templating web/index.html keeps the
// tracked file a normal Flutter template that `flutter run` still works with.
//
//   node infra/tools/brand_web_shell.js --dir build/shops/x/customer \
//     --shop "Schnittwerk" --tagline "Friseur & Barbier" --primary 1A3A5C

import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';

import { parseArgs, parseHex, escapeHtml } from './make_poster.js';

/// The letter that goes in the tab. First letter of the first word, because
/// "Schnitt & Werk" should read S, not S&W.
export function initialOf(shop) {
  const first = String(shop).trim().split(/\s+/)[0] ?? '';
  return [...first][0]?.toUpperCase() ?? '?';
}

/// A favicon that needs no image library: a rounded square in the shop's
/// colour with its initial. SVG favicons are supported by every current
/// browser, and this is the part of the shell a person actually sees.
export function faviconSvg({ shop, primary, surface }) {
  const bg = parseHex(primary)?.hex ?? '#6E1A1F';
  const fg = parseHex(surface)?.hex ?? '#FBF6EB';
  const initial = escapeHtml(initialOf(shop));

  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64">
  <rect width="64" height="64" rx="14" fill="${bg}"/>
  <text x="32" y="33" fill="${fg}" font-family="Georgia, 'Times New Roman', serif"
        font-size="38" font-weight="700" text-anchor="middle"
        dominant-baseline="central">${initial}</text>
</svg>
`;
}

export function brandIndexHtml(html, { shop, tagline, primary }) {
  const title = escapeHtml(shop);
  const description = escapeHtml(
    tagline ? `${shop} — ${tagline}. Termin online buchen.`
      : `${shop} — Termin online buchen.`);
  const themeColor = parseHex(primary)?.hex ?? '#6E1A1F';

  let out = html
    .replace(/<title>[\s\S]*?<\/title>/, `<title>${title}</title>`)
    .replace(
      /<meta name="description" content="[^"]*">/,
      `<meta name="description" content="${description}">`)
    .replace(
      /<meta name="apple-mobile-web-app-title" content="[^"]*">/,
      `<meta name="apple-mobile-web-app-title" content="${title}">`);

  // The status bar behind a PWA, and the browser chrome tint on Android.
  if (/<meta name="theme-color"/.test(out)) {
    out = out.replace(/<meta name="theme-color" content="[^"]*">/,
      `<meta name="theme-color" content="${themeColor}">`);
  } else {
    out = out.replace(/<meta charset="UTF-8">/,
      `<meta charset="UTF-8">\n  ` +
      `<meta name="theme-color" content="${themeColor}">`);
  }

  // Prefer the generated SVG, keep the PNG as the fallback for anything old.
  if (!/rel="icon" type="image\/svg\+xml"/.test(out)) {
    out = out.replace(
      /<link rel="icon" type="image\/png" href="favicon.png"\/>/,
      '<link rel="icon" type="image/svg+xml" href="favicon.svg"/>\n  ' +
      '<link rel="icon" type="image/png" href="favicon.png"/>');
  }

  return out;
}

export function brandManifest(json, { shop, tagline, primary, surface }) {
  const manifest = JSON.parse(json);

  manifest.name = shop;
  manifest.short_name = shop;
  manifest.description = tagline
    ? `${shop} — ${tagline}. Termin online buchen.`
    : `${shop} — Termin online buchen.`;
  manifest.theme_color = parseHex(primary)?.hex ?? '#6E1A1F';
  manifest.background_color = parseHex(surface)?.hex ?? '#FBF6EB';

  return `${JSON.stringify(manifest, null, 4)}\n`;
}

export function brandDirectory(dir, config) {
  const touched = [];

  const indexPath = join(dir, 'index.html');
  if (existsSync(indexPath)) {
    writeFileSync(indexPath,
      brandIndexHtml(readFileSync(indexPath, 'utf8'), config), 'utf8');
    touched.push('index.html');
  }

  const manifestPath = join(dir, 'manifest.json');
  if (existsSync(manifestPath)) {
    writeFileSync(manifestPath,
      brandManifest(readFileSync(manifestPath, 'utf8'), config), 'utf8');
    touched.push('manifest.json');
  }

  writeFileSync(join(dir, 'favicon.svg'), faviconSvg(config), 'utf8');
  touched.push('favicon.svg');

  return touched;
}

function main(argv) {
  const args = parseArgs(argv);

  if (!args.dir || !args.shop) {
    console.error('Usage: brand_web_shell.js --dir <build-dir> --shop <name> ' +
      '[--tagline <t>] [--primary <hex>] [--surface <hex>]');
    process.exit(1);
  }
  if (!existsSync(args.dir)) {
    console.error(`No such directory: ${args.dir}`);
    process.exit(1);
  }

  const touched = brandDirectory(args.dir, args);
  console.log(`  branded ${touched.join(', ')}`);
}

if (import.meta.url === `file://${process.argv[1]}`) {
  main(process.argv.slice(2));
}
