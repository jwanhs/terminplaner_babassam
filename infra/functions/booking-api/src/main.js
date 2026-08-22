// Appwrite Function — the customer-facing booking API.
//
// This function exists because the customer app must not talk to the
// appointments table. That table holds every customer's name, phone number and
// whereabouts-at-a-given-hour; it is staff-only now, and this function is the
// narrow, audited door through which an anonymous customer may still book,
// look up, move and cancel *their own* appointment.
//
// Runtime:  node-22
// Trigger:  HTTP execution, execute("any")
//
// Env vars:
//   APPWRITE_API_KEY          server key with tablesDB read/write  (REQUIRED)
//   APPWRITE_FUNCTION_API_ENDPOINT / APPWRITE_FUNCTION_PROJECT_ID  (injected)
//   APPWRITE_INSECURE_TLS     "true" only for self-signed self-hosting
//   SMS_PROVIDER / TWILIO_*   OTP delivery; or OTP_DEV_MODE=true to pilot
//   SHOP_NAME                 used in the OTP message
//
// Request:  POST { "action": "...", ... }
// Response: { "ok": true, ... } | { "ok": false, "error": "code", "message": "…" }
//
// Every action that touches an existing booking requires proof of ownership:
// either the manage token minted for that booking, or a live OTP session for
// the phone number on it. There is no action that returns another person's
// data, and none that trusts a price, an amount or a paid flag from the client.

import { randomUUID } from 'node:crypto';

import { AppwriteDb, Q, isUniqueViolation } from './appwrite.js';
import {
  computeSlots, validateSlot, slotKeyFor, releasedSlotKey, pickResource,
  SOLO_RESOURCE,
} from './availability.js';
import { canRedeem, loyaltyCard } from './loyalty.js';
import * as otp from './otp.js';
import * as rate from './ratelimit.js';
import {
  hashToken, hashesEqual, mintToken, normalisePhone, looksLikePhone,
} from './tokens.js';
import { parseDateKey, shopDateKey, wallClockLabel, daysBetween, addDays } from './shoptime.js';

const DB_ID = process.env.APPWRITE_DATABASE_ID || 'barber_db';
const T_SERVICES = 'services';
const T_APPOINTMENTS = 'appointments';
const T_HOURS = 'business_hours';
const T_CLOSURES = 'closures';
const T_SETTINGS = 'shop_settings';
const T_RESOURCES = 'resources';

const STAMPS_PER_REWARD = Number(process.env.LOYALTY_STAMPS_PER_REWARD || 10);
const MAX_TOKENS_PER_CALL = 50;
const DAY_MS = 86400000;

export default async ({ req, res, log, error }) => {
  // Undici 6+ requires Web Streams to exist on module load.
  // We explicitly DO NOT polyfill fetch here to avoid VM sandbox termination bugs.
  if (!globalThis.ReadableStream) {
    const webStreams = await import('node:stream/web');
    Object.assign(globalThis, webStreams);
  }

  const apiKey = process.env.APPWRITE_API_KEY;
  if (!apiKey) {
    error('APPWRITE_API_KEY is not set on the function');
    return res.json({ ok: false, error: 'server_misconfigured' }, 500);
  }

  const db = new AppwriteDb({
    endpoint: process.env.APPWRITE_FUNCTION_API_ENDPOINT || 'https://cloud.appwrite.io/v1',
    projectId: process.env.APPWRITE_FUNCTION_PROJECT_ID,
    apiKey,
    databaseId: DB_ID,
  });

  return handle({ req, res, log, error, db });
};

/**
 * The router proper, with the database and clock handed in.
 *
 * Split out from the Appwrite entry point purely so the test suite can drive
 * every action against an in-memory double at a fixed instant — the
 * access-control rules in here are the ones worth a regression test, and they
 * are untestable if the function can only reach a live Appwrite at whatever
 * time the suite happens to run.
 */
export async function handle({ req, res, log, error, db, nowMs: fixedNow }) {
  let body = {};
  try {
    body = req.bodyJson ?? (req.body ? JSON.parse(req.body) : {});
  } catch {
    return res.json({ ok: false, error: 'bad_request', message: 'Body must be JSON.' }, 400);
  }

  const action = String(body.action ?? '');
  const nowMs = fixedNow ?? Date.now();
  const ip = rate.clientIp(req.headers ?? {});
  const ctx = { db, body, nowMs, ip, log, error };

  try {
    switch (action) {
      case 'catalog':      return res.json(await catalog(ctx));
      case 'availability': return await availability(ctx, res);
      case 'create':       return await create(ctx, res);
      case 'my':           return await mine(ctx, res);
      case 'cancel':       return await cancel(ctx, res);
      case 'reschedule':   return await reschedule(ctx, res);
      case 'redeem':       return await redeem(ctx, res);
      case 'status':       return await status(ctx, res);
      case 'otp_request':  return await otpRequest(ctx, res);
      case 'otp_verify':   return await otpVerify(ctx, res);
      default:
        return res.json({ ok: false, error: 'unknown_action', message: `Unknown action "${action}".` }, 400);
    }
  } catch (e) {
    error(`[${action}] ${e.stack || e.message}`);
    // Never leak an internal message to an anonymous caller.
    return res.json({ ok: false, error: 'server_error' }, 500);
  }
}

// --- shop configuration ------------------------------------------------------

async function loadSettings(db) {
  const row = await db.getRow(T_SETTINGS, 'default');
  return {
    timezone: row?.timezone || 'Europe/Berlin',
    buffer_minutes: row?.buffer_minutes ?? 0,
    lead_time_minutes: row?.lead_time_minutes ?? 30,
    cancel_cutoff_hours: row?.cancel_cutoff_hours ?? 12,
    max_advance_days: row?.max_advance_days ?? 30,
    max_open_per_phone: row?.max_open_per_phone ?? 3,
  };
}

/**
 * The chairs that can take a booking, in the order they should be filled.
 *
 * A shop with no `resources` rows is a one-chair shop and gets the implicit
 * resource every slot key it has ever written already names — which is what
 * lets this ship to existing deployments without a migration.
 *
 * The table is missing entirely on a deployment that has not re-run
 * setup_barber_db.sh, and that must degrade to a working one-chair shop
 * rather than a booking API that returns 500.
 */
async function loadResources(db) {
  let rows = [];
  try {
    rows = await db.listRows(T_RESOURCES, [
      Q.equal('active', true),
      Q.orderAsc('display_order'),
      Q.limit(50),
    ]);
  } catch {
    return [];
  }
  return rows;
}

function chairsOf(resources) {
  const ids = resources.map((r) => r.$id).filter(Boolean);
  return ids.length > 0 ? ids : [SOLO_RESOURCE];
}

async function loadHours(db) {
  const rows = await db.listRows(T_HOURS, [Q.limit(7)]);
  const byWeekday = {};
  for (const r of rows) byWeekday[Number(r.weekday)] = r;
  return byWeekday;
}

/**
 * Non-cancelled appointments that could touch the shop-local day [dateKey].
 * Widened by a day on each side so an appointment that starts late and runs
 * past midnight — or one on the far side of a timezone offset — is still seen.
 */
async function loadDayAppointments(db, dateKey, timezone) {
  const { year, month, day } = parseDateKey(dateKey);
  const anchor = Date.UTC(year, month - 1, day);
  const rows = await db.listRows(T_APPOINTMENTS, [
    Q.greaterThanEqual('start_at', new Date(anchor - DAY_MS).toISOString()),
    Q.lessThan('start_at', new Date(anchor + 2 * DAY_MS).toISOString()),
    Q.notEqual('status', 'cancelled'),
    Q.orderAsc('start_at'),
    Q.limit(200),
  ]);
  return rows;
}

async function loadClosures(db, dateKey) {
  const { year, month, day } = parseDateKey(dateKey);
  const anchor = Date.UTC(year, month - 1, day);
  return db.listRows(T_CLOSURES, [
    Q.lessThan('starts_at', new Date(anchor + 2 * DAY_MS).toISOString()),
    Q.greaterThanEqual('ends_at', new Date(anchor - DAY_MS).toISOString()),
    Q.limit(100),
  ]);
}

// --- actions -----------------------------------------------------------------

/** Public price list + opening hours + the booking rules, in one round trip. */
async function catalog({ db }) {
  const [services, hours, settings] = await Promise.all([
    db.listRows(T_SERVICES, [Q.orderAsc('display_order'), Q.limit(50)]),
    loadHours(db),
    loadSettings(db),
  ]);
  return {
    ok: true,
    services: services
      .filter((s) => s.active !== false)
      .map((s) => ({
        id: s.$id,
        name: s.name,
        description: s.description ?? null,
        durationMinutes: s.duration_minutes,
        priceCents: s.price_cents,
        displayOrder: s.display_order ?? 100,
      })),
    hours: Object.values(hours).map((h) => ({
      weekday: h.weekday,
      openTime: h.open_time,
      closeTime: h.close_time,
      breakStart: h.break_start ?? null,
      breakEnd: h.break_end ?? null,
      closed: h.closed ?? false,
    })),
    settings: {
      timezone: settings.timezone,
      cancelCutoffHours: settings.cancel_cutoff_hours,
      maxAdvanceDays: settings.max_advance_days,
      leadTimeMinutes: settings.lead_time_minutes,
    },
    loyalty: { stampsPerReward: STAMPS_PER_REWARD },
  };
}

/**
 * Free slots for one day and one service. Returns times only — no hint of who
 * holds the busy ones. A taken slot is simply absent.
 */
async function availability({ db, body, nowMs }, res) {
  const serviceId = String(body.serviceId ?? '');
  if (!serviceId) return res.json(bad('bad_request', 'serviceId is required.'), 400);

  const settings = await loadSettings(db);
  const timezone = settings.timezone;
  const dateKey = String(body.date ?? shopDateKey(nowMs, timezone));

  let parsed;
  try { parsed = parseDateKey(dateKey); } catch {
    return res.json(bad('bad_request', 'date must be YYYY-MM-DD.'), 400);
  }

  const service = await db.getRow(T_SERVICES, serviceId);
  if (!service || service.active === false) {
    return res.json(bad('not_found', 'Unknown service.'), 404);
  }

  const [hours, appointments, closures, resources] = await Promise.all([
    loadHours(db),
    loadDayAppointments(db, dateKey, timezone),
    loadClosures(db, dateKey),
    loadResources(db),
  ]);

  const weekday = weekdayOf(parsed);
  const slots = computeSlots({
    resources: chairsOf(resources),
    dateKey,
    timezone,
    hours: hours[weekday],
    appointments,
    closures,
    durationMinutes: service.duration_minutes,
    settings,
    nowMs,
  });

  return res.json({
    ok: true,
    date: dateKey,
    timezone,
    serviceId,
    durationMinutes: service.duration_minutes,
    // Times only. Which chair is free at 10:00 says which chair is busy at
    // 10:00, and a customer has no business knowing the shop's occupancy.
    slots: slots.map(({ start, end, label }) => ({ start, end, label })),
  });
}

/**
 * Book a slot.
 *
 * The client sends a service, a start instant, a name and a phone number — and
 * nothing else. Duration, price, end time and status are all decided here; a
 * client that sends `priceCents: 1` or `paid: true` is simply ignored, because
 * those fields are never read from the request.
 */
async function create({ db, body, nowMs, ip }, res) {
  const serviceId = String(body.serviceId ?? '');
  const startIso = String(body.start ?? '');
  const name = String(body.name ?? '').trim().slice(0, 120);
  const phone = normalisePhone(body.phone);
  const notes = String(body.notes ?? '').trim().slice(0, 500);

  if (name.length < 2) return res.json(bad('bad_request', 'Bitte Namen angeben.'), 400);
  if (!looksLikePhone(phone)) return res.json(bad('bad_request', 'Bitte gültige Telefonnummer angeben.'), 400);

  const startMs = Date.parse(startIso);
  if (!Number.isFinite(startMs)) return res.json(bad('bad_request', 'start must be an ISO instant.'), 400);

  // Two brakes: one on the caller, one on the phone number. Neither is a
  // security boundary — they just stop a script owning the calendar.
  const byIp = await rate.hit(db, { kind: 'book_ip', key: ip, limit: 12, windowSec: 3600, nowMs });
  if (!byIp.allowed) return res.json(bad('rate_limited', 'Zu viele Anfragen. Bitte später erneut versuchen.'), 429);
  const byPhone = await rate.hit(db, { kind: 'book_phone', key: phone, limit: 6, windowSec: 3600, nowMs });
  if (!byPhone.allowed) return res.json(bad('rate_limited', 'Zu viele Buchungen für diese Nummer.'), 429);

  const settings = await loadSettings(db);
  const timezone = settings.timezone;

  const service = await db.getRow(T_SERVICES, serviceId);
  if (!service || service.active === false) {
    return res.json(bad('not_found', 'Diese Leistung gibt es nicht mehr.'), 404);
  }

  // How many live bookings this number already holds.
  const open = await db.listRows(T_APPOINTMENTS, [
    Q.equal('customer_phone', phone),
    Q.notEqual('status', 'cancelled'),
    Q.greaterThanEqual('start_at', new Date(nowMs).toISOString()),
    Q.limit(50),
  ]);
  if (open.length >= settings.max_open_per_phone) {
    return res.json(bad('too_many_open',
      `Für diese Nummer sind bereits ${open.length} Termine offen.`), 409);
  }

  const dateKey = shopDateKey(startMs, timezone);
  const [hours, appointments, closures, resources] = await Promise.all([
    loadHours(db),
    loadDayAppointments(db, dateKey, timezone),
    loadClosures(db, dateKey),
    loadResources(db),
  ]);
  const chairs = chairsOf(resources);

  // The authoritative check. The customer's grid was drawn from exactly this
  // function; re-running it here is what stops a stale or forged slot landing.
  const check = validateSlot({
    startMs,
    durationMinutes: service.duration_minutes,
    timezone,
    hours: hours[weekdayOf(parseDateKey(dateKey))],
    appointments,
    closures,
    settings,
    nowMs,
    resources: chairs,
  });
  if (!check.ok) {
    return res.json(bad(check.reason === 'taken' ? 'slot_taken' : 'slot_unavailable',
      check.reason === 'taken'
        ? 'Dieser Termin wurde gerade vergeben.'
        : 'Zu dieser Zeit ist leider geschlossen.'), 409);
  }

  const endMs = startMs + service.duration_minutes * 60000;
  const manageToken = mintToken();
  const rowId = randomUUID().replace(/-/g, '').slice(0, 20);

  // Claim a chair.
  //
  // The unique index on slot_key is per chair, so a collision means somebody
  // took *that* chair between our read and our insert. In a one-chair shop
  // that is the end of it; in a three-chair shop it is not — the slot is still
  // for sale on another chair, and telling the customer it is gone would be a
  // lie the shop pays for. So this walks the free chairs rather than failing
  // on the first one.
  let row = null;
  let chair = null;
  const candidates = [...check.free];

  while (candidates.length > 0) {
    chair = pickResource(candidates);
    candidates.splice(candidates.indexOf(chair), 1);

    try {
      row = await db.createRow(T_APPOINTMENTS, rowId, {
        customer_name: name,
        customer_phone: phone,
        service_id: serviceId,
        service_name: service.name,
        start_at: new Date(startMs).toISOString(),
        end_at: new Date(endMs).toISOString(),
        status: 'confirmed',
        paid: false,
        payment_amount_cents: 0,
        discount_cents: 0,
        manage_token_hash: hashToken(manageToken),
        slot_key: slotKeyFor(startMs, chair),
        resource_id: chair,
        source: 'online',
        ...(notes ? { notes } : {}),
      });
      break;
    } catch (e) {
      if (isUniqueViolation(e)) continue;
      throw e;
    }
  }

  if (!row) {
    // Every chair that was free when we looked has since been taken.
    return res.json(bad('slot_taken', 'Dieser Termin wurde gerade vergeben.'), 409);
  }

  // The unique key only catches an identical start. A *different* start whose
  // appointment overlaps ours can still have landed concurrently, so re-read
  // and stand down if someone booked across us first.
  const loser = await losesRace(db, row, startMs, endMs, settings);
  if (loser) {
    await db.updateRow(T_APPOINTMENTS, row.$id, {
      status: 'cancelled',
      slot_key: releasedSlotKey(row.$id),
    }).catch(() => {});
    return res.json(bad('slot_taken', 'Dieser Termin wurde gerade vergeben.'), 409);
  }

  return res.json({
    ok: true,
    manageToken,
    appointment: publicAppointment(row, settings.timezone),
  });
}

/**
 * Did another overlapping booking beat this one? Ties break on row id so two
 * racing executions always pick the same winner and never both stand down.
 */
async function losesRace(db, row, startMs, endMs, settings) {
  const buffer = (settings.buffer_minutes ?? 0) * 60000;
  // Overlapping in time is only a conflict on the *same* chair. Without this
  // a three-chair shop would cancel two of every three simultaneous bookings.
  const chair = row.resource_id || SOLO_RESOURCE;
  const sameWindow = await db.listRows(T_APPOINTMENTS, [
    Q.greaterThanEqual('start_at', new Date(startMs - 12 * 3600000).toISOString()),
    Q.lessThan('start_at', new Date(endMs + 12 * 3600000).toISOString()),
    Q.notEqual('status', 'cancelled'),
    Q.limit(200),
  ]);
  return sameWindow.some((other) => {
    if (other.$id === row.$id) return false;
    if ((other.resource_id || SOLO_RESOURCE) !== chair) return false;
    const oStart = Date.parse(other.start_at) - buffer;
    const oEnd = Date.parse(other.end_at) + buffer;
    const overlaps = startMs < oEnd && oStart < endMs;
    if (!overlaps) return false;
    const oCreated = Date.parse(other.$createdAt ?? 0);
    const myCreated = Date.parse(row.$createdAt ?? 0);
    if (oCreated !== myCreated) return oCreated < myCreated;
    return String(other.$id) < String(row.$id);
  });
}

/**
 * The caller's own appointments.
 *
 * Two ways to prove they are the caller's: manage tokens held on the device
 * (the frictionless path, no code needed), or a live OTP session for the phone
 * number (the path for a new device). Anything not proved is not returned.
 */
async function mine({ db, body, nowMs }, res) {
  const tokens = Array.isArray(body.tokens) ? body.tokens.slice(0, MAX_TOKENS_PER_CALL) : [];
  const session = body.session ? String(body.session) : null;
  const settings = await loadSettings(db);

  const found = new Map();

  if (tokens.length) {
    const hashes = tokens.map((t) => hashToken(String(t)));
    const rows = await db.listRows(T_APPOINTMENTS, [
      Q.equal('manage_token_hash', hashes),
      Q.orderDesc('start_at'),
      Q.limit(100),
    ]);
    for (const r of rows) found.set(r.$id, r);
  }

  let phone = null;
  if (session) {
    phone = await otp.phoneForSession(db, { session, nowMs });
    if (!phone) return res.json(bad('session_expired', 'Bitte erneut bestätigen.'), 401);
    const rows = await db.listRows(T_APPOINTMENTS, [
      Q.equal('customer_phone', phone),
      Q.orderDesc('start_at'),
      Q.limit(100),
    ]);
    for (const r of rows) found.set(r.$id, r);
  }

  const rows = [...found.values()].sort((a, b) => Date.parse(b.start_at) - Date.parse(a.start_at));

  // The stamp card only makes sense for a verified number: derived from a
  // handful of device-held tokens it would under-count and confuse people.
  const card = phone
    ? loyaltyCard(rows.filter((r) => r.customer_phone === phone), nowMs, STAMPS_PER_REWARD)
    : null;

  return res.json({
    ok: true,
    appointments: rows.map((r) => publicAppointment(r, settings.timezone)),
    loyalty: card,
    verifiedPhone: phone,
  });
}

async function cancel({ db, body, nowMs }, res) {
  const auth = await authoriseAppointment({ db, body, nowMs });
  if (!auth.ok) return res.json(bad(auth.error, auth.message), auth.code);

  const { row, settings } = auth;
  if (row.status === 'cancelled') {
    return res.json({ ok: true, appointment: publicAppointment(row, settings.timezone) });
  }

  const cutoffMs = settings.cancel_cutoff_hours * 3600000;
  if (Date.parse(row.start_at) - nowMs < cutoffMs) {
    return res.json(bad('too_late',
      `Online-Stornierung ist bis ${settings.cancel_cutoff_hours} Stunden vorher möglich. `
      + 'Bitte im Salon anrufen.'), 409);
  }

  const updated = await db.updateRow(T_APPOINTMENTS, row.$id, {
    status: 'cancelled',
    // Free the slot for the next customer.
    slot_key: releasedSlotKey(row.$id),
  });
  return res.json({ ok: true, appointment: publicAppointment(updated, settings.timezone) });
}

async function reschedule({ db, body, nowMs }, res) {
  const auth = await authoriseAppointment({ db, body, nowMs });
  if (!auth.ok) return res.json(bad(auth.error, auth.message), auth.code);

  const { row, settings } = auth;
  const timezone = settings.timezone;

  if (row.status === 'cancelled') {
    return res.json(bad('cancelled', 'Dieser Termin wurde storniert.'), 409);
  }
  if (Date.parse(row.start_at) - nowMs < settings.cancel_cutoff_hours * 3600000) {
    return res.json(bad('too_late',
      `Online-Umbuchung ist bis ${settings.cancel_cutoff_hours} Stunden vorher möglich. `
      + 'Bitte im Salon anrufen.'), 409);
  }

  const startMs = Date.parse(String(body.start ?? ''));
  if (!Number.isFinite(startMs)) return res.json(bad('bad_request', 'start must be an ISO instant.'), 400);

  const service = await db.getRow(T_SERVICES, row.service_id);
  const duration = service?.duration_minutes
    ?? Math.round((Date.parse(row.end_at) - Date.parse(row.start_at)) / 60000);

  const dateKey = shopDateKey(startMs, timezone);
  const [hours, appointments, closures, resources] = await Promise.all([
    loadHours(db),
    loadDayAppointments(db, dateKey, timezone),
    loadClosures(db, dateKey),
    loadResources(db),
  ]);

  const check = validateSlot({
    startMs,
    durationMinutes: duration,
    timezone,
    appointments,
    // The booking's own current slot must not block its own move.
    exclude: [row.$id],
    hours: hours[weekdayOf(parseDateKey(dateKey))],
    closures,
    settings,
    nowMs,
    resources: chairsOf(resources),
  });
  if (!check.ok) {
    return res.json(bad('slot_taken', 'Dieser Termin ist nicht mehr frei.'), 409);
  }

  const endMs = startMs + duration * 60000;

  // Prefer to stay on the chair the booking is already on. Moving a customer
  // from Tuesday to Wednesday should not also move them to a different barber
  // when their own is free at the new time.
  const candidates = [...check.free];
  let updated = null;
  let chair = null;

  while (candidates.length > 0) {
    chair = pickResource(candidates, row.resource_id);
    candidates.splice(candidates.indexOf(chair), 1);

    try {
      updated = await db.updateRow(T_APPOINTMENTS, row.$id, {
        start_at: new Date(startMs).toISOString(),
        end_at: new Date(endMs).toISOString(),
        slot_key: slotKeyFor(startMs, chair),
        resource_id: chair,
      });
      break;
    } catch (e) {
      if (isUniqueViolation(e)) continue;
      throw e;
    }
  }

  if (!updated) {
    return res.json(bad('slot_taken', 'Dieser Termin ist nicht mehr frei.'), 409);
  }
  return res.json({ ok: true, appointment: publicAppointment(updated, timezone) });
}

/**
 * Spend a loyalty reward on a booking.
 *
 * Used to be a client-side write to `discount_cents` on a world-writable
 * table — i.e. free haircuts for anyone who could send an HTTP request. The
 * entitlement is now recomputed here from the customer's own history, and the
 * discount is the service's real price, not a number off the wire.
 */
async function redeem({ db, body, nowMs }, res) {
  const auth = await authoriseAppointment({ db, body, nowMs });
  if (!auth.ok) return res.json(bad(auth.error, auth.message), auth.code);

  const { row, settings } = auth;
  const history = await db.listRows(T_APPOINTMENTS, [
    Q.equal('customer_phone', row.customer_phone),
    Q.orderDesc('start_at'),
    Q.limit(200),
  ]);

  const verdict = canRedeem({
    target: row, appts: history, nowMs, stampsPerReward: STAMPS_PER_REWARD,
  });
  if (!verdict.ok) {
    const messages = {
      no_reward: 'Noch keine Treueprämie verfügbar.',
      already_redeemed: 'Für diesen Termin wurde bereits eine Prämie eingelöst.',
      already_paid: 'Dieser Termin ist bereits bezahlt.',
      past: 'Dieser Termin liegt in der Vergangenheit.',
      cancelled: 'Dieser Termin wurde storniert.',
    };
    return res.json(bad(verdict.reason, messages[verdict.reason] ?? 'Einlösen nicht möglich.'), 409);
  }

  const service = await db.getRow(T_SERVICES, row.service_id);
  const discount = Number(service?.price_cents ?? 0);
  if (discount <= 0) return res.json(bad('no_price', 'Für diese Leistung ist kein Preis hinterlegt.'), 409);

  const updated = await db.updateRow(T_APPOINTMENTS, row.$id, { discount_cents: discount });
  return res.json({
    ok: true,
    appointment: publicAppointment(updated, settings.timezone),
    loyalty: loyaltyCard(
      history.map((h) => (h.$id === row.$id ? { ...h, discount_cents: discount } : h)),
      nowMs, STAMPS_PER_REWARD,
    ),
  });
}

/**
 * Current state of one booking. The customer app polls this after the Stripe
 * sheet closes, because `paid` is now written by the Stripe webhook and never
 * by the client — so the app has to ask rather than assert.
 */
async function status({ db, body, nowMs }, res) {
  const auth = await authoriseAppointment({ db, body, nowMs });
  if (!auth.ok) return res.json(bad(auth.error, auth.message), auth.code);
  return res.json({
    ok: true,
    appointment: publicAppointment(auth.row, auth.settings.timezone),
  });
}

async function otpRequest({ db, body, nowMs, ip, log, error }, res) {
  const phone = normalisePhone(body.phone);
  if (!looksLikePhone(phone)) return res.json(bad('bad_request', 'Bitte gültige Telefonnummer angeben.'), 400);

  const byPhone = await rate.hit(db, { kind: 'otp_phone', key: phone, limit: 5, windowSec: 3600, nowMs });
  const byIp = await rate.hit(db, { kind: 'otp_ip', key: ip, limit: 20, windowSec: 3600, nowMs });
  if (!byPhone.allowed || !byIp.allowed) {
    return res.json(bad('rate_limited', 'Zu viele Code-Anfragen. Bitte später erneut versuchen.'), 429);
  }

  const out = await otp.requestOtp(db, { phone, nowMs, log, error });
  // Housekeeping rides along on a low-traffic action rather than a cron.
  await otp.prune(db, { nowMs });
  await rate.prune(db, { nowMs });

  if (!out.sent) return res.json(bad('sms_unavailable', 'Code konnte nicht gesendet werden.'), 503);
  return res.json({ ok: true, expiresInSec: otp.OTP_TTL_SEC, devCode: out.devCode });
}

async function otpVerify({ db, body, nowMs, ip }, res) {
  const phone = normalisePhone(body.phone);
  const code = String(body.code ?? '').trim();
  if (!looksLikePhone(phone) || !/^\d{6}$/.test(code)) {
    return res.json(bad('bad_request', 'Bitte Nummer und 6-stelligen Code angeben.'), 400);
  }

  const byIp = await rate.hit(db, { kind: 'otp_try', key: ip, limit: 30, windowSec: 3600, nowMs });
  if (!byIp.allowed) return res.json(bad('rate_limited', 'Zu viele Versuche.'), 429);

  const out = await otp.verifyOtp(db, { phone, code, nowMs });
  if (!out.ok) {
    const messages = {
      no_code: 'Kein Code angefordert.',
      used: 'Dieser Code wurde bereits verwendet.',
      expired: 'Der Code ist abgelaufen.',
      locked: 'Zu viele Fehlversuche. Bitte neuen Code anfordern.',
      wrong_code: 'Code stimmt nicht.',
    };
    return res.json(bad(out.reason, messages[out.reason] ?? 'Bestätigung fehlgeschlagen.'), 401);
  }
  return res.json({ ok: true, session: out.session, expiresInSec: out.expiresInSec });
}

// --- authorisation -----------------------------------------------------------

/**
 * Resolve `appointmentId` from the request and prove the caller owns it.
 *
 * Accepts either the manage token minted at booking time, or a live OTP
 * session whose phone number matches the row. Everything that mutates or
 * reveals a booking goes through here — there is no second path.
 */
async function authoriseAppointment({ db, body, nowMs }) {
  const id = String(body.appointmentId ?? '');
  if (!id) return { ok: false, error: 'bad_request', message: 'appointmentId is required.', code: 400 };

  const [row, settings] = await Promise.all([
    db.getRow(T_APPOINTMENTS, id),
    loadSettings(db),
  ]);
  // Same answer for "does not exist" and "not yours": a 404 that distinguishes
  // them is an oracle for probing which booking ids are real.
  const denied = { ok: false, error: 'not_found', message: 'Termin nicht gefunden.', code: 404 };
  if (!row) return denied;

  const token = body.token ? String(body.token) : null;
  if (token && row.manage_token_hash && hashesEqual(row.manage_token_hash, hashToken(token))) {
    return { ok: true, row, settings };
  }

  const session = body.session ? String(body.session) : null;
  if (session) {
    const phone = await otp.phoneForSession(db, { session, nowMs });
    if (phone && phone === row.customer_phone) return { ok: true, row, settings };
  }

  return denied;
}

// --- shaping -----------------------------------------------------------------

/**
 * The only shape an appointment leaves this function in. Note what is absent:
 * the token hash, the Stripe intent id, the slot key, the internal notes on
 * anyone else's row. Add fields here deliberately, never by spreading `row`.
 */
function publicAppointment(row, timezone) {
  return {
    id: row.$id,
    customerName: row.customer_name,
    customerPhone: row.customer_phone,
    serviceId: row.service_id,
    serviceName: row.service_name,
    startAt: row.start_at,
    endAt: row.end_at,
    startLabel: wallClockLabel(Date.parse(row.start_at), timezone),
    dateKey: shopDateKey(Date.parse(row.start_at), timezone),
    status: row.status ?? 'confirmed',
    notes: row.notes ?? null,
    paid: row.paid ?? false,
    paymentAmountCents: row.payment_amount_cents ?? 0,
    discountCents: row.discount_cents ?? 0,
  };
}

function weekdayOf({ year, month, day }) {
  // JS: 0 = Sun … 6 = Sat. business_hours: 0 = Mon … 6 = Sun.
  return (new Date(Date.UTC(year, month - 1, day)).getUTCDay() + 6) % 7;
}

function bad(error, message) {
  return { ok: false, error, message };
}

// Re-exported for the test suite and for tooling that wants the same helpers.
export { computeSlots, daysBetween, addDays };
