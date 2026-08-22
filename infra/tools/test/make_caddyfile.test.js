// The hostnames here are the ones printed on posters, so the failure this
// guards against is not "the config is ugly" — it is a wall full of QR codes
// pointing at a name the server does not answer to.

import test from 'node:test';
import assert from 'node:assert/strict';

import {
  defaultStaffUrl,
  hostOf,
  parseEnv,
  renderCaddyfile,
  readShops,
} from '../make_caddyfile.js';

const SHOPS_DIR = new URL('../../shops', import.meta.url).pathname;

test('parseEnv reads the shapes the shop files actually use', () => {
  const env = parseEnv(`
# a comment
SHOP_NAME='Schnittwerk'
SHOP_TAGLINE="Friseur & Barbier"
BOOKING_URL=https://schnittwerk.example.de
EMPTY=''
SPACED = ignored because of the key regex
APOSTROPHE="BaBa'Ssam"
TRAILING=value # with a comment
  `);

  assert.equal(env.SHOP_NAME, 'Schnittwerk');
  assert.equal(env.SHOP_TAGLINE, 'Friseur & Barbier');
  assert.equal(env.BOOKING_URL, 'https://schnittwerk.example.de');
  assert.equal(env.EMPTY, '');
  assert.equal(env.APOSTROPHE, "BaBa'Ssam");
  assert.equal(env.TRAILING, 'value');
  assert.ok(!('a comment' in env));
});

test('hostOf refuses anything it would have to guess about', () => {
  assert.equal(hostOf('https://x.example.de', 'BOOKING_URL', 's'),
    'x.example.de');
  assert.equal(hostOf('https://x.example.de/', 'BOOKING_URL', 's'),
    'x.example.de');

  assert.throws(() => hostOf('', 'BOOKING_URL', 's'), /is not set/);
  assert.throws(() => hostOf('schnittwerk.de', 'BOOKING_URL', 's'),
    /is not a URL/);
  // A poster printed with http:// would be a downgrade nobody notices.
  assert.throws(() => hostOf('http://x.example.de', 'BOOKING_URL', 's'),
    /must be https/);
});

test('the staff panel defaults to a sibling hostname', () => {
  assert.equal(defaultStaffUrl('https://schnittwerk.terminplaner.haey.eu'),
    'https://schnittwerk-team.terminplaner.haey.eu');
  assert.equal(defaultStaffUrl('https://termine.schnittwerk.de'),
    'https://termine-team.schnittwerk.de');
});

test('customer and staff never share an origin', () => {
  // Same origin would put the customer app's manage tokens and the staff
  // session in one localStorage.
  for (const shop of readShops(SHOPS_DIR)) {
    assert.notEqual(shop.customerHost, shop.staffHost,
      `${shop.slug} serves both apps from one origin`);
  }
});

test('every shop in the repo generates a usable site block', () => {
  const shops = readShops(SHOPS_DIR);
  assert.ok(shops.length > 0, 'there is at least one shop configured');

  const caddyfile = renderCaddyfile(shops, { root: '/srv/terminplaner' });

  for (const shop of shops) {
    assert.match(caddyfile, new RegExp(`^${shop.customerHost} \\{`, 'm'));
    assert.match(caddyfile, new RegExp(`^${shop.staffHost} \\{`, 'm'));
    assert.ok(caddyfile.includes(`/srv/terminplaner/${shop.slug}/customer`));
    assert.ok(caddyfile.includes(`/srv/terminplaner/${shop.slug}/staff`));
  }

  // Braces balance, or Caddy refuses the whole file.
  const opens = (caddyfile.match(/\{/g) ?? []).length;
  const closes = (caddyfile.match(/\}/g) ?? []).length;
  assert.equal(opens, closes, 'unbalanced braces');
});

test('the entry points are never long-cached', () => {
  // Flutter does not content-hash main.dart.js, and a cached service worker
  // can never replace itself — a shop would be pinned to the build they first
  // loaded and every later fix would be invisible to them.
  const caddyfile = renderCaddyfile(readShops(SHOPS_DIR), {});

  for (const path of ['/index.html', '/main.dart.js',
    '/flutter_service_worker.js', '/version.json']) {
    assert.ok(caddyfile.includes(path), `${path} is not in the no-cache set`);
  }
  assert.match(caddyfile, /header @revalidate Cache-Control "no-cache"/);
});

test('the staff panel asks not to be indexed', () => {
  const caddyfile = renderCaddyfile([{
    slug: 'x',
    name: 'X',
    customerHost: 'x.example.de',
    staffHost: 'x-team.example.de',
  }], {});

  const staffBlock = caddyfile.slice(caddyfile.indexOf('x-team.example.de'));
  const customerBlock = caddyfile.slice(
    caddyfile.indexOf('x.example.de {'),
    caddyfile.indexOf('x-team.example.de'));

  assert.match(staffBlock, /X-Robots-Tag "noindex, nofollow"/);
  assert.ok(!customerBlock.includes('X-Robots-Tag'),
    'the booking page should be findable');
});

test('no shops yields a valid, empty file rather than a crash', () => {
  const out = renderCaddyfile([], {});
  assert.match(out, /No shops configured yet/);
});

// --- behind an existing reverse proxy ----------------------------------------
//
// A box that already runs Nginx Proxy Manager has no free 80 or 443. Caddy
// becomes an internal origin instead, and the failure to avoid is it trying to
// bind 443 anyway and refusing to start.

const ONE_SHOP = [{
  slug: 'babassam',
  name: "BaBa'Ssam",
  customerHost: 'babassam.example.de',
  staffHost: 'babassam-team.example.de',
}];

test('an internal origin binds the given port and no other', () => {
  const out = renderCaddyfile(ONE_SHOP, { listen: 8080 });

  assert.match(out, /^http:\/\/babassam\.example\.de:8080 \{/m);
  assert.match(out, /^http:\/\/babassam-team\.example\.de:8080 \{/m);
  // No bare hostname site address, which is what would make Caddy want 443.
  assert.ok(!/^babassam\.example\.de \{/m.test(out));
});

test('auto_https is off so Caddy does not fight the proxy for 443', () => {
  const out = renderCaddyfile(ONE_SHOP, { listen: 8080 });
  assert.match(out, /\{\n\tauto_https off\n\}/);
});

test('the header warns that the port must not be public', () => {
  // It answers for every hostname without checking a certificate, so exposing
  // it turns the box into an open proxy for the whole domain.
  const out = renderCaddyfile(ONE_SHOP, { listen: 8080 });
  assert.match(out, /must NOT be reachable from the internet/);
});

test('routing still happens by Host, so one proxy entry covers every shop', () => {
  const out = renderCaddyfile([
    ...ONE_SHOP,
    {
      slug: 'schnittwerk',
      name: 'Schnittwerk',
      customerHost: 'schnittwerk.example.de',
      staffHost: 'schnittwerk-team.example.de',
    },
  ], { listen: 8080 });

  // Four distinct hosts, one port.
  const addresses = [...out.matchAll(/^http:\/\/(\S+):8080 \{/gm)]
    .map((m) => m[1]);
  assert.equal(new Set(addresses).size, 4);
  assert.equal((out.match(/:8080 \{/g) ?? []).length, 4);
});

test('without --listen nothing about the standalone setup changes', () => {
  const out = renderCaddyfile(ONE_SHOP, {});

  assert.match(out, /^babassam\.example\.de \{/m);
  assert.ok(!out.includes('auto_https off'));
  assert.ok(!out.includes(':8080'));
});

test('no access log is configured', () => {
  // Caddy could not write the per-shop log files, which is how this surfaced.
  // The fix was to stop writing them: an access log is a record of which IP
  // asked for a barber's booking page and when, kept indefinitely, on a
  // product that tells shops it collects the appointment and nothing else.
  // It appeared in no TOM annex and no Datenschutzerklärung, because nobody
  // decided to create it.
  const caddyfile = renderCaddyfile(readShops(SHOPS_DIR), { listen: 8080 });

  assert.ok(!caddyfile.includes('/var/log/'), 'writes a log file');
  assert.ok(!/^\s*log \{/m.test(caddyfile), 'has a log directive');
});

test('every site block closes cleanly', () => {
  // Removing the log directive left a dangling blank line before the brace.
  // Harmless, but caddy fmt rewrites it and then warns on every deploy.
  const caddyfile = renderCaddyfile(readShops(SHOPS_DIR), { listen: 8080 });
  assert.ok(!caddyfile.includes('\n\n}'), 'blank line before a closing brace');
});

test('the SPA fallback never answers for an asset', () => {
  // A blanket `try_files {path} /index.html` returns index.html with a 200 for
  // a missing .js or .wasm. The engine then parses HTML as JavaScript, the
  // page goes blank, and every request in the network tab looks successful.
  // This is how a wrong CanvasKit path presented as an unexplained blank page.
  const caddyfile = renderCaddyfile(readShops(SHOPS_DIR), { listen: 8080 });

  // The directive, not the word — it is named in a comment explaining why
  // it is not used.
  assert.ok(!/^\s*try_files/m.test(caddyfile), 'blanket fallback is back');
  assert.match(caddyfile, /@navigation \{/);
  assert.match(caddyfile, /header Accept \*text\/html\*/);
  assert.match(caddyfile, /rewrite @navigation \/index\.html/);
});
