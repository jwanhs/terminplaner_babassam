#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Ba-Ba'Ssam Booking — staff team + first staff login
# -----------------------------------------------------------------------------
# Every staff-only table permission in setup_barber_db.sh is granted to
# `team:staff`. This script creates that team and (optionally) the first staff
# account, then puts the account in the team.
#
# The staff panel signs in with e-mail + password against Appwrite Account and
# checks team membership on boot — a user who is not in the team sees nothing,
# because the *table permissions* say so, not because the UI hides a button.
#
# Idempotent: safe to re-run.
#
# Usage:
#   APPWRITE_ENDPOINT=https://cloud.appwrite.io/v1 \
#   APPWRITE_PROJECT_ID=babassam \
#   APPWRITE_API_KEY=xxxxxxxxxxxx \
#   STAFF_EMAIL=chef@babassam.de \
#   STAFF_PASSWORD='...' \
#   ./setup_staff_team.sh
#
# Omit STAFF_EMAIL/STAFF_PASSWORD to only create the team.
# -----------------------------------------------------------------------------

set -u

ENDPOINT="${APPWRITE_ENDPOINT:-https://cloud.appwrite.io/v1}"
PROJECT_ID="${APPWRITE_PROJECT_ID:-babassam}"
API_KEY="${APPWRITE_API_KEY:-}"

STAFF_TEAM_ID="${STAFF_TEAM_ID:-staff}"
STAFF_TEAM_NAME="${STAFF_TEAM_NAME:-Shop Staff}"

STAFF_EMAIL="${STAFF_EMAIL:-}"
STAFF_PASSWORD="${STAFF_PASSWORD:-}"
STAFF_NAME="${STAFF_NAME:-Shop Staff}"

if [ -z "$API_KEY" ]; then
  echo "APPWRITE_API_KEY is not set. Export a server API key for project '$PROJECT_ID' and re-run." >&2
  exit 1
fi

export APPWRITE_ENDPOINT="$ENDPOINT"
export APPWRITE_PROJECT_ID="$PROJECT_ID"
export APPWRITE_API_KEY="$API_KEY"

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

# --- team ---------------------------------------------------------------------
log "Creating team '$STAFF_TEAM_ID'..."
run appwrite teams create --team-id "$STAFF_TEAM_ID" --name "$STAFF_TEAM_NAME"
ok "Team ready"

# --- first staff user ---------------------------------------------------------
if [ -z "$STAFF_EMAIL" ] || [ -z "$STAFF_PASSWORD" ]; then
  cat <<EOF

Team '$STAFF_TEAM_ID' exists. No STAFF_EMAIL/STAFF_PASSWORD given, so no staff
account was created.

To add one later:
  STAFF_EMAIL=chef@babassam.de STAFF_PASSWORD='...' ./setup_staff_team.sh

EOF
  exit 0
fi

if [ "${#STAFF_PASSWORD}" -lt 8 ]; then
  echo "STAFF_PASSWORD must be at least 8 characters." >&2
  exit 1
fi

# Deterministic user id from the e-mail so re-runs don't pile up accounts.
USER_ID="$(printf '%s' "$STAFF_EMAIL" | shasum -a 256 2>/dev/null | cut -c1-32 \
  || printf '%s' "$STAFF_EMAIL" | sha256sum | cut -c1-32)"

log "Creating staff user $STAFF_EMAIL..."
run appwrite users create \
  --user-id "$USER_ID" \
  --email "$STAFF_EMAIL" \
  --password "$STAFF_PASSWORD" \
  --name "$STAFF_NAME"

log "Adding $STAFF_EMAIL to team '$STAFF_TEAM_ID'..."
# `memberships create` with a user-id and no URL adds the member directly,
# already confirmed — no invitation e-mail round-trip.
run appwrite teams create-membership \
  --team-id "$STAFF_TEAM_ID" \
  --user-id "$USER_ID" \
  --roles "owner"

ok "Staff account ready — sign in to the staff panel with $STAFF_EMAIL"

cat <<EOF

Build the staff panel with:

  flutter build apk --dart-define=APP_MODE=staff \\
    --dart-define=APPWRITE_PROJECT_ID=$PROJECT_ID \\
    --dart-define=APPWRITE_ENDPOINT=$ENDPOINT

EOF
