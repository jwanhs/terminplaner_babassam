#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Build one shop — customer web app, staff panel, and the printable QR kit.
# -----------------------------------------------------------------------------
# Every shop-specific value is a --dart-define, so this script is the whole of
# "onboarding a second shop": write infra/shops/<slug>.env, run this, upload
# the two directories it produces.
#
# Web rather than an app store on purpose. The customer app lives behind a QR
# code on a wall, which is a URL — going through App Store review to deliver a
# URL costs a developer account per shop and days of latency per change. Staff
# get the same build with APP_MODE=staff; it installs from the browser as a PWA
# if they want it on a home screen.
#
# Usage:
#   ./build_shop.sh schnittwerk               # customer + staff + poster
#   ./build_shop.sh schnittwerk --poster-only # just the print kit, no Flutter
#   ./build_shop.sh schnittwerk --customer-only
#
# Output:
#   build/shops/<slug>/customer/   static site — the QR points here
#   build/shops/<slug>/staff/      static site — the panel, behind a login
#   build/shops/<slug>/poster.html A4 wall poster + four A6 table stands
# -----------------------------------------------------------------------------
set -eu

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"

SLUG="${1:-}"
MODE="${2:-all}"

if [ -z "$SLUG" ] || [ "$SLUG" = "--help" ]; then
  sed -n '2,26p' "$0" | sed 's/^# \{0,1\}//'
  exit 1
fi

SHOPS_DIR="${SHOPS_DIR:-$HERE/shops}"
CONFIG="$SHOPS_DIR/$SLUG.env"
if [ ! -f "$CONFIG" ]; then
  echo "No config at infra/shops/$SLUG.env" >&2
  echo "Copy infra/shops/_template.env and fill it in." >&2
  exit 1
fi

# The config is shell on purpose — it is written by us, lives in the repo, and
# being able to compute a value in it is worth more than a parser.
# shellcheck disable=SC1090
. "$CONFIG"

require() {
  eval "value=\${$1:-}"
  if [ -z "$value" ]; then
    echo "$1 is not set in infra/shops/$SLUG.env" >&2
    exit 1
  fi
}

require SHOP_NAME
require BOOKING_URL
require APPWRITE_PROJECT_ID
# Required, not defaulted. An unset endpoint used to fall through to the Dart
# default, so a build would come out pointing at somebody else's Appwrite and
# say nothing about it — the app loads, and every request fails at a stranger's
# server. Better to refuse to build.
require APPWRITE_ENDPOINT

OUT="$ROOT/build/shops/$SLUG"
mkdir -p "$OUT"

# ── the print kit ─────────────────────────────────────────────────────────────
#
# First, because it needs no toolchain beyond Node and it is the thing you
# actually carry into a shop.

echo "==> Poster and table stands"
node "$HERE/tools/make_poster.js" \
  --url "$BOOKING_URL" \
  --shop "$SHOP_NAME" \
  --tagline "${SHOP_TAGLINE:-}" \
  --primary "${SHOP_PRIMARY:-6E1A1F}" \
  --secondary "${SHOP_SECONDARY:-C9A961}" \
  --surface "${SHOP_SURFACE:-FBF6EB}" \
  --ink "${SHOP_ON_SURFACE:-2A1810}" \
  --out "$OUT/poster.html"

if [ "$MODE" = "--poster-only" ]; then
  echo
  echo "Poster only. $OUT/poster.html"
  exit 0
fi

# ── the apps ──────────────────────────────────────────────────────────────────

if ! command -v flutter >/dev/null 2>&1; then
  echo "flutter is not on PATH — cannot build the apps." >&2
  echo "Re-run with --poster-only for just the print kit." >&2
  exit 1
fi

# Assembled once and reused for both binaries: the two apps differ only by
# APP_MODE, and any drift between their configuration would be a bug that only
# shows up as the panel and the booking page disagreeing about the shop.
# An array, not a string. A string would be word-split on the way to flutter,
# and the first value with a space in it — SHOP_TAGLINE='Der Friseursalon' —
# becomes two arguments, the second of which Flutter reads as a target file:
#
#   Target file "Friseursalon" not found.
#
# Which points at nothing resembling the cause.
DEFINES=()
add_define() {
  # Skip empties so the Dart-side defaults stay in charge of anything unset.
  if [ -n "${2:-}" ]; then
    DEFINES+=("--dart-define=$1=$2")
  fi
}

add_define APPWRITE_ENDPOINT      "${APPWRITE_ENDPOINT:-}"
add_define APPWRITE_PROJECT_ID    "${APPWRITE_PROJECT_ID:-}"
add_define APPWRITE_DATABASE_ID   "${APPWRITE_DATABASE_ID:-}"
add_define STAFF_TEAM_ID          "${STAFF_TEAM_ID:-}"
add_define BOOKING_FUNCTION_ID    "${BOOKING_FUNCTION_ID:-}"
add_define STRIPE_FUNCTION_ID     "${STRIPE_FUNCTION_ID:-}"

add_define SHOP_NAME              "${SHOP_NAME:-}"
add_define SHOP_TAGLINE           "${SHOP_TAGLINE:-}"
add_define SHOP_TIMEZONE          "${SHOP_TIMEZONE:-}"

add_define SHOP_PRIMARY           "${SHOP_PRIMARY:-}"
add_define SHOP_SECONDARY         "${SHOP_SECONDARY:-}"
add_define SHOP_SURFACE           "${SHOP_SURFACE:-}"
add_define SHOP_BACKGROUND        "${SHOP_BACKGROUND:-}"
add_define SHOP_ON_SURFACE        "${SHOP_ON_SURFACE:-}"
add_define SHOP_PRIMARY_DARK      "${SHOP_PRIMARY_DARK:-}"
add_define SHOP_SECONDARY_DARK    "${SHOP_SECONDARY_DARK:-}"
add_define SHOP_SURFACE_DARK      "${SHOP_SURFACE_DARK:-}"
add_define SHOP_BACKGROUND_DARK   "${SHOP_BACKGROUND_DARK:-}"
add_define SHOP_ON_SURFACE_DARK   "${SHOP_ON_SURFACE_DARK:-}"

add_define STRIPE_PUBLISHABLE_KEY "${STRIPE_PUBLISHABLE_KEY:-}"
add_define STRIPE_MERCHANT_ID     "${STRIPE_MERCHANT_ID:-}"

cd "$ROOT"

# Flutter's loader picks the CDN or the local copy from a flag baked into the
# build: `canvasKitBaseUrl: engineRevision && !useLocalCanvasKit ? <gstatic> :
# "canvaskit"`. --no-web-resources-cdn is what sets useLocalCanvasKit, so this
# fixes the branch that actually runs; the rewrite below only removes the dead
# string the other branch holds.
#
# Probed rather than assumed: the flag has not always existed, and a build that
# dies on an unknown option is worse than one that ships a URL we then rewrite.
CDN_FLAG=()
if flutter build web --help 2>&1 | grep -q -- '--no-web-resources-cdn'; then
  CDN_FLAG=(--no-web-resources-cdn)
else
  echo "note: this Flutter has no --no-web-resources-cdn; relying on the" >&2
  echo "      URL rewrite alone. Check the app still renders." >&2
fi

# `flutter build web` copies web/index.html and web/manifest.json through
# untouched, and those are the stock template — so without this the Dart side
# is branded and the browser tab still says someone else's shop.
brand_shell() {
  node "$HERE/tools/brand_web_shell.js" \
    --dir "$1" \
    --shop "$SHOP_NAME" \
    --tagline "${SHOP_TAGLINE:-}" \
    --primary "${SHOP_PRIMARY:-6E1A1F}" \
    --surface "${SHOP_SURFACE:-FBF6EB}"
}

# Serve the CanvasKit renderer from our own origin.
#
# Flutter's web engine loads it from gstatic.com by default — the same
# disclosure problem as the fonts, with a ~1.5 MB file. `flutter build web`
# emits a canvaskit/ directory in some versions and not others, so this copies
# it out of the SDK when it is missing rather than assuming either way.
selfhost_canvaskit() {
  local dir="$1"

  if [ -d "$dir/canvaskit" ]; then
    echo "    canvaskit already in the build"
    return 0
  fi

  local sdk src
  sdk="$(dirname "$(dirname "$(readlink -f "$(command -v flutter)")")")"
  src="$sdk/bin/cache/flutter_web_sdk/canvaskit"

  if [ -d "$src" ]; then
    cp -r "$src" "$dir/canvaskit"
    echo "    self-hosted canvaskit from $src"
  else
    echo "    No canvaskit at $src, and none in the build." >&2
    echo "    Shipping would load it from Google. Run: flutter precache --web" >&2
    return 1
  fi
}

# The compiled Dart honours FLUTTER_WEB_CANVASKIT_URL, but flutter.js and
# flutter_bootstrap.js are copied out of the SDK verbatim and keep the gstatic
# URL the SDK shipped. Rewriting it means there is no Google address left in
# the artefact — a claim grep can check, rather than one that rests on which
# loader path happens to run.
localise_canvaskit() {
  node "$HERE/tools/localise_canvaskit.js" \
    --dir "$1" --base "${2:-/}canvaskit/" --font-base "${2:-/}fonts/"
}

# Refuse to ship a build that phones home.
#
# Fonts are bundled and there is a test for that, but Flutter's own web output
# can still fetch the CanvasKit renderer from gstatic.com, and which versions
# do that has changed more than once. Rather than pin a flag against a Flutter
# version this checks the artefact itself, which stays true across upgrades.
#
# Appwrite and Stripe are deliberately not checked: they are disclosed
# processors with an AVV, which is exactly what Google is not.
assert_no_google() {
  local dir="$1" hits
  hits="$(grep -rIl -E 'gstatic\.com|fonts\.googleapis\.com' "$dir" || true)"

  if [ -n "$hits" ]; then
    echo >&2
    echo "REFUSING TO SHIP: the build fetches from Google at runtime." >&2
    echo "$hits" | sed 's/^/  /' >&2
    echo >&2
    echo "That sends every visitor's IP to Google before they book." >&2
    echo "If it is CanvasKit, self-host it — see infra/HOSTING.md." >&2
    exit 1
  fi
}

# A release build calls Env.assertSafe() at boot and refuses to start on a
# test Stripe key, a plaintext endpoint or disabled TLS validation. That check
# is the reason these are release builds and not profile ones.
echo
echo "==> Customer app"
flutter build web --release \
  --base-href "${BASE_HREF:-/}" \
  --output "$OUT/customer" \
  "${DEFINES[@]}" "${CDN_FLAG[@]+"${CDN_FLAG[@]}"}" \
  --dart-define=FLUTTER_WEB_CANVASKIT_URL="${BASE_HREF:-/}canvaskit/"
brand_shell "$OUT/customer"
selfhost_canvaskit "$OUT/customer"
localise_canvaskit "$OUT/customer" "${BASE_HREF:-/}"
assert_no_google "$OUT/customer"

if [ "$MODE" != "--customer-only" ]; then
  echo
  echo "==> Staff panel"
  flutter build web --release \
    --base-href "${STAFF_BASE_HREF:-/}" \
    --output "$OUT/staff" \
    "${DEFINES[@]}" "${CDN_FLAG[@]+"${CDN_FLAG[@]}"}" \
    --dart-define=APP_MODE=staff \
    --dart-define=FLUTTER_WEB_CANVASKIT_URL="${STAFF_BASE_HREF:-/}canvaskit/"
  brand_shell "$OUT/staff"
  selfhost_canvaskit "$OUT/staff"
  localise_canvaskit "$OUT/staff" "${STAFF_BASE_HREF:-/}"
  assert_no_google "$OUT/staff"
fi

echo
echo "-----------------------------------------------------------------------"
echo "  $SHOP_NAME"
echo
echo "  customer  $OUT/customer"
echo "  staff     $OUT/staff"
echo "  print kit $OUT/poster.html"
echo
echo "  The QR points at $BOOKING_URL — serve build/shops/$SLUG/customer"
echo "  there before printing anything."
echo "-----------------------------------------------------------------------"
