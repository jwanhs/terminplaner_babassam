// Points the built app at its own copy of the CanvasKit renderer.
//
// Two things reference it and only one of them listens to a build flag:
//
//   main.dart.js        compiled Dart, so --dart-define=FLUTTER_WEB_CANVASKIT_URL
//                       replaces the default at compile time
//   flutter.js          copied verbatim out of the SDK, so it keeps whatever
//   flutter_bootstrap.js the SDK shipped — a gstatic.com URL
//
// Leaving those two is not harmless. Whether they are reached depends on which
// loader path runs, and "probably unused" is not something to put in a
// Datenschutzerklärung. Rewriting the string means there is no Google URL in
// the artefact at all, which is a claim that can be checked with grep rather
// than reasoned about.
//
//   node infra/tools/localise_canvaskit.js --dir build/shops/x/customer

import { readFileSync, writeFileSync, readdirSync, statSync, existsSync }
  from 'node:fs';
import { join, extname } from 'node:path';

import { parseArgs } from './make_poster.js';

/// The versioned CDN path Flutter's engine ships with. The hash pins the
/// renderer to the engine build, which is exactly why the local copy has to
/// come out of the same SDK rather than be downloaded once and reused.
// Two shapes appear in a real build. main.dart.js carries the whole URL with
// the engine hash baked in; flutter.js and flutter_bootstrap.js carry only the
// prefix and append the revision at runtime:
//
//   I("https://www.gstatic.com/flutter-canvaskit", e.engineRevision)
//
// so the hash is optional here. Missing that is why the first version of this
// found nothing while the guard rejected the same three files.
const CANVASKIT_CDN =
  /https:\/\/www\.gstatic\.com\/flutter-canvaskit(?:\/[0-9a-fA-F]+)?\/?/g;

// The CanvasKit font fallback. When a glyph is in none of the bundled fonts,
// the engine downloads a Noto face for it — from Google, at the moment the
// customer types a name containing that glyph.
//
//   s = s.fontFallbackBaseUrl; return s == null ? "https://fonts.gstatic.com/s/" : s
//
// Nothing sets the config, so that default IS the live value: rewriting it
// changes behaviour, not only the text. With no fonts served at the new
// address the download fails and the glyph renders as a box — which is the
// right trade for a German booking page whose bundled fonts already cover
// Latin, and the wrong one for a shop with Arabic-script clientele. See
// legal/README.md.
const FONT_FALLBACK_CDN = /https:\/\/fonts\.gstatic\.com\/s\/?/g;

// Flutter's loader decides where to get the renderer from:
//
//   i.canvasKitBaseUrl ? i.canvasKitBaseUrl
//     : e.engineRevision && !e.useLocalCanvasKit ? I(<cdn>, e.engineRevision)
//     : "canvaskit"
//
// so the flag in the build config picks the branch. Without it set, the middle
// branch runs and appends the engine revision to whatever base it is given —
// which is why rewriting the URL alone produced a request for
// /canvaskit/<revision>/canvaskit.js and a blank page. Setting the flag takes
// the last branch, a plain relative "canvaskit", which is where the files are.
//
// --no-web-resources-cdn is supposed to set this at build time. It did not on
// the toolchain this was first run against, so it is set here where the result
// can be checked rather than assumed.
const BUILD_CONFIG = /(_flutter\.buildConfig\s*=\s*\{)/g;

const REWRITABLE = new Set(['.js', '.html', '.json']);

/// Anything pointing at Google's static host, whatever its shape. Used to
/// tell "there is nothing to do" apart from "there is something here I do not
/// recognise" — the second silently looked like the first until a real build
/// disagreed with the guard that runs straight afterwards.
const ANY_GSTATIC = /gstatic\.com/g;

export function localiseText(text, base = '/canvaskit/', fontBase = '/fonts/') {
  return useLocalCanvasKit(text)
    .replace(CANVASKIT_CDN, base)
    .replace(FONT_FALLBACK_CDN, fontBase);
}

/// Adds `useLocalCanvasKit` to Flutter's build config. Idempotent, so a second
/// pass over an already-published build changes nothing.
export function useLocalCanvasKit(text) {
  // The QUOTED key, as it appears in the JSON config. Testing for the bare
  // identifier matches `!e.useLocalCanvasKit` in the loader function a few
  // hundred characters later, so the guard fires on every file and the flag is
  // never written — which looks exactly like it worked.
  if (text.includes('"useLocalCanvasKit"')) return text;
  return text.replace(BUILD_CONFIG, '$1"useLocalCanvasKit":true,');
}

export function findCdnRefs(text) {
  const needsFlag =
    BUILD_CONFIG.test(text) && !text.includes('"useLocalCanvasKit"');
  BUILD_CONFIG.lastIndex = 0;
  return [
    ...(text.match(CANVASKIT_CDN) ?? []),
    ...(text.match(FONT_FALLBACK_CDN) ?? []),
    ...(needsFlag ? ['buildConfig'] : []),
  ];
}

/**
 * References to gstatic that [localiseText] does not know how to rewrite.
 *
 * Returned with surrounding text, because the useful question is never "is
 * there one" but "what shape is it" — a URL built by concatenating a version
 * variable needs different handling from a literal one.
 *
 * @returns {string[]} up to `limit` excerpts, each with the match in context
 */
export function findUnrewritable(text, limit = 3) {
  const rewritten = localiseText(text);
  // eslint-disable-next-line no-unused-vars
  const excerpts = [];

  for (const match of rewritten.matchAll(ANY_GSTATIC)) {
    if (excerpts.length >= limit) break;
    const from = Math.max(0, match.index - 70);
    const to = Math.min(rewritten.length, match.index + 90);
    excerpts.push(rewritten.slice(from, to).replace(/\s+/g, ' '));
  }
  return excerpts;
}

function* walk(dir) {
  for (const entry of readdirSync(dir)) {
    const path = join(dir, entry);
    if (statSync(path).isDirectory()) {
      yield* walk(path);
    } else {
      yield path;
    }
  }
}

/**
 * Rewrites every CDN reference under `dir` to `base`.
 *
 * @returns {{file: string, count: number}[]} what was changed
 */
export function localiseDirectory(dir, base = '/canvaskit/',
  fontBase = '/fonts/') {
  const changed = [];

  for (const path of walk(dir)) {
    if (!REWRITABLE.has(extname(path))) continue;

    const before = readFileSync(path, 'utf8');
    const refs = findCdnRefs(before);
    if (refs.length === 0) continue;

    writeFileSync(path, localiseText(before, base, fontBase), 'utf8');
    changed.push({ file: path, count: refs.length });
  }

  return changed;
}

/// A rewrite pointing at a directory that is not there would turn a working
/// app into a blank page, so this is checked before anything is edited.
export function hasLocalCanvaskit(dir) {
  return existsSync(join(dir, 'canvaskit', 'canvaskit.js'))
    || existsSync(join(dir, 'canvaskit', 'canvaskit.wasm'));
}

function main(argv) {
  const args = parseArgs(argv);
  const dir = args.dir;
  const base = args.base ?? '/canvaskit/';
  const fontBase = args['font-base'] ?? '/fonts/';

  if (!dir) {
    console.error('Usage: localise_canvaskit.js --dir <build-dir> [--base /canvaskit/]');
    process.exit(1);
  }

  if (!hasLocalCanvaskit(dir)) {
    console.error(`No canvaskit/ in ${dir} — refusing to rewrite the URL to a`);
    console.error('path that would 404. Run: flutter precache --web');
    process.exit(1);
  }

  const changed = localiseDirectory(dir, base, fontBase);
  const total = changed.reduce((sum, c) => sum + c.count, 0);

  for (const { file, count } of changed) {
    console.log(`    ${file.split('/').pop()}: ${count} → ${base}`);
  }
  if (total === 0) {
    console.log('    no known CanvasKit CDN pattern found');
  }

  // Whatever is left over, the ship-guard is about to reject — so say what it
  // is here, where the file is still open, rather than leaving a grep to
  // whoever reads the refusal.
  const leftovers = [];
  for (const path of walk(dir)) {
    if (!REWRITABLE.has(extname(path))) continue;
    const excerpts = findUnrewritable(readFileSync(path, 'utf8'));
    if (excerpts.length > 0) leftovers.push({ path, excerpts });
  }

  if (leftovers.length > 0) {
    console.error('');
    console.error('    Unrecognised gstatic references remain:');
    for (const { path, excerpts } of leftovers) {
      console.error(`      ${path.split('/').pop()}`);
      for (const excerpt of excerpts) console.error(`        …${excerpt}…`);
    }
    console.error('');
    if (leftovers.some((l) => l.excerpts.some(
      (e) => e.includes('fonts.gstatic.com')))) {
      console.error('    fonts.gstatic.com is the CanvasKit font FALLBACK, not');
      console.error('    the renderer — a different fix. See legal/README.md.');
    } else {
      console.error('    Add the shape to CANVASKIT_CDN in this file, with a');
      console.error('    case in test/localise_canvaskit.test.js.');
    }
    process.exit(1);
  }
}

if (import.meta.url === `file://${process.argv[1]}`) {
  main(process.argv.slice(2));
}
