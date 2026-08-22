// The shapes Flutter's own output actually contains, taken from a real build
// that the ship-guard rejected: main.dart.js, flutter.js and
// flutter_bootstrap.js all carried the versioned gstatic URL.

import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, writeFileSync, readFileSync, mkdirSync, rmSync }
  from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

import {
  findCdnRefs,
  findUnrewritable,
  useLocalCanvasKit,
  hasLocalCanvaskit,
  localiseDirectory,
  localiseText,
} from '../localise_canvaskit.js';

const HASH = '0ec0f1d0f0c1e0a0b0c0d0e0f0a0b0c0';
const CDN = `https://www.gstatic.com/flutter-canvaskit/${HASH}/`;

test('the versioned CDN path is rewritten wherever it appears', () => {
  assert.equal(localiseText(`"${CDN}"`), '"/canvaskit/"');
  assert.equal(localiseText(`"${CDN}canvaskit.js"`), '"/canvaskit/canvaskit.js"');
  // Without the trailing slash, as the bootstrap sometimes writes it.
  assert.equal(
    localiseText(`x="https://www.gstatic.com/flutter-canvaskit/${HASH}"`),
    'x="/canvaskit/"');
});

test('quoting survives the rewrite', () => {
  // The replacement goes inside an existing string literal in minified JS —
  // breaking out of it would be a syntax error in the app's entry point.
  const before = `var a='${CDN}canvaskit.js',b="${CDN}skwasm.js";`;
  const after = localiseText(before);

  assert.equal(after, "var a='/canvaskit/canvaskit.js',b=\"/canvaskit/skwasm.js\";");
  assert.equal((after.match(/'/g) ?? []).length, 2);
  assert.equal((after.match(/"/g) ?? []).length, 2);
});

test('a base href other than / is honoured', () => {
  assert.equal(localiseText(`"${CDN}"`, '/shop/canvaskit/'),
    '"/shop/canvaskit/"');
});

test('other Google URLs are left alone', () => {
  // This tool has one job. Fonts are handled by bundling, and a stray
  // rewrite of an unrelated URL would be worse than the reference it removed.
  const other = 'https://fonts.googleapis.com/css2?family=Inter';
  assert.equal(localiseText(other), other);
  assert.equal(findCdnRefs(other).length, 0);
});

test('a directory is rewritten file by file, and reported', () => {
  const dir = mkdtempSync(join(tmpdir(), 'canvaskit-'));
  try {
    mkdirSync(join(dir, 'canvaskit'), { recursive: true });
    writeFileSync(join(dir, 'canvaskit', 'canvaskit.js'), '// local', 'utf8');

    writeFileSync(join(dir, 'main.dart.js'), `load("${CDN}canvaskit.js")`, 'utf8');
    writeFileSync(join(dir, 'flutter.js'), `base="${CDN}"`, 'utf8');
    writeFileSync(join(dir, 'flutter_bootstrap.js'),
      `a="${CDN}";b="${CDN}skwasm.js"`, 'utf8');
    writeFileSync(join(dir, 'index.html'), '<html>clean</html>', 'utf8');
    // Binary-ish payloads must not be touched.
    writeFileSync(join(dir, 'app.wasm'), CDN, 'utf8');

    assert.ok(hasLocalCanvaskit(dir), 'the local copy is present');

    const changed = localiseDirectory(dir);
    const byName = Object.fromEntries(
      changed.map((c) => [c.file.split('/').pop(), c.count]));

    assert.deepEqual(byName, {
      'main.dart.js': 1,
      'flutter.js': 1,
      'flutter_bootstrap.js': 2,
    });

    // Nothing Google-shaped survives in the rewritable files.
    for (const name of ['main.dart.js', 'flutter.js', 'flutter_bootstrap.js']) {
      const text = readFileSync(join(dir, name), 'utf8');
      assert.ok(!text.includes('gstatic.com'), `${name} still references Google`);
      assert.ok(text.includes('/canvaskit/'));
    }
    // The untouched files are byte-identical.
    assert.equal(readFileSync(join(dir, 'index.html'), 'utf8'),
      '<html>clean</html>');
    assert.equal(readFileSync(join(dir, 'app.wasm'), 'utf8'), CDN);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test('a build with no local copy is detected before anything is rewritten', () => {
  // Rewriting to /canvaskit/ without the files there swaps a privacy problem
  // for a blank page — worse, and harder to notice.
  const dir = mkdtempSync(join(tmpdir(), 'canvaskit-'));
  try {
    writeFileSync(join(dir, 'flutter.js'), `base="${CDN}"`, 'utf8');
    assert.equal(hasLocalCanvaskit(dir), false);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test('running twice changes nothing the second time', () => {
  const once = localiseText(`"${CDN}canvaskit.js"`);
  assert.equal(localiseText(once), once);
});

test('the two shapes a real build contains are both handled', () => {
  // Taken verbatim from the build that failed the guard. The renderer URL is
  // a bare prefix with the revision appended at runtime — no hash to match on,
  // which is what the first version of this missed.
  const loader = 'canvasKitBaseUrl:e.engineRevision&&!e.useLocalCanvasKit'
    + '?I("https://www.gstatic.com/flutter-canvaskit",e.engineRevision)'
    + ':"canvaskit"}';
  // And the font fallback, which is a different fetch with a different fix.
  const fallback = 'return s==null?"https://fonts.gstatic.com/s/":s';

  assert.deepEqual(findUnrewritable(loader), []);
  assert.deepEqual(findUnrewritable(fallback), []);
  assert.match(localiseText(loader), /I\("\/canvaskit\/",e\.engineRevision\)/);
  assert.match(localiseText(fallback), /"\/fonts\/"/);
});

test('a shape it does not know is reported, not passed over', () => {
  // The failure this was added for: the rewriter found nothing, said so
  // cheerfully, and the guard two lines later rejected the same file. Silence
  // and success looked identical.
  const unknown = 'var u="https://www.gstatic.com/some-new-thing/v2/x.js";';

  assert.equal(findCdnRefs(unknown).length, 0, 'not a shape it knows');
  const leftovers = findUnrewritable(unknown);
  assert.equal(leftovers.length, 1);
  assert.match(leftovers[0], /some-new-thing/, 'the shape, not just the host');
});

test('a rewritten file reports nothing left over', () => {
  const literal = `a="${CDN}canvaskit.js"`;
  assert.deepEqual(findUnrewritable(literal), []);
});

test('the report is capped so a minified bundle stays readable', () => {
  const many = Array(20).fill('x="gstatic.com/y"').join(';');
  assert.equal(findUnrewritable(many).length, 3);
});

test('the build config gets the flag that picks the local renderer', () => {
  // Without it the loader appends the engine revision to whatever base it is
  // given, asks for /canvaskit/<revision>/canvaskit.js, and gets nothing.
  const config = '_flutter.buildConfig = {"engineRevision":"c416acf"};';
  const out = useLocalCanvasKit(config);

  assert.match(out, /\{"useLocalCanvasKit":true,"engineRevision"/);
  assert.doesNotThrow(() => JSON.parse(
    out.match(/buildConfig = (\{.*\});/)[1]), 'still valid JSON');
});

test('the flag is not added twice', () => {
  const once = useLocalCanvasKit('_flutter.buildConfig = {"a":1};');
  assert.equal(useLocalCanvasKit(once), once);
});

test('the loader mentioning useLocalCanvasKit does not block the flag', () => {
  // The guard has to look for the quoted JSON key. Matching the bare
  // identifier finds `!e.useLocalCanvasKit` in the loader a few hundred
  // characters later, so nothing is ever written — and it looks like it
  // worked.
  const real = '_flutter.buildConfig = {"engineRevision":"c416acf"};'
    + 'function E(i,e){return e.engineRevision&&!e.useLocalCanvasKit?x:"canvaskit"}';

  assert.match(useLocalCanvasKit(real), /"useLocalCanvasKit":true/);
});

test('a build config without the flag counts as work to do', () => {
  assert.ok(findCdnRefs('_flutter.buildConfig = {"a":1};').includes('buildConfig'));
  assert.deepEqual(
    findCdnRefs('_flutter.buildConfig = {"useLocalCanvasKit":true};'), []);
});
