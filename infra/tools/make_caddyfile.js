// Generates the Caddyfile for every shop in infra/shops/.
//
// The hostnames come from each shop's own BOOKING_URL and STAFF_URL, which are
// the same values the QR code is printed from. That is the point: a poster on a
// wall is the one artefact you cannot revise, so the served hostname and the
// printed one are read from a single field rather than kept in step by hand.
//
//   node infra/tools/make_caddyfile.js --root /srv/terminplaner > Caddyfile
//
// Behind an existing reverse proxy — Nginx Proxy Manager, Traefik, anything
// already holding 80 and 443 — pass --listen 8080. Caddy then serves plain
// HTTP on that port as an internal origin and the proxy in front keeps the
// certificates. Routing still happens here, by Host header, which is what
// lets one proxy entry cover every shop.

import { readFileSync, readdirSync } from 'node:fs';
import { basename, join } from 'node:path';

import { parseArgs } from './make_poster.js';

/// A deliberately small reader for the shop .env files. They are shell, but
/// the fields this needs are plain assignments; anything computed would not
/// belong in a hostname anyway.
export function parseEnv(text) {
  const out = {};
  for (const raw of text.split('\n')) {
    const line = raw.trim();
    if (!line || line.startsWith('#')) continue;

    const eq = line.indexOf('=');
    if (eq === -1) continue;

    const key = line.slice(0, eq).trim();
    if (!/^[A-Z_][A-Z0-9_]*$/.test(key)) continue;

    let value = line.slice(eq + 1).trim();
    const quote = value[0];
    if (quote === "'" || quote === '"') {
      const end = value.lastIndexOf(quote);
      value = end > 0 ? value.slice(1, end) : value.slice(1);
    } else {
      value = value.split(' #')[0].trim();
    }
    out[key] = value;
  }
  return out;
}

/// The hostname a URL serves under. Throws rather than guessing, because a
/// silently wrong host means a printed QR code that resolves nowhere.
export function hostOf(url, field, slug) {
  if (!url) throw new Error(`${slug}: ${field} is not set`);
  let parsed;
  try {
    parsed = new URL(url);
  } catch {
    throw new Error(`${slug}: ${field} is not a URL: ${url}`);
  }
  if (parsed.protocol !== 'https:') {
    throw new Error(`${slug}: ${field} must be https, got ${parsed.protocol}`);
  }
  return parsed.hostname;
}

/// Where the staff panel lives when a shop has not said otherwise:
/// schnittwerk.example.de → schnittwerk-team.example.de.
export function defaultStaffUrl(bookingUrl) {
  const parsed = new URL(bookingUrl);
  const [first, ...rest] = parsed.hostname.split('.');
  parsed.hostname = [`${first}-team`, ...rest].join('.');
  return parsed.toString().replace(/\/$/, '');
}

export function readShops(dir) {
  return readdirSync(dir)
    .filter((f) => f.endsWith('.env') && !f.startsWith('_'))
    .sort()
    .map((file) => {
      const slug = basename(file, '.env');
      const env = parseEnv(readFileSync(join(dir, file), 'utf8'));
      const booking = env.BOOKING_URL;
      const staff = env.STAFF_URL || (booking ? defaultStaffUrl(booking) : '');
      return {
        slug,
        name: env.SHOP_NAME || slug,
        customerHost: hostOf(booking, 'BOOKING_URL', slug),
        staffHost: hostOf(staff, 'STAFF_URL', slug),
      };
    });
}

// Flutter's web output is not content-hashed — main.dart.js keeps its name
// across builds — so a long max-age on the entry points would pin a shop to
// the build they first loaded. index.html and the service worker especially:
// cache those and the app can never update itself.
const REVALIDATE = [
  '/', '/index.html', '/main.dart.js', '/flutter_bootstrap.js',
  '/flutter_service_worker.js', '/version.json', '/manifest.json',
];

const CACHEABLE = [
  '/assets/*', '/canvaskit/*', '/icons/*', '*.png', '*.svg', '*.ttf', '*.woff2',
];

// No access log on purpose.
//
// Caddy runs as its own user and could not write the per-shop log files, which
// is how this came up — but the fix is not a chown. An access log is a list of
// which IP address asked for a barber's booking page at what time, kept
// forever, on a product whose whole claim is that it collects the appointment
// and nothing else. It was not in the TOM annex, not in any shop's
// Datenschutzerklärung, and had no retention period, because nobody decided to
// create it.
//
// Errors and startup still reach journald, which is what you want at three in
// the afternoon when a shop says the page is blank. Turning request logging on
// for a debugging session is fine; leaving it on is a disclosure.
function siteBlock({ host, dir, label, noindex, listen }) {
  // An explicit http:// scheme is what stops Caddy trying to obtain its own
  // certificate for a hostname whose TLS is somebody else's job.
  const address = listen ? `http://${host}:${listen}` : host;
  return `# ${label}
${address} {
\troot * ${dir}
\tencode gzip zstd

\t# Fall back to index.html only for navigations, never for assets.
\t#
\t# A blanket try_files answers a missing .js or .wasm with index.html and a
\t# 200, so the engine parses HTML as JavaScript and the page goes blank with
\t# nothing in the network tab looking wrong. A missing asset has to 404.
\t@navigation {
\t\tnot file
\t\theader Accept *text/html*
\t}
\trewrite @navigation /index.html

\tfile_server

\theader {
\t\tStrict-Transport-Security "max-age=31536000; includeSubDomains"
\t\tX-Content-Type-Options "nosniff"
\t\tReferrer-Policy "strict-origin-when-cross-origin"
\t\tX-Frame-Options "SAMEORIGIN"
\t\t-Server${noindex ? '\n\t\tX-Robots-Tag "noindex, nofollow"' : ''}
\t}

\t@revalidate path ${REVALIDATE.join(' ')}
\theader @revalidate Cache-Control "no-cache"

\t@cacheable path ${CACHEABLE.join(' ')}
\theader @cacheable Cache-Control "public, max-age=86400"
}`;
}

export function renderCaddyfile(
  shops,
  { root = '/srv/terminplaner', listen = null } = {},
) {
  const flags = listen ? ` --listen ${listen}` : '';
  const header = listen
    ? `# Generated by infra/tools/make_caddyfile.js — do not edit by hand.
#
# Regenerate after adding a shop:
#   node infra/tools/make_caddyfile.js --root ${root}${flags} > Caddyfile
#
# Caddy is an INTERNAL ORIGIN here, serving plain HTTP on ${listen}. The proxy
# in front owns the certificates, so auto_https is off — left on, Caddy would
# try to bind 443 and fail to start because the proxy already has it.
#
# Routing is still by Host header, so one wildcard entry in the proxy covers
# every shop below and adding a shop needs no change there.
#
# Port ${listen} must NOT be reachable from the internet. It answers for every
# hostname without checking a certificate.

{
\tauto_https off
}
`
    : `# Generated by infra/tools/make_caddyfile.js — do not edit by hand.
#
# Regenerate after adding a shop:
#   node infra/tools/make_caddyfile.js --root ${root} > Caddyfile
#
# Caddy obtains a certificate per hostname over HTTP-01 on first request, so
# every host below needs a DNS record pointing here BEFORE Caddy is reloaded,
# and port 80 must stay reachable. If these names sit behind Cloudflare's
# proxy, set those records to DNS-only — otherwise Cloudflare answers the
# challenge and Caddy never gets a certificate.
`;

  if (shops.length === 0) {
    return `${header}\n# No shops configured yet.\n`;
  }

  const blocks = shops.flatMap((shop) => [
    siteBlock({
      host: shop.customerHost,
      dir: `${root}/${shop.slug}/customer`,
      label: `${shop.name} — customer`,
      noindex: false,
      listen,
    }),
    siteBlock({
      host: shop.staffHost,
      dir: `${root}/${shop.slug}/staff`,
      label: `${shop.name} — staff`,
      // The panel is for the shop, not for search results.
      noindex: true,
      listen,
    }),
  ]);

  return `${header}\n${blocks.join('\n\n')}\n`;
}

function main(argv) {
  const args = parseArgs(argv);
  const dir = args.shops
    ?? new URL('../shops', import.meta.url).pathname;

  const shops = readShops(dir);
  process.stdout.write(renderCaddyfile(shops, {
    root: args.root,
    listen: args.listen ? Number(args.listen) : null,
  }));
  console.error(`# ${shops.length} shop(s): ` +
    shops.map((s) => s.slug).join(', '));
}

if (import.meta.url === `file://${process.argv[1]}`) {
  main(process.argv.slice(2));
}
