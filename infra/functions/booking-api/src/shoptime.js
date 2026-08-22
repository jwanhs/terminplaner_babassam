// Wall-clock arithmetic in the shop's own timezone.
//
// WHY THIS EXISTS: the old client computed slots with `DateTime.now()` on the
// customer's phone and stored the result as UTC. A phone set to another
// timezone — a tourist, a traveller, a device with a wrong clock — booked the
// wrong hour, and twice a year DST moved every slot in the grid. Availability
// is now computed here, in the shop's zone, and the client only ever renders
// what the server already decided.
//
// No dependencies: Node ships a full IANA tz database behind Intl.

/**
 * Offset of [tz] from UTC, in milliseconds, at the instant [utcMs].
 * Positive east of Greenwich (Europe/Berlin is +1h or +2h).
 */
export function tzOffsetMs(utcMs, tz) {
  const dtf = new Intl.DateTimeFormat('en-US', {
    timeZone: tz,
    hour12: false,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
  });
  const parts = dtf.formatToParts(new Date(utcMs));
  const get = (type) => Number(parts.find((p) => p.type === type).value);
  // Some ICU versions emit hour "24" for midnight under hour12:false.
  const hour = get('hour') % 24;
  const asIfUtc = Date.UTC(
    get('year'), get('month') - 1, get('day'),
    hour, get('minute'), get('second'),
  );
  return asIfUtc - utcMs;
}

/** The wall-clock fields [tz] shows at the instant [utcMs]. */
export function wallPartsOf(utcMs, tz) {
  const dtf = new Intl.DateTimeFormat('en-US', {
    timeZone: tz,
    hour12: false,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    weekday: 'short',
  });
  const parts = dtf.formatToParts(new Date(utcMs));
  const get = (type) => parts.find((p) => p.type === type).value;
  const WD = { Mon: 0, Tue: 1, Wed: 2, Thu: 3, Fri: 4, Sat: 5, Sun: 6 };
  return {
    year: Number(get('year')),
    month: Number(get('month')),
    day: Number(get('day')),
    hour: Number(get('hour')) % 24,
    minute: Number(get('minute')),
    // ISO-ish weekday matching the business_hours table: 0 = Mon … 6 = Sun.
    weekday: WD[get('weekday')],
  };
}

/**
 * Convert a wall-clock time in [tz] to a UTC epoch-ms instant.
 *
 * Returns `null` when that wall time does not exist — the hour skipped by the
 * spring-forward transition. Callers drop such slots: you cannot get a haircut
 * at 02:30 on a day where 02:30 never happens.
 *
 * On the autumn fall-back day one wall time occurs twice. This resolves to the
 * *earlier* of the two, matching the "compatible" disambiguation every other
 * date library picks, so a shop that somehow trades at 02:30 opens once rather
 * than mysteriously an hour late.
 */
export function zonedWallToUtc({ year, month, day, hour, minute }, tz) {
  const naive = Date.UTC(year, month - 1, day, hour, minute);

  // A transition is never less than a day from another, so the offsets a day
  // either side of the target bracket every case: normal (both equal), gap
  // (neither candidate round-trips) and ambiguous (both do, an hour apart).
  const candidates = new Set([
    naive - tzOffsetMs(naive - 86400000, tz),
    naive - tzOffsetMs(naive + 86400000, tz),
  ]);

  let best = null;
  for (const ts of candidates) {
    const back = wallPartsOf(ts, tz);
    const matches = back.year === year && back.month === month && back.day === day &&
      back.hour === hour && back.minute === minute;
    if (matches && (best === null || ts < best)) best = ts;
  }
  return best;
}

/** "HH:mm" as shown on the shop's own wall clock at [utcMs]. */
export function wallClockLabel(utcMs, tz) {
  const p = wallPartsOf(utcMs, tz);
  return `${String(p.hour).padStart(2, '0')}:${String(p.minute).padStart(2, '0')}`;
}

/** "YYYY-MM-DD" for the shop-local calendar day containing [utcMs]. */
export function shopDateKey(utcMs, tz) {
  const p = wallPartsOf(utcMs, tz);
  return `${p.year}-${String(p.month).padStart(2, '0')}-${String(p.day).padStart(2, '0')}`;
}

/** Parse "YYYY-MM-DD" into calendar fields. Throws on anything else. */
export function parseDateKey(key) {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(key ?? ''));
  if (!m) throw new Error(`Invalid date "${key}", expected YYYY-MM-DD`);
  const year = Number(m[1]);
  const month = Number(m[2]);
  const day = Number(m[3]);
  if (month < 1 || month > 12 || day < 1 || day > 31) {
    throw new Error(`Invalid date "${key}"`);
  }
  return { year, month, day };
}

/** Parse "HH:mm" into minutes since midnight. Returns null if unparseable. */
export function parseHm(hm) {
  const m = /^(\d{1,2}):(\d{2})$/.exec(String(hm ?? '').trim());
  if (!m) return null;
  const h = Number(m[1]);
  const min = Number(m[2]);
  if (h > 23 || min > 59) return null;
  return h * 60 + min;
}

/** Shop-local calendar day [key] advanced by [n] days, as a new date key. */
export function addDays(key, n) {
  const { year, month, day } = parseDateKey(key);
  const d = new Date(Date.UTC(year, month - 1, day));
  d.setUTCDate(d.getUTCDate() + n);
  return `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, '0')}-${String(d.getUTCDate()).padStart(2, '0')}`;
}

/** Whole days from shop-day [fromKey] to shop-day [toKey] (may be negative). */
export function daysBetween(fromKey, toKey) {
  const a = parseDateKey(fromKey);
  const b = parseDateKey(toKey);
  const ms = Date.UTC(b.year, b.month - 1, b.day) - Date.UTC(a.year, a.month - 1, a.day);
  return Math.round(ms / 86400000);
}
