// Fixed-window rate limiting, backed by the private `rate_limits` table.
//
// Without this, one loop fills the shop's calendar for a month, or walks the
// OTP keyspace. Buckets are hashed so the table never accumulates a plain-text
// list of phone numbers and IP addresses beside the one that already exists
// for good reason.

import { createHash } from 'node:crypto';
import { Q } from './appwrite.js';

const T_RATE = 'rate_limits';

function bucketId(kind, key) {
  return `${kind}_${createHash('sha256').update(String(key)).digest('hex').slice(0, 40)}`;
}

/**
 * Count one hit against `kind:key`. Returns `{ allowed, remaining, retryAfterSec }`.
 *
 * Fails *open* on infrastructure errors: a broken counter table must not stop
 * a shop taking bookings. It is a spam brake, not an authorisation check —
 * everything that actually protects data is enforced elsewhere.
 */
export async function hit(db, { kind, key, limit, windowSec, nowMs }) {
  const id = bucketId(kind, key);
  const windowMs = windowSec * 1000;
  try {
    const existing = await db.getRow(T_RATE, id);
    if (!existing) {
      await db.createRow(T_RATE, id, {
        bucket: id,
        count: 1,
        window_start: new Date(nowMs).toISOString(),
      });
      return { allowed: true, remaining: limit - 1, retryAfterSec: 0 };
    }

    const startedMs = Date.parse(existing.window_start);
    const expired = !Number.isFinite(startedMs) || nowMs - startedMs >= windowMs;
    if (expired) {
      await db.updateRow(T_RATE, id, {
        count: 1,
        window_start: new Date(nowMs).toISOString(),
      });
      return { allowed: true, remaining: limit - 1, retryAfterSec: 0 };
    }

    const count = Number(existing.count ?? 0) + 1;
    if (count > limit) {
      return {
        allowed: false,
        remaining: 0,
        retryAfterSec: Math.ceil((startedMs + windowMs - nowMs) / 1000),
      };
    }
    await db.updateRow(T_RATE, id, { count });
    return { allowed: true, remaining: limit - count, retryAfterSec: 0 };
  } catch {
    return { allowed: true, remaining: limit, retryAfterSec: 0 };
  }
}

/** Best-effort sweep of windows nobody has touched in a day. */
export async function prune(db, { nowMs, olderThanSec = 86400 }) {
  try {
    const stale = await db.listRows(T_RATE, [
      Q.lessThan('window_start', new Date(nowMs - olderThanSec * 1000).toISOString()),
      Q.limit(100),
    ]);
    await Promise.all(stale.map((r) => db.deleteRow(T_RATE, r.$id).catch(() => {})));
  } catch { /* housekeeping only */ }
}

/**
 * Caller's IP, for anonymous rate limiting. Appwrite sits behind its own proxy,
 * so the left-most X-Forwarded-For entry is the client.
 */
export function clientIp(headers = {}) {
  const fwd = headers['x-forwarded-for'] ?? headers['X-Forwarded-For'];
  if (typeof fwd === 'string' && fwd.length) return fwd.split(',')[0].trim();
  return headers['x-real-ip'] ?? 'unknown';
}
