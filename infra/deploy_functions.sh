#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Ba-Ba'Ssam Booking — deploy the three Appwrite Functions
# -----------------------------------------------------------------------------
#   booking-api            the customer-facing API (the only anonymous path to
#                          the appointments table)
#   create-payment-intent  mints Stripe PaymentIntents, prices them server-side
#   stripe-webhook         verifies Stripe events; the only writer of `paid`
#
# All three need APPWRITE_API_KEY as a *function variable* — that key is what
# lets them reach the staff-only tables. It is set here from the environment
# and never committed.
#
# Idempotent: re-running updates variables and pushes a fresh deployment.
#
# Usage:
#   APPWRITE_ENDPOINT=https://cloud.appwrite.io/v1 \
#   APPWRITE_PROJECT_ID=babassam \
#   APPWRITE_API_KEY=xxxxxxxx \
#   STRIPE_SECRET_KEY=sk_live_xxx \
#   STRIPE_WEBHOOK_SECRET=whsec_xxx \
#   ./deploy_functions.sh
#
# Optional:
#   SMS_PROVIDER=twilio TWILIO_ACCOUNT_SID=.. TWILIO_AUTH_TOKEN=.. TWILIO_FROM=..
#   OTP_DEV_MODE=true          pilot the OTP flow without an SMS account
#   APPWRITE_INSECURE_TLS=true self-hosted behind a self-signed certificate
# -----------------------------------------------------------------------------

set -u

ENDPOINT="${APPWRITE_ENDPOINT:-https://cloud.appwrite.io/v1}"
PROJECT_ID="${APPWRITE_PROJECT_ID:-babassam}"
API_KEY="${APPWRITE_API_KEY:-}"

if [ -z "$API_KEY" ]; then
  echo "APPWRITE_API_KEY is not set. Export a server API key for project '$PROJECT_ID' and re-run." >&2
  exit 1
fi

export APPWRITE_ENDPOINT="$ENDPOINT"
export APPWRITE_PROJECT_ID="$PROJECT_ID"
export APPWRITE_API_KEY="$API_KEY"

HERE="$(cd "$(dirname "$0")" && pwd)"

# FIX 1: Appwrite 1.9.x uses not "node-22.0". The patch is
# rejected with a 400. Allow override via FUNCTION_RUNTIME for older servers.
RUNTIME="${FUNCTION_RUNTIME:-node-16.0}"

log()  { printf "\033[1;36m▸ %s\033[0m\n" "$*"; }
ok()   { printf "\033[1;32m✓ %s\033[0m\n" "$*"; }
warn() { printf "\033[1;33m! %s\033[0m\n" "$*"; }

run() {
  out=$("$@" 2>&1) && return 0
  if echo "$out" | grep -qiE "already exists|_already_exists"; then
    warn "exists — skipped: $*"
    return 0
  fi
  echo "$out" >&2
  return 1
}

ensure_function() {  # id name execute-role
  log "Function: $1"
  run appwrite functions create \
    --function-id "$1" --name "$2" --runtime "$RUNTIME" \
    --execute "$3" --entrypoint "src/main.js" \
    --commands "npm install"
}

set_var() {  # function-id key value
  [ -z "$3" ] && return 0
  # Try to create first. If the variable already exists (conflict/409), find
  # its UUID via list-variables and update it. This avoids passing the key name
  # as --variable-id (which the CLI rejects — it needs the internal UUID).
  local fn_id="$1" key="$2" val="$3"
  local out exit_code var_id

  # ADDED: --variable-id "unique()"
  out=$(appwrite functions create-variable \
    --function-id "$fn_id" --variable-id "unique()" --key "$key" --value "$val" 2>&1)
  exit_code=$?

  if [ $exit_code -eq 0 ]; then
    return 0
  fi

  if ! echo "$out" | grep -qiE "already exists|variable_already_exists|conflict|409"; then
    echo "$out" >&2
    return 1
  fi

  # Variable exists — find its UUID then update/replace it.
  var_id=$(appwrite functions list-variables --function-id "$fn_id" 2>/dev/null \
    | grep -B5 "\"$key\"" | grep -oE '"[0-9a-f]{20}"' | head -1 | tr -d '"')

  if [ -n "$var_id" ]; then
    # Try update-variable first (available in recent CLI versions).
    if appwrite functions update-variable \
        --function-id "$fn_id" --variable-id "$var_id" \
        --key "$key" --value "$val" >/dev/null 2>&1; then
      return 0
    fi
    # Fall back to delete + create.
    appwrite functions delete-variable \
      --function-id "$fn_id" --variable-id "$var_id" >/dev/null 2>&1 || true
  fi

  # ADDED: --variable-id "unique()"
  run appwrite functions create-variable \
    --function-id "$fn_id" --variable-id "unique()" --key "$key" --value "$val"
}

deploy() {  # function-id dir
  log "Deploying $1 from $2"
  run appwrite functions create-deployment \
    --function-id "$1" --code "$2" --activate true --entrypoint "src/main.js"
}

# FIX 2: The single-quote in BaBa'Ssam terminates a double-quoted ${:-...}
# substitution early, causing a bash "bad substitution" error. Store the
# default in a plain variable before use.
_DEFAULT_SHOP_NAME="${SHOP_NAME:-BaBa\'Ssam}"

# --- booking-api --------------------------------------------------------------
# execute("any"): the customer app is anonymous by design. The function's own
# ownership checks are the boundary, not who may invoke it.
ensure_function "booking-api" "Booking API" 'any'
set_var "booking-api" "APPWRITE_API_KEY"          "$API_KEY"
set_var "booking-api" "APPWRITE_DATABASE_ID"      "${APPWRITE_DATABASE_ID:-barber_db}"
set_var "booking-api" "SHOP_NAME"                 "$_DEFAULT_SHOP_NAME"
set_var "booking-api" "LOYALTY_STAMPS_PER_REWARD" "${LOYALTY_STAMPS_PER_REWARD:-10}"
set_var "booking-api" "APPWRITE_INSECURE_TLS"     "${APPWRITE_INSECURE_TLS:-}"
set_var "booking-api" "SMS_PROVIDER"              "${SMS_PROVIDER:-}"
set_var "booking-api" "TWILIO_ACCOUNT_SID"        "${TWILIO_ACCOUNT_SID:-}"
set_var "booking-api" "TWILIO_AUTH_TOKEN"         "${TWILIO_AUTH_TOKEN:-}"
set_var "booking-api" "TWILIO_FROM"               "${TWILIO_FROM:-}"
set_var "booking-api" "OTP_DEV_MODE"              "${OTP_DEV_MODE:-}"
deploy "booking-api" "$HERE/functions/booking-api"

# --- create-payment-intent ----------------------------------------------------
ensure_function "stripe-deposit" "Stripe Deposit" 'any'
set_var "stripe-deposit" "APPWRITE_API_KEY"       "$API_KEY"
set_var "stripe-deposit" "APPWRITE_DATABASE_ID"   "${APPWRITE_DATABASE_ID:-barber_db}"
set_var "stripe-deposit" "STRIPE_SECRET_KEY"      "${STRIPE_SECRET_KEY:-}"
set_var "stripe-deposit" "SHOP_NAME"              "$_DEFAULT_SHOP_NAME"
set_var "stripe-deposit" "APPWRITE_INSECURE_TLS"  "${APPWRITE_INSECURE_TLS:-}"
deploy "stripe-deposit" "$HERE/functions/create-payment-intent"

# --- stripe-webhook -----------------------------------------------------------
# Also execute("any") — Stripe posts to it unauthenticated. The signature check
# inside is what makes that safe.
ensure_function "stripe-webhook" "Stripe Webhook" 'any'
set_var "stripe-webhook" "APPWRITE_API_KEY"       "$API_KEY"
set_var "stripe-webhook" "APPWRITE_DATABASE_ID"   "${APPWRITE_DATABASE_ID:-barber_db}"
set_var "stripe-webhook" "STRIPE_SECRET_KEY"      "${STRIPE_SECRET_KEY:-}"
set_var "stripe-webhook" "STRIPE_WEBHOOK_SECRET"  "${STRIPE_WEBHOOK_SECRET:-}"
set_var "stripe-webhook" "APPWRITE_INSECURE_TLS"  "${APPWRITE_INSECURE_TLS:-}"
deploy "stripe-webhook" "$HERE/functions/stripe-webhook"

ok "Functions deployed."

if [ -z "${STRIPE_WEBHOOK_SECRET:-}" ]; then
  warn "STRIPE_WEBHOOK_SECRET is empty — the webhook will refuse every event."
fi

cat <<EOF

Finish the Stripe side:

  1. Copy the stripe-webhook function URL from the Appwrite Console.
  2. Stripe → Developers → Webhooks → Add endpoint, paste that URL.
  3. Subscribe to: payment_intent.succeeded, payment_intent.payment_failed,
     charge.refunded, charge.dispute.created
  4. Copy the signing secret (whsec_...) and re-run this script with
     STRIPE_WEBHOOK_SECRET set.

Until step 4 is done, payments will be taken but no booking will ever show as
paid — the client cannot mark itself paid any more, and that is deliberate.

EOF
