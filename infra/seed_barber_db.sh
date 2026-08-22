#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Ba-Ba'Ssam — Seed initial services and business_hours into barber_db.
# Run after setup_barber_db.sh.
#
# Targets barber_db, the only schema. Run after setup_barber_db.sh.
#
# CHAIRS ARE NOT SEEDED ON PURPOSE. No rows in `resources` means a one-chair
# shop, which is what the booking API falls back to and what every existing
# deployment already behaves like. Seeding a chair here would quietly move a
# running shop off that path.
#
# A shop with more than one chair gets them added explicitly:
#
#   appwrite tablesDB create-row --database-id barber_db --table-id resources \
#     --row-id chair-1 --data '{"name":"Stuhl 1","display_order":1,"active":true}'
#
# From two rows upward the panel starts showing chairs, availability sells each
# time once per chair, and staff can block one barber without shutting the shop.

# -----------------------------------------------------------------------------
set -u

ENDPOINT="${APPWRITE_ENDPOINT:-https://cloud.appwrite.io/v1}"
PROJECT_ID="${APPWRITE_PROJECT_ID:-babassam}"

# Server API key, supplied by the environment only — never committed.
# Same key as the setup scripts; stays in tooling, never reaches the client.
API_KEY="${APPWRITE_API_KEY:-}"

if [ -z "$API_KEY" ]; then
  echo "APPWRITE_API_KEY is not set. Export a server API key for project '$PROJECT_ID' and re-run." >&2
  exit 1
fi

export APPWRITE_ENDPOINT="$ENDPOINT"
export APPWRITE_PROJECT_ID="$PROJECT_ID"
export APPWRITE_API_KEY="$API_KEY"

DB="barber_db"

create_row() {
  local tbl="$1" id="$2" data="$3"
  appwrite tables-db create-row \
    --database-id "$DB" --table-id "$tbl" \
    --row-id "$id" --data "$data" 2>/dev/null \
    || echo "  (skip: $tbl/$id likely exists)"
}

# --- services --------------------------------------------------------------
create_row services svc_haarschnitt '{
  "name": "Herren-Haarschnitt",
  "description": "Klassischer Haarschnitt mit Waschen und Styling.",
  "duration_minutes": 30, "price_cents": 2500, "display_order": 1
}'

create_row services svc_bart '{
  "name": "Bart-Trimmen",
  "description": "Präzises Trimmen und Konturieren des Bartes.",
  "duration_minutes": 20, "price_cents": 1500, "display_order": 2
}'

create_row services svc_kombi '{
  "name": "Haar & Bart Kombi",
  "description": "Haarschnitt + Bartpflege im Komplettpaket.",
  "duration_minutes": 45, "price_cents": 3500, "display_order": 3
}'

create_row services svc_rasur '{
  "name": "Klassische Nassrasur",
  "description": "Heiße Tücher, Schaum, Rasiermesser.",
  "duration_minutes": 30, "price_cents": 2800, "display_order": 4
}'

create_row services svc_kind '{
  "name": "Kinder-Haarschnitt",
  "description": "Für Jungs bis 12 Jahre.",
  "duration_minutes": 20, "price_cents": 1800, "display_order": 5
}'

# --- business_hours -----------------------------------------------------------
# ISO weekdays (0 = Mon … 6 = Sun); see lib/staff/data/models.dart. Row ids are
# hours_<weekday> so the staff panel can upsert them without a lookup.
# Mon-Fri 09:00-19:00, Sat 09:00-16:00, Sun closed. 30-minute slots.
for day in 0 1 2 3 4; do
  create_row business_hours "hours_${day}" "{
    \"weekday\": $day,
    \"open_time\": \"09:00\", \"close_time\": \"19:00\",
    \"slot_minutes\": 30, \"closed\": false
  }"
done

create_row business_hours "hours_5" '{
  "weekday": 5,
  "open_time": "09:00", "close_time": "16:00",
  "slot_minutes": 30, "closed": false
}'

# open_time/close_time are required varchars even when closed; placeholder them.
create_row business_hours "hours_6" '{
  "weekday": 6,
  "open_time": "00:00", "close_time": "00:00",
  "slot_minutes": 30, "closed": true
}'

echo "✓ barber_db seed complete."
