#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Ba-Ba'Ssam Booking — schema (barber_db, Tables API)
# -----------------------------------------------------------------------------
# Provisions the `barber_db` database used by both the customer app
# (`lib/customer/`) and the staff panel (`lib/staff/`).
#
# SECURITY MODEL — read this before changing any --permissions line.
#
#   The Flutter client ships the project id in its binary. Anything readable
#   or writable by "any" is readable or writable by anyone who unpacks the
#   APK. Therefore:
#
#     appointments   staff-only, every permission. Customers never touch this
#                    table directly — they go through the `booking-api`
#                    Function, which holds a server API key and enforces
#                    ownership (manage token or verified OTP session).
#     otp_codes      no client permissions at all. Function-only.
#     rate_limits    no client permissions at all. Function-only.
#     closures       staff-only read: a block-off reason ("Arzttermin") is
#                    staff business, not public. The Function reads it with
#                    the API key when computing availability.
#     services       read("any") — the public price list. Writes staff-only.
#     business_hours read("any") — the opening hours on the door.
#     shop_settings  read("any") — cancellation cutoff etc. so the app can
#                    explain the rules. Contains no personal data.
#
#   `--row-security false` is deliberate on the staff-only tables: the table
#   permission IS the boundary, and no per-row grants should widen it.
#
# Idempotent: safe to re-run. See MIGRATION at the bottom for upgrading a
# deployment that was provisioned by the old (public-write) version.
#
# Usage:
#   APPWRITE_ENDPOINT=https://cloud.appwrite.io/v1 \
#   APPWRITE_PROJECT_ID=babassam \
#   APPWRITE_API_KEY=xxxxxxxxxxxx \
#   ./setup_barber_db.sh
# -----------------------------------------------------------------------------

set -u

# --- Config -------------------------------------------------------------------
ENDPOINT="${APPWRITE_ENDPOINT:-https://cloud.appwrite.io/v1}"
PROJECT_ID="${APPWRITE_PROJECT_ID:-babassam}"

# Server API key, supplied by the environment only — never committed.
# Never reaches the Flutter client.
API_KEY="${APPWRITE_API_KEY:-}"

if [ -z "$API_KEY" ]; then
  echo "APPWRITE_API_KEY is not set. Export a server API key for project '$PROJECT_ID' and re-run." >&2
  exit 1
fi

DB_ID="barber_db"
DB_NAME="BarberDB"

TBL_SERVICES="services"
TBL_APPOINTMENTS="appointments"
TBL_HOURS="business_hours"
TBL_CLOSURES="closures"
TBL_SETTINGS="shop_settings"
TBL_RESOURCES="resources"
TBL_OTP="otp_codes"
TBL_RATE="rate_limits"

# Team whose members are shop staff. Created by ./setup_staff_team.sh.
STAFF_TEAM_ID="${STAFF_TEAM_ID:-staff}"
STAFF="team:$STAFF_TEAM_ID"

export APPWRITE_ENDPOINT="$ENDPOINT"
export APPWRITE_PROJECT_ID="$PROJECT_ID"
export APPWRITE_API_KEY="$API_KEY"

# --- Helpers ------------------------------------------------------------------
log()  { printf "\033[1;36m▸ %s\033[0m\n" "$*"; }
ok()   { printf "\033[1;32m✓ %s\033[0m\n" "$*"; }
warn() { printf "\033[1;33m! %s\033[0m\n" "$*"; }

# Run a CLI command; swallow "already exists" errors so script is idempotent.
run() {
  out=$("$@" 2>&1) && return 0
  if echo "$out" | grep -qiE \
    "already exists|document_already_exists|attribute_already_exists|collection_already_exists|database_already_exists|index_already_exists|table_already_exists|column_already_exists"; then
    warn "exists — skipped: $*"
    return 0
  fi
  echo "$out" >&2
  return 1
}

# --- Database -----------------------------------------------------------------
log "Creating database '$DB_ID'..."
run appwrite tables-db create \
  --database-id "$DB_ID" --name "$DB_NAME"
ok  "Database ready"

# --- Table helpers ------------------------------------------------------------
create_table() {  # id name perms...
  local id="$1" name="$2"
  shift 2
  local perm_flags=()
  for p in "$@"; do perm_flags+=(--permissions "$p"); done
  log "Table: $id"
  run appwrite tables-db create-table \
    --database-id "$DB_ID" --table-id "$id" --name "$name" \
    "${perm_flags[@]}" \
    --row-security "false"
}

# A table with no client permissions whatsoever — reachable only through a
# server API key (i.e. from an Appwrite Function).
create_private_table() {  # id name
  log "Table: $1 (function-only)"
  run appwrite tables-db create-table \
    --database-id "$DB_ID" --table-id "$1" --name "$2" \
    --row-security "false"
}

# Re-apply permissions to an existing table. `create-table` is a no-op once the
# table exists, so upgrading a deployment provisioned by the old public-write
# version needs an explicit update. This is what actually closes the hole.
set_table_perms() {  # id name perms...
  local id="$1" name="$2"
  shift 2
  local perm_flags=()
  for p in "$@"; do perm_flags+=(--permissions "$p"); done
  run appwrite tables-db update-table \
    --database-id "$DB_ID" --table-id "$id" --name "$name" \
    "${perm_flags[@]}" \
    --row-security "false"
}

set_private_table_perms() {  # id name
  run appwrite tables-db update-table \
    --database-id "$DB_ID" --table-id "$1" --name "$2" \
    --row-security "false"
}

col_varchar() {  # table key size required [default]
  local tbl="$1" key="$2" size="$3" required="$4" default="${5:-}"
  if [ -n "$default" ] && [ "$required" = "false" ]; then
    run appwrite tables-db create-varchar-column \
      --database-id "$DB_ID" --table-id "$tbl" --key "$key" \
      --size "$size" --required "$required" --xdefault "$default"
  else
    run appwrite tables-db create-varchar-column \
      --database-id "$DB_ID" --table-id "$tbl" --key "$key" \
      --size "$size" --required "$required"
  fi
}

col_int() {  # table key required [min] [max] [default]
  local tbl="$1" key="$2" required="$3" min="${4:-0}" max="${5:-2147483647}" default="${6:-}"
  if [ -n "$default" ] && [ "$required" = "false" ]; then
    run appwrite tables-db create-integer-column \
      --database-id "$DB_ID" --table-id "$tbl" --key "$key" \
      --required "$required" --min "$min" --max "$max" --xdefault "$default"
  else
    run appwrite tables-db create-integer-column \
      --database-id "$DB_ID" --table-id "$tbl" --key "$key" \
      --required "$required" --min "$min" --max "$max"
  fi
}

col_bool() {  # table key required [default]
  local tbl="$1" key="$2" required="$3" default="${4:-}"
  if [ -n "$default" ] && [ "$required" = "false" ]; then
    run appwrite tables-db create-boolean-column \
      --database-id "$DB_ID" --table-id "$tbl" --key "$key" \
      --required "$required" --xdefault "$default"
  else
    run appwrite tables-db create-boolean-column \
      --database-id "$DB_ID" --table-id "$tbl" --key "$key" \
      --required "$required"
  fi
}

col_datetime() {  # table key required
  run appwrite tables-db create-datetime-column \
    --database-id "$DB_ID" --table-id "$1" --key "$2" --required "$3"
}

col_enum() {  # table key elements required [default]
  local tbl="$1" key="$2" elements="$3" required="$4" default="${5:-}"
  local elem_flags=()
  for e in $elements; do elem_flags+=(--elements "$e"); done
  if [ -n "$default" ]; then
    run appwrite tables-db create-enum-column \
      --database-id "$DB_ID" --table-id "$tbl" --key "$key" \
      "${elem_flags[@]}" --required "$required" --xdefault "$default"
  else
    run appwrite tables-db create-enum-column \
      --database-id "$DB_ID" --table-id "$tbl" --key "$key" \
      "${elem_flags[@]}" --required "$required"
  fi
}

create_index() {  # table key type columns...
  local tbl="$1" key="$2" type="$3"; shift 3
  run appwrite tables-db create-index \
    --database-id "$DB_ID" --table-id "$tbl" \
    --key "$key" --type "$type" --columns "$@"
}

# Column creation is async server-side; small pause before adding indexes.
wait_for_cols() { sleep 2; }

# --- services ----------------------------------------------------------------
# The public price list: world-readable, staff-writable.
create_table "$TBL_SERVICES" "Services" \
  'read("any")' "create(\"$STAFF\")" "update(\"$STAFF\")" "delete(\"$STAFF\")"
set_table_perms "$TBL_SERVICES" "Services" \
  'read("any")' "create(\"$STAFF\")" "update(\"$STAFF\")" "delete(\"$STAFF\")"
col_varchar  "$TBL_SERVICES" "name"              120 true
col_varchar  "$TBL_SERVICES" "description"       500 false
col_int      "$TBL_SERVICES" "duration_minutes"  true 5 240
col_int      "$TBL_SERVICES" "price_cents"       true 0 100000
col_int      "$TBL_SERVICES" "display_order"     false 0 999 100
col_bool     "$TBL_SERVICES" "active"            false "true"
wait_for_cols
create_index "$TBL_SERVICES" "by_display_order" key display_order

# --- resources ---------------------------------------------------------------
# The chairs. One row per chair, station or barber that can take a booking in
# parallel with the others.
#
# A shop with NO rows here is a one-chair shop, and the booking API falls back
# to the implicit resource "shop" that every slot key written before this table
# existed already names. That is deliberate: adding this table to a running
# deployment changes nothing until somebody adds a chair.
#
# World-readable like the price list — a chair's name is not personal data, and
# the staff panel needs it before anyone has signed in.
create_table "$TBL_RESOURCES" "Resources" \
  'read("any")' "create(\"$STAFF\")" "update(\"$STAFF\")" "delete(\"$STAFF\")"
set_table_perms "$TBL_RESOURCES" "Resources" \
  'read("any")' "create(\"$STAFF\")" "update(\"$STAFF\")" "delete(\"$STAFF\")"
col_varchar  "$TBL_RESOURCES" "name"          80 true
col_int      "$TBL_RESOURCES" "display_order" false 0 999 100
col_bool     "$TBL_RESOURCES" "active"        false "true"
wait_for_cols
create_index "$TBL_RESOURCES" "by_display_order" key display_order

# --- appointments ------------------------------------------------------------
# STAFF ONLY — every permission. Customers reach this table exclusively through
# the `booking-api` Function, which authenticates them by manage token or
# verified OTP session. Making any of these "any" re-opens a personal-data
# breach (every customer's name, phone and schedule) plus free rewrites of
# anyone else's booking.
create_table "$TBL_APPOINTMENTS" "Appointments" \
  "read(\"$STAFF\")" "create(\"$STAFF\")" "update(\"$STAFF\")" "delete(\"$STAFF\")"
set_table_perms "$TBL_APPOINTMENTS" "Appointments" \
  "read(\"$STAFF\")" "create(\"$STAFF\")" "update(\"$STAFF\")" "delete(\"$STAFF\")"
col_varchar  "$TBL_APPOINTMENTS" "customer_name"        120 true
col_varchar  "$TBL_APPOINTMENTS" "customer_phone"        40 true
col_varchar  "$TBL_APPOINTMENTS" "service_id"            36 true
col_varchar  "$TBL_APPOINTMENTS" "service_name"         120 true
col_datetime "$TBL_APPOINTMENTS" "start_at"                 true
col_datetime "$TBL_APPOINTMENTS" "end_at"                   true
col_varchar  "$TBL_APPOINTMENTS" "notes"                 500 false
col_bool     "$TBL_APPOINTMENTS" "paid"                 false "false"
col_int      "$TBL_APPOINTMENTS" "payment_amount_cents" false 0 100000 0
col_int      "$TBL_APPOINTMENTS" "discount_cents"       false 0 100000 0

# Ownership proof for an account-less customer. The Function returns the raw
# token once, at booking time; only its SHA-256 is stored. Whoever presents the
# token owns the booking — that is what replaces the old "anyone may update".
col_varchar  "$TBL_APPOINTMENTS" "manage_token_hash"     64 false

# Stripe reconciliation handle. Written when the PaymentIntent is minted, read
# by the webhook to find the row again.
col_varchar  "$TBL_APPOINTMENTS" "payment_intent_id"     64 false

# Concurrency guard. `slot_key` is "<staff>|<start ISO>" and carries a UNIQUE
# index, so two simultaneous bookings of the same slot cannot both land — the
# second insert fails at the database, not in application code. Cancelling
# rewrites the key to a dead value so the slot frees up again.
col_varchar  "$TBL_APPOINTMENTS" "slot_key"              80 false

# Which chair this booking sits on — a row id from `resources`. Empty on every
# booking written before the shop had more than one chair; the booking API
# reads an empty or unknown value as the first chair, because a booking that
# occupies nobody would let its slot be sold a second time.
col_varchar  "$TBL_APPOINTMENTS" "resource_id"           36 false

# Where the booking came from, so staff can tell a walk-in from an online one.
col_enum     "$TBL_APPOINTMENTS" "source" "online walkin staff" false "online"

# Set by the reminder job so a customer is never messaged twice.
col_datetime "$TBL_APPOINTMENTS" "reminder_sent_at"          false

# Appwrite ≤1.9.x rejects --xdefault on required columns; keep status
# non-required so the default applies to console inserts.
col_enum     "$TBL_APPOINTMENTS" "status" \
  "confirmed cancelled completed no_show" false "confirmed"
wait_for_cols
create_index "$TBL_APPOINTMENTS" "by_start" key start_at
create_index "$TBL_APPOINTMENTS" "by_phone" key customer_phone
create_index "$TBL_APPOINTMENTS" "by_token" key manage_token_hash
create_index "$TBL_APPOINTMENTS" "by_intent" key payment_intent_id
# slot_key is "<chair>|<start ISO>", so this unique index is per chair: a
# three-chair shop can sell 10:00 three times and not a fourth, and the
# database is what decides that rather than application code.
create_index "$TBL_APPOINTMENTS" "uniq_slot" unique slot_key
create_index "$TBL_APPOINTMENTS" "by_resource" key resource_id

# --- business_hours ----------------------------------------------------------
# One row per weekday. ISO weekdays (0 = Mon … 6 = Sun).
# `break_start`/`break_end` carve the lunch break out of the day; leave empty
# for no break.
create_table "$TBL_HOURS" "BusinessHours" \
  'read("any")' "create(\"$STAFF\")" "update(\"$STAFF\")" "delete(\"$STAFF\")"
set_table_perms "$TBL_HOURS" "BusinessHours" \
  'read("any")' "create(\"$STAFF\")" "update(\"$STAFF\")" "delete(\"$STAFF\")"
col_int      "$TBL_HOURS" "weekday"      true 0 6
col_varchar  "$TBL_HOURS" "open_time"      5 true
col_varchar  "$TBL_HOURS" "close_time"    5 true
col_varchar  "$TBL_HOURS" "break_start"    5 false
col_varchar  "$TBL_HOURS" "break_end"      5 false
col_int      "$TBL_HOURS" "slot_minutes" false 5 240 30
col_bool     "$TBL_HOURS" "closed"       false "false"
wait_for_cols
create_index "$TBL_HOURS" "by_weekday" unique weekday

# --- closures ----------------------------------------------------------------
# Holidays, vacation, sick days and ad-hoc block-offs. Any slot overlapping a
# closure is unavailable. Staff-only: the reason is nobody else's business.
create_table "$TBL_CLOSURES" "Closures" \
  "read(\"$STAFF\")" "create(\"$STAFF\")" "update(\"$STAFF\")" "delete(\"$STAFF\")"
set_table_perms "$TBL_CLOSURES" "Closures" \
  "read(\"$STAFF\")" "create(\"$STAFF\")" "update(\"$STAFF\")" "delete(\"$STAFF\")"
col_datetime "$TBL_CLOSURES" "starts_at" true
col_datetime "$TBL_CLOSURES" "ends_at"   true
col_varchar  "$TBL_CLOSURES" "reason"    160 false
col_bool     "$TBL_CLOSURES" "all_day"   false "false"
# Which chair is blocked. EMPTY MEANS THE WHOLE SHOP — that is the difference
# between "closed Monday" and "Ali is on holiday", and reading it the wrong way
# either empties the grid for nothing or sells appointments during a holiday.
col_varchar  "$TBL_CLOSURES" "resource_id" 36 false
wait_for_cols
create_index "$TBL_CLOSURES" "by_starts" key starts_at

# --- shop_settings -----------------------------------------------------------
# Exactly one row, id `default`. Booking rules live here rather than in the
# client so changing them doesn't need an app release.
create_table "$TBL_SETTINGS" "ShopSettings" \
  'read("any")' "create(\"$STAFF\")" "update(\"$STAFF\")" "delete(\"$STAFF\")"
set_table_perms "$TBL_SETTINGS" "ShopSettings" \
  'read("any")' "create(\"$STAFF\")" "update(\"$STAFF\")" "delete(\"$STAFF\")"
# IANA zone the shop lives in. All slot arithmetic happens in this zone, never
# in the customer's device zone.
col_varchar  "$TBL_SETTINGS" "timezone"             64 false "Europe/Berlin"
# Cleanup/turnaround time wedged after every appointment.
col_int      "$TBL_SETTINGS" "buffer_minutes"       false 0 120 0
# How soon before a slot it may still be booked ("not within 30 minutes").
col_int      "$TBL_SETTINGS" "lead_time_minutes"    false 0 10080 30
# How late a customer may still cancel or move a booking themselves.
col_int      "$TBL_SETTINGS" "cancel_cutoff_hours"  false 0 720 12
# How far ahead the calendar opens.
col_int      "$TBL_SETTINGS" "max_advance_days"     false 1 365 30
# Cap on bookings one phone number may hold at once — anti-spam.
col_int      "$TBL_SETTINGS" "max_open_per_phone"   false 1 50 3
wait_for_cols

# --- otp_codes ---------------------------------------------------------------
# One-time codes for "show me my appointments". No client permissions at all:
# the Function is the only thing that may read or write them.
create_private_table "$TBL_OTP" "OtpCodes"
set_private_table_perms "$TBL_OTP" "OtpCodes"
col_varchar  "$TBL_OTP" "phone"      40 true
col_varchar  "$TBL_OTP" "code_hash"  64 true
col_datetime "$TBL_OTP" "expires_at"    true
col_int      "$TBL_OTP" "attempts"   false 0 100 0
col_bool     "$TBL_OTP" "consumed"   false "false"
# Session token handed out after a successful verification; proves "this device
# owns this phone number" for subsequent lookups.
col_varchar  "$TBL_OTP" "session_hash" 64 false
col_datetime "$TBL_OTP" "session_expires_at" false
wait_for_cols
create_index "$TBL_OTP" "by_phone" key phone
create_index "$TBL_OTP" "by_session" key session_hash

# --- rate_limits -------------------------------------------------------------
# Fixed-window counters keyed by a hashed bucket (phone or client IP). Private:
# a client that could edit these could lift its own limits.
create_private_table "$TBL_RATE" "RateLimits"
set_private_table_perms "$TBL_RATE" "RateLimits"
col_varchar  "$TBL_RATE" "bucket"       80 true
col_int      "$TBL_RATE" "count"        false 0 100000 0
col_datetime "$TBL_RATE" "window_start"    true
wait_for_cols
create_index "$TBL_RATE" "uniq_bucket" unique bucket

# --- default settings row ----------------------------------------------------
log "Seeding default shop settings..."
run appwrite tables-db create-row \
  --database-id "$DB_ID" --table-id "$TBL_SETTINGS" --row-id "default" \
  --data '{"timezone":"Europe/Berlin","buffer_minutes":0,"lead_time_minutes":30,"cancel_cutoff_hours":12,"max_advance_days":30,"max_open_per_phone":3}'

# -----------------------------------------------------------------------------
ok "barber_db tables, columns, indexes and permissions provisioned."

cat <<EOF

Next steps:
  1. ./setup_staff_team.sh              — create the '$STAFF_TEAM_ID' team and your first staff login
  2. ./deploy_functions.sh              — deploy booking-api, stripe-deposit, stripe-webhook
  3. Seed services + business_hours     — via the staff panel, or the Appwrite Console

MIGRATION — deployment provisioned by the pre-lockdown version of this script:

  Re-running this script re-applies the permissions above to the existing
  tables (that is what set_table_perms is for), which is the step that
  actually closes the public read/write hole. After re-running:

    * Old appointment rows have no manage_token_hash, so their customers can
      no longer self-cancel online — they will be told to phone the shop.
      Staff can still cancel and move them from the panel. Rows created from
      then on are unaffected.
    * Old rows have no slot_key, so they do not participate in the unique
      index. They still block their slot: the Function's overlap check reads
      every non-cancelled row for the day, key or no key.
    * ASSUME THE OLD DATA LEAKED. While appointments were read("any"),
      every row was world-readable to anyone holding the project id — which
      ships in the app binary. Under GDPR Art. 33 a controller has 72 hours
      from becoming aware of a personal-data breach to notify the supervisory
      authority. Treat closing this hole as the moment of awareness and take
      advice on whether the customers themselves must be told (Art. 34).

EOF
