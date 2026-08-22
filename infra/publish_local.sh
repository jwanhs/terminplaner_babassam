#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Build and publish a shop from the machine that also serves it.
# -----------------------------------------------------------------------------
# The counterpart to deploy_web.sh, for the case where there is one box and no
# separate build machine: no SSH, no rsync over the network, no hosting.env, no
# sudoers rule. It builds, installs into the web root, regenerates the Caddyfile
# and reloads.
#
#   ./infra/publish_local.sh babassam
#   ./infra/publish_local.sh babassam --poster-only   # print kit only, no Flutter
#
# Configuration, all optional:
#   SITE_ROOT    where the sites are served from   (default /srv/terminplaner)
#   CADDY_PORT   set when something else owns 80/443 — Nginx Proxy Manager,
#                Traefik. Caddy then serves plain HTTP on this port as an
#                internal origin. (default: read from infra/hosting.env)
#
# Run it as the ordinary user that owns SITE_ROOT, not as root: Flutter refuses
# to build as root, and the files only need to be readable by Caddy.
# -----------------------------------------------------------------------------
set -eu

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"

SLUG="${1:-}"
MODE="${2:-all}"

if [ -z "$SLUG" ] || [ "$SLUG" = "--help" ]; then
  sed -n '2,21p' "$0" | sed 's/^# \{0,1\}//'
  exit 1
fi

# hosting.env is about SSH, but it is also where CADDY_PORT is written down.
# Reuse it when it exists so the two paths cannot disagree about the port.
if [ -f "$HERE/hosting.env" ]; then
  # shellcheck disable=SC1090
  . "$HERE/hosting.env"
fi

SITE_ROOT="${SITE_ROOT:-${DEPLOY_ROOT:-/srv/terminplaner}}"
CADDY_PORT="${CADDY_PORT:-}"

# Only the app build cares — the print kit is Node and runs as anyone.
if [ "$MODE" != "--poster-only" ] && [ "$(id -u)" = "0" ]; then
  echo "Do not run this as root — Flutter refuses to build as root." >&2
  echo "Run it as the user that owns $SITE_ROOT." >&2
  exit 1
fi

# ── build ─────────────────────────────────────────────────────────────────────

"$HERE/build_shop.sh" "$SLUG" ${MODE:+"$MODE"}

if [ "$MODE" = "--poster-only" ]; then
  echo
  echo "Print kit only: $ROOT/build/shops/$SLUG/poster.html"
  exit 0
fi

# ── install ───────────────────────────────────────────────────────────────────

echo
echo "==> Installing into $SITE_ROOT/$SLUG"

if [ ! -w "$(dirname "$SITE_ROOT")" ] && [ ! -w "$SITE_ROOT" ]; then
  echo "$SITE_ROOT is not writable by $(whoami)." >&2
  echo "  sudo mkdir -p $SITE_ROOT && sudo chown -R $(whoami) $SITE_ROOT" >&2
  exit 1
fi

mkdir -p "$SITE_ROOT/$SLUG"
for app in customer staff; do
  [ -d "$ROOT/build/shops/$SLUG/$app" ] || continue
  # --delete so a file dropped from the build cannot keep being served. An old
  # index.html surviving a deploy is exactly the file that serves yesterday's
  # app forever.
  rsync -a --delete \
    "$ROOT/build/shops/$SLUG/$app/" "$SITE_ROOT/$SLUG/$app/"
  echo "    $app"
done

# ── reload ────────────────────────────────────────────────────────────────────
#
# Generated for every shop at once, so a syntax error would take them all down
# together — hence validating before the reload rather than after.

echo
echo "==> Caddyfile"

TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

if [ -n "$CADDY_PORT" ]; then
  node "$HERE/tools/make_caddyfile.js" --root "$SITE_ROOT" \
    --listen "$CADDY_PORT" > "$TMP"
else
  node "$HERE/tools/make_caddyfile.js" --root "$SITE_ROOT" > "$TMP"
fi

sudo cp "$TMP" /etc/caddy/Caddyfile
# Let Caddy format its own file rather than trying to match its formatter from
# a generator that cannot run it — otherwise every deploy prints a fmt warning,
# and warnings you always see are warnings you stop reading.
sudo caddy fmt --overwrite /etc/caddy/Caddyfile
sudo caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile

# reload-or-restart, not reload: a fresh Caddy install fails to start when
# something else already holds :80, so the service is inactive the first time
# and there is nothing to reload. Restarting starts it.
sudo systemctl reload-or-restart caddy

if ! systemctl is-active --quiet caddy; then
  echo >&2
  echo "caddy did not come up. What it says:" >&2
  sudo journalctl -u caddy -n 20 --no-pager >&2
  exit 1
fi

echo
echo "-----------------------------------------------------------------------"
echo "  Live from $SITE_ROOT/$SLUG"
echo
echo "  Print kit: $ROOT/build/shops/$SLUG/poster.html"
echo "  Copy it to a machine with a printer:"
echo "    scp $(whoami)@<this-host>:$ROOT/build/shops/$SLUG/poster.html ."
echo "-----------------------------------------------------------------------"
