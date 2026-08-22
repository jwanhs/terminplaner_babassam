// Slot computation — the single source of truth for "is this time free?".
//
// Pure: no I/O, no clock reads, no Appwrite. Everything it needs is an
// argument, which is what makes it testable (see test/availability.test.js)
// and what lets `create` re-run the exact same check the customer's grid was
// drawn from. The client no longer computes availability at all; if it did,
// the two would drift and drift is what lets a double booking through.

import {
  parseDateKey, parseHm, zonedWallToUtc, wallClockLabel, daysBetween, shopDateKey,
} from './shoptime.js';

const MIN = 60 * 1000;

/**
 * The chair a shop has before anyone tells it otherwise.
 *
 * A shop with no `resources` rows is a one-chair shop, and every slot key it
 * has ever written names this resource — so leaving the default here is what
 * keeps existing deployments byte-identical after this change.
 */
export const SOLO_RESOURCE = 'shop';
const SOLO = [SOLO_RESOURCE];

/**
 * Which chair a row belongs to.
 *
 * An appointment written before the shop grew a second chair carries no
 * resource. It still occupied somebody, so it is attributed to the first
 * chair rather than to nobody — treating it as unassigned would quietly double
 * the shop's apparent capacity on every historical booking.
 */
function resourceOf(row) {
  const value = row.resource ?? row.resourceId ?? row.resource_id;
  return value == null || value === '' ? null : String(value);
}

/**
 * @param {object}   a
 * @param {string}   a.dateKey     shop-local day, "YYYY-MM-DD"
 * @param {string}   a.timezone    IANA zone the shop lives in
 * @param {object}   a.hours       business_hours row for that weekday
 * @param {object[]} a.appointments non-cancelled rows overlapping the day:
 *                                  { startAt, endAt, resource } — resource
 *                                  absent means the first chair
 * @param {object[]} a.closures    { startsAt, endsAt, resource } — resource
 *                                  absent means the whole shop is shut
 * @param {number}   a.durationMinutes  chosen service length
 * @param {object}   a.settings    { bufferMinutes, leadTimeMinutes, maxAdvanceDays }
 * @param {number}   a.nowMs       current instant, epoch ms
 * @param {string[]} a.resources   chairs that can take this service, in the
 *                                 order they should be filled. Defaults to a
 *                                 single implicit chair.
 * @returns {{start:string, end:string, label:string, free:string[]}[]}
 *          bookable slots only, each carrying the chairs free at that time
 */
export function computeSlots({
  dateKey, timezone, hours, appointments = [], closures = [],
  durationMinutes, settings = {}, nowMs, resources = SOLO,
}) {
  if (!hours || hours.closed) return [];

  // A shop with every chair switched off is shut, whatever its opening hours
  // say.
  const chairs = [...new Set(resources.map(String))];
  if (chairs.length === 0) return [];

  const buffer = clampInt(settings.buffer_minutes ?? settings.bufferMinutes, 0, 120, 0);
  const lead = clampInt(settings.lead_time_minutes ?? settings.leadTimeMinutes, 0, 10080, 30);
  const maxAdvance = clampInt(settings.max_advance_days ?? settings.maxAdvanceDays, 1, 365, 30);

  // Outside the bookable window entirely — no need to look at the day at all.
  const todayKey = shopDateKey(nowMs, timezone);
  const offset = daysBetween(todayKey, dateKey);
  if (offset < 0 || offset > maxAdvance) return [];

  const open = parseHm(hours.open_time);
  const close = parseHm(hours.close_time);
  if (open === null || close === null || close <= open) return [];

  const step = clampInt(hours.slot_minutes, 5, 240, 30);
  const duration = clampInt(durationMinutes, 5, 480, 30);

  const breakStart = parseHm(hours.break_start);
  const breakEnd = parseHm(hours.break_end);
  const hasBreak = breakStart !== null && breakEnd !== null && breakEnd > breakStart;

  const { year, month, day } = parseDateKey(dateKey);
  const earliest = nowMs + lead * MIN;

  // Busy intervals, each already padded by the turnaround buffer so the guard
  // below is a plain overlap test. Closures are NOT padded: a shop that closes
  // at 13:00 for a funeral means 13:00, not 13:00 minus the cleanup time.
  //
  // `chair: null` means the interval blocks every chair. That is the whole
  // difference between "the shop is shut this afternoon" and "Ali is off" —
  // the first must empty the grid, the second must only cost one chair.
  //
  // A row naming a chair the shop no longer has is attributed to the first
  // chair rather than to nobody. Both directions of that choice cost
  // something, and they are not symmetric: reading it as "blocks nothing"
  // sells a slot to a customer who will arrive to find someone in it, while
  // reading it as "blocks chair one" only makes the shop look busier than it
  // is. The second is recoverable at the counter; the first is not.
  const chairOfRow = (row, fallback) => {
    const named = resourceOf(row);
    if (named === null) return fallback;
    return chairs.includes(named) ? named : chairs[0];
  };

  const busy = [
    ...appointments.map((a) => ({
      from: Date.parse(a.startAt ?? a.start_at) - buffer * MIN,
      to: Date.parse(a.endAt ?? a.end_at) + buffer * MIN,
      chair: chairOfRow(a, chairs[0]),
    })),
    ...closures.map((c) => ({
      from: Date.parse(c.startsAt ?? c.starts_at),
      to: Date.parse(c.endsAt ?? c.ends_at),
      chair: chairOfRow(c, null),
    })),
  ].filter((b) => Number.isFinite(b.from) && Number.isFinite(b.to) && b.to > b.from);

  const slots = [];
  for (let mins = open; mins + duration <= close; mins += step) {
    // A slot that starts before the break must also finish before it.
    if (hasBreak && mins < breakEnd && mins + duration > breakStart) continue;

    const startMs = zonedWallToUtc({
      year, month, day,
      hour: Math.floor(mins / 60),
      minute: mins % 60,
    }, timezone);
    // Wall time skipped by the spring-forward transition — it never happens.
    if (startMs === null) continue;

    if (startMs < earliest) continue;

    const endMs = startMs + duration * MIN;

    // The slot is offered while any one chair can take it. Which chairs those
    // are travels with the slot so `create` can claim one without recomputing
    // — and so a collision on the chair it picked can fall through to the next
    // rather than telling a customer the time is gone when it is not.
    const free = chairs.filter((chair) => !busy.some(
      (b) => (b.chair === null || b.chair === chair)
        && startMs < b.to && b.from < endMs));
    if (free.length === 0) continue;

    slots.push({
      start: new Date(startMs).toISOString(),
      end: new Date(endMs).toISOString(),
      label: wallClockLabel(startMs, timezone),
      free,
    });
  }
  return slots;
}

/**
 * Is [startMs, startMs+duration) still bookable? Re-runs the same rules as
 * [computeSlots] for one candidate instead of a whole day.
 *
 * Returns `{ok:true}` or `{ok:false, reason}` — the reason is what the customer
 * is told, so it has to be specific enough to act on.
 */
export function validateSlot({
  startMs, durationMinutes, timezone, hours, appointments = [], closures = [],
  settings = {}, nowMs, resources = SOLO, exclude = [],
}) {
  const dateKey = shopDateKey(startMs, timezone);
  const slots = computeSlots({
    dateKey, timezone, hours, closures, durationMinutes, settings, nowMs,
    resources,
    // Moving a booking must not be blocked by where it currently sits.
    appointments: exclude.length === 0
      ? appointments
      : appointments.filter((a) => !exclude.includes(a.$id ?? a.id)),
  });
  if (slots.length === 0) return { ok: false, reason: 'closed' };

  const wanted = new Date(startMs).toISOString();
  const hit = slots.find((s) => s.start === wanted);
  if (!hit) return { ok: false, reason: 'taken' };
  return { ok: true, slot: hit, free: hit.free };
}

/**
 * Slot key for the unique index that stops two simultaneous bookings of one
 * chair at one instant.
 *
 * The resource is part of the key, so a three-chair shop can sell 10:00 three
 * times and no more — the database decides that, not application code.
 */
export function slotKeyFor(startMs, resource = SOLO_RESOURCE) {
  return `${resource}|${new Date(startMs).toISOString()}`;
}

/**
 * Which chair to give a booking, out of the ones free at that time.
 *
 * First fit, in the shop's own display order. Filling chair one before chair
 * two keeps whole chairs free for the long appointments, where spreading the
 * load would leave a three-chair shop unable to take a single colour
 * treatment by mid-morning. Staff can move anyone afterwards.
 */
export function pickResource(free, preferred = null) {
  if (!Array.isArray(free) || free.length === 0) return null;
  if (preferred && free.includes(String(preferred))) return String(preferred);
  return free[0];
}

/** Dead key parked on a cancelled row so its slot leaves the unique index. */
export function releasedSlotKey(rowId) {
  return `released|${rowId}`;
}

function clampInt(value, min, max, fallback) {
  const n = Number(value);
  if (!Number.isFinite(n)) return fallback;
  return Math.min(max, Math.max(min, Math.trunc(n)));
}
