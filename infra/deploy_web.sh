#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Upload built shop sites to the web server.
# -----------------------------------------------------------------------------
# Runs from your machine, not from CI and not from a container: it needs an SSH
# agent holding a key the server trusts. Nothing here reads a password, and no
# credentials belong in this repo — connection details live in the gitignored
# infra/hosting.env (copy hosting.env.example).
#
# Usage:
#   ./deploy_web.sh                 # every shop that has been built
#   ./deploy_web.sh schnittwerk     # one shop
#   ./deploy_web.sh --caddy         # regenerate the Caddyfile and reload
#   ./deploy_web.sh --dry-run       # show what would change, transfer nothing
#
# Deploying a shop uploads the customer site and the staff site to
# $DEPLOY_ROOT/<slug>/{customer,staff}, deleting files that are no longer part
# of the build. It never touches another shop's directory.
# -----------------------------------------------------------------------------
set -eu

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
CONFIG="$HERE/hosting.env"

if [ ! -f "$CONFIG" ]; then
  echo "No infra/hosting.env." >&2
  echo "  cp infra/hosting.env.example infra/hosting.env  and fill it in." >&2
  exit 1
fi
# shellcheck disable=SC1090
. "$CONFIG"

: "${DEPLOY_HOST:?DEPLOY_HOST is not set in infra/hosting.env}"
: "${DEPLOY_USER:?DEPLOY_USER is not set in infra/hosting.env}"
DEPLOY_ROOT="${DEPLOY_ROOT:-/srv/terminplaner}"
# Set when something else already owns 80/443 — Nginx Proxy Manager, Traefik.
# Caddy then serves plain HTTP on this port and the proxy in front does TLS.
CADDY_PORT="${CADDY_PORT:-}"
SSH_PORT="${SSH_PORT:-22}"
TARGET="$DEPLOY_USER@$DEPLOY_HOST"

for tool in rsync ssh; do
  command -v "$tool" >/dev/null 2>&1 || {
    echo "$tool is not installed." >&2
    exit 1
  }
done

DRY=""
ARG="${1:-}"
if [ "$ARG" = "--dry-run" ]; then
  DRY="--dry-run"
  ARG=""
  echo "(dry run — nothing will be transferred)"
fi

ssh_run() { ssh -p "$SSH_PORT" "$TARGET" "$@"; }

# ── Caddyfile ─────────────────────────────────────────────────────────────────
#
# Generated from the shop configs so the served hostnames and the ones printed
# on posters cannot drift apart. Validated before reload: a syntax error would
# otherwise take every shop offline at once.

deploy_caddy() {
  echo "==> Caddyfile"
  local tmp
  tmp="$(mktemp)"
  if [ -n "$CADDY_PORT" ]; then
    node "$HERE/tools/make_caddyfile.js" --root "$DEPLOY_ROOT" \
      --listen "$CADDY_PORT" > "$tmp"
  else
    node "$HERE/tools/make_caddyfile.js" --root "$DEPLOY_ROOT" > "$tmp"
  fi

  rsync -e "ssh -p $SSH_PORT" $DRY "$tmp" "$TARGET:/tmp/Caddyfile.new"
  rm -f "$tmp"
  [ -n "$DRY" ] && return 0

  # Each sudo here needs a matching line in /etc/sudoers.d/terminplaner —
  # see infra/HOSTING.md. reload-or-restart rather than reload, because a
  # Caddy that never started has nothing to reload.
  ssh_run "sudo cp /tmp/Caddyfile.new /etc/caddy/Caddyfile \
    && sudo caddy fmt --overwrite /etc/caddy/Caddyfile \
    && sudo caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile \
    && sudo systemctl reload-or-restart caddy"
  echo "    reloaded"
}

if [ "$ARG" = "--caddy" ]; then
  deploy_caddy
  exit 0
fi

# ── sites ─────────────────────────────────────────────────────────────────────

deploy_shop() {
  local slug="$1"
  local src="$ROOT/build/shops/$slug"

  if [ ! -d "$src" ]; then
    echo "  $slug: not built — run ./infra/build_shop.sh $slug" >&2
    return 1
  fi

  echo "==> $slug"
  for app in customer staff; do
    [ -d "$src/$app" ] || continue
    # A stale index.html left behind by --delete-less rsync is exactly the file
    # that would keep serving an old build forever.
    rsync -az --delete $DRY \
      -e "ssh -p $SSH_PORT" \
      "$src/$app/" "$TARGET:$DEPLOY_ROOT/$slug/$app/"
    echo "    $app"
  done
}

if [ -n "$ARG" ]; then
  SLUGS="$ARG"
else
  SLUGS="$(ls "$ROOT/build/shops" 2>/dev/null || true)"
  [ -n "$SLUGS" ] || {
    echo "Nothing built yet. Run ./infra/build_shop.sh <slug> first." >&2
    exit 1
  }
fi

[ -n "$DRY" ] || ssh_run "mkdir -p $DEPLOY_ROOT"

for slug in $SLUGS; do
  deploy_shop "$slug"
done

echo
echo "Done. If you added a shop, also run:  ./deploy_web.sh --caddy"
