// What build_shop.sh actually hands to Flutter.
//
// This exists because of a real failure: the defines were assembled into a
// string and expanded unquoted, so the first value containing a space —
// SHOP_TAGLINE='Der Friseursalon' — arrived as two arguments and Flutter
// reported
//
//   Target file "Friseursalon" not found.
//
// which names neither the variable nor the cause. Shell word splitting is
// invisible until a value has a space in it, and shop names and taglines are
// exactly the values that will.
//
// So: run the real script against a stub `flutter` that records its argv, and
// assert on the arguments rather than on the script's text.

import test from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { mkdtempSync, writeFileSync, readFileSync, chmodSync, mkdirSync,
  rmSync, existsSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const REPO = new URL('../../..', import.meta.url).pathname.replace(/\/$/, '');
const BUILD_SHOP = join(REPO, 'infra', 'build_shop.sh');

// A tagline with a space, a shop name with an apostrophe, and a colour that
// must survive intact — the three shapes most likely to be mangled on the way
// through a shell.
const SHOP_ENV = `
SHOP_NAME="BaBa'Ssam & Söhne"
SHOP_TAGLINE='Der Friseursalon'
SHOP_TIMEZONE='Europe/Berlin'
BOOKING_URL='https://test.example.de'
STAFF_URL='https://test-team.example.de'
SHOP_PRIMARY='1A3A5C'
APPWRITE_ENDPOINT='https://cloud.appwrite.io/v1'
APPWRITE_PROJECT_ID='test-project'
`;

/// A stand-in for flutter that logs its arguments and produces just enough
/// output for the branding and the Google check to run against.
function stubFlutter(dir, logPath, { supportsCdnFlag = true } = {}) {
  const bin = join(dir, 'bin');
  mkdirSync(bin, { recursive: true });

  const script = `#!/usr/bin/env bash
set -eu

# build_shop.sh probes for --no-web-resources-cdn before using it. Answer the
# probe, and keep it out of the argv log so it is not mistaken for a build.
for a in "$@"; do
  if [ "$a" = "--help" ]; then
${supportsCdnFlag ? '    echo "  --no-web-resources-cdn  Use local resources"' : '    echo "  --release  Build a release version"'}
    exit 0
  fi
done

{
  echo "--- invocation ---"
  for a in "$@"; do printf '%s\\n' "$a"; done
} >> "${logPath}"

out=""
prev=""
for a in "$@"; do
  if [ "$prev" = "--output" ]; then out="$a"; fi
  prev="$a"
done

if [ -n "$out" ]; then
  mkdir -p "$out/canvaskit"
  cp "${REPO}/web/index.html" "$out/index.html"
  cp "${REPO}/web/manifest.json" "$out/manifest.json"
  echo '// canvaskit' > "$out/canvaskit/canvaskit.js"
  # What a real build leaves behind, and what the ship-guard caught.
  echo 'var base="https://www.gstatic.com/flutter-canvaskit/abc123def456/";' \
    > "$out/flutter.js"
  echo 'load("https://www.gstatic.com/flutter-canvaskit/abc123def456/ck.js")' \
    > "$out/main.dart.js"
fi
`;
  const path = join(bin, 'flutter');
  writeFileSync(path, script, 'utf8');
  chmodSync(path, 0o755);
  return bin;
}

function runBuild(slug = 'test-shop', options = {}) {
  const work = mkdtempSync(join(tmpdir(), 'build-shop-'));
  const shops = join(work, 'shops');
  mkdirSync(shops, { recursive: true });
  writeFileSync(join(shops, `${slug}.env`), SHOP_ENV, 'utf8');

  const log = join(work, 'argv.log');
  const bin = stubFlutter(work, log, options);

  execFileSync('bash', [BUILD_SHOP, slug], {
    env: {
      ...process.env,
      PATH: `${bin}:${process.env.PATH}`,
      SHOPS_DIR: shops,
    },
    stdio: 'pipe',
  });

  // Split the log into one array of arguments per flutter invocation.
  const invocations = readFileSync(log, 'utf8')
    .split('--- invocation ---')
    .map((block) => block.split('\n').filter(Boolean))
    .filter((args) => args.length > 0);

  return { invocations, work, slug };
}

let built;
try {
  built = runBuild();
} catch (error) {
  built = { error };
}

test('the script runs to completion against a stub toolchain', () => {
  if (built.error) {
    assert.fail(`build_shop.sh failed:\n${built.error.stderr ?? built.error}`);
  }
  assert.equal(built.invocations.length, 2, 'customer and staff');
});

test('a value containing a space arrives as ONE argument', () => {
  // The regression. As a string this became "--dart-define=SHOP_TAGLINE=Der"
  // followed by a bare "Friseursalon".
  for (const args of built.invocations) {
    assert.ok(
      args.includes('--dart-define=SHOP_TAGLINE=Der Friseursalon'),
      'the tagline was split across arguments');
    assert.ok(
      !args.includes('Friseursalon'),
      'a bare word Flutter would read as a target file');
  }
});

test('an apostrophe and an ampersand survive intact', () => {
  for (const args of built.invocations) {
    assert.ok(args.includes("--dart-define=SHOP_NAME=BaBa'Ssam & Söhne"));
  }
});

test('no argument is empty or stray', () => {
  for (const args of built.invocations) {
    for (const arg of args) {
      assert.notEqual(arg.trim(), '', 'empty argument');
      // Everything is either a flag, a value for one, or the subcommand.
      assert.ok(
        arg.startsWith('--') || ['build', 'web'].includes(arg)
          || args[args.indexOf(arg) - 1]?.startsWith('--'),
        `unexpected bare argument: ${arg}`);
    }
  }
});

test('unset values are left out rather than passed empty', () => {
  // The Dart side has its own defaults; an empty define would override them
  // with the empty string and, for a colour, silently drop the house brand.
  for (const args of built.invocations) {
    assert.ok(!args.some((a) => /^--dart-define=[A-Z_]+=$/.test(a)),
      'an empty define was passed');
    assert.ok(!args.some((a) => a.startsWith('--dart-define=SHOP_SURFACE=')),
      'SHOP_SURFACE is unset in the fixture and should be absent');
  }
});

test('the two apps differ only by APP_MODE', () => {
  const [customer, staff] = built.invocations;
  const defines = (args) =>
    args.filter((a) => a.startsWith('--dart-define=')).sort();

  const onlyInStaff = defines(staff)
    .filter((d) => !defines(customer).includes(d));
  const onlyInCustomer = defines(customer)
    .filter((d) => !defines(staff).includes(d));

  assert.deepEqual(onlyInStaff, ['--dart-define=APP_MODE=staff']);
  assert.deepEqual(onlyInCustomer, []);
});

test('each app is built to its own output directory', () => {
  const outputs = built.invocations.map(
    (args) => args[args.indexOf('--output') + 1]);

  assert.equal(new Set(outputs).size, 2);
  assert.ok(outputs.every((o) => existsSync(join(o, 'index.html'))));
  // And the shell got branded on the way out.
  const html = readFileSync(join(outputs[0], 'index.html'), 'utf8');
  assert.match(html, /<title>BaBa&#039;Ssam &amp; Söhne<\/title>|<title>BaBa'Ssam &amp; Söhne<\/title>/);
});

test('the CanvasKit CDN reference is gone from the shipped build', () => {
  // The end of the chain the ship-guard enforces: Flutter emits a gstatic URL,
  // the build copies canvaskit locally, rewrites the references, and only then
  // does assert_no_google let the build through. If any link breaks the script
  // exits non-zero and the first test in this file fails instead.
  const outputs = built.invocations.map(
    (args) => args[args.indexOf('--output') + 1]);

  for (const out of outputs) {
    for (const name of ['flutter.js', 'main.dart.js']) {
      const text = readFileSync(join(out, name), 'utf8');
      assert.ok(!text.includes('gstatic.com'), `${name} still points at Google`);
      assert.match(text, /\/canvaskit\//);
    }
    assert.ok(existsSync(join(out, 'canvaskit', 'canvaskit.js')),
      'the renderer is served from our own origin');
  }
});

test('the renderer URL is passed to the compiler too', () => {
  for (const args of built.invocations) {
    assert.ok(
      args.includes('--dart-define=FLUTTER_WEB_CANVASKIT_URL=/canvaskit/'),
      'compiled Dart would keep the gstatic default without this');
  }
});

test('the local-resources flag is passed when Flutter supports it', () => {
  // The flag is what flips useLocalCanvasKit, which decides the branch that
  // actually runs. The URL rewrite only cleans up the dead one.
  for (const args of built.invocations) {
    assert.ok(args.includes('--no-web-resources-cdn'));
  }
});

test('a Flutter without that flag still builds', () => {
  // The probe exists so an older toolchain degrades to the rewrite alone
  // rather than dying on an unknown option. This also covers expanding an
  // empty bash array under `set -u`, which is its own way to fail.
  const older = runBuild('test-shop-older', { supportsCdnFlag: false });
  try {
    assert.equal(older.invocations.length, 2);
    for (const args of older.invocations) {
      assert.ok(!args.includes('--no-web-resources-cdn'));
      assert.ok(args.includes('--release'), 'still a real build');
    }
  } finally {
    rmSync(older.work, { recursive: true, force: true });
    rmSync(join(REPO, 'build', 'shops', 'test-shop-older'),
      { recursive: true, force: true });
  }
});

test.after(() => {
  if (built.work) rmSync(built.work, { recursive: true, force: true });
  if (built.slug) {
    rmSync(join(REPO, 'build', 'shops', built.slug),
      { recursive: true, force: true });
  }
});
