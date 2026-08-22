// Phone verification for "show me my appointments".
//
// Booking itself stays friction-free — that is the product. But the old
// lookup returned a person's full visit history to anyone who typed their
// number, which is an enumeration hole with real names and times behind it.
// So: looking up history by phone costs one SMS code. Devices that already
// hold a manage token from booking skip this entirely and see their own
// bookings with no code at all.
//
// The sender is pluggable. With no provider configured the code is written to
// the function log so a shop can pilot the flow before signing up for SMS;
// that fallback refuses to run unless OTP_DEV_MODE is explicitly set, so it
// can't be left on by accident in production.

import { Q } from './appwrite.js';
import { hashToken, hashesEqual, mintOtp, mintToken } from './tokens.js';

const T_OTP = 'otp_codes';

export const OTP_TTL_SEC = 10 * 60;
export const SESSION_TTL_SEC = 30 * 60;
const MAX_ATTEMPTS = 5;

/**
 * Create and send a code for [phone]. Returns `{ sent, devCode }` — `devCode`
 * is only ever populated in dev mode.
 */
export async function requestOtp(db, { phone, nowMs, log, error }) {
  const code = mintOtp();
  const id = `otp_${hashToken(phone).slice(0, 32)}`;

  const row = {
    phone,
    code_hash: hashToken(code),
    expires_at: new Date(nowMs + OTP_TTL_SEC * 1000).toISOString(),
    attempts: 0,
    consumed: false,
  };

  // One live code per number: re-requesting replaces the previous one.
  const existing = await db.getRow(T_OTP, id);
  if (existing) await db.updateRow(T_OTP, id, row);
  else await db.createRow(T_OTP, id, row);

  const delivery = await sendSms(phone, code, { log, error });
  return {
    sent: delivery.sent,
    channel: delivery.channel,
    devCode: delivery.channel === 'log' ? code : undefined,
  };
}

/**
 * Check [code] for [phone]. On success returns `{ ok:true, session }` where
 * `session` is a short-lived token the client sends with lookup calls.
 */
export async function verifyOtp(db, { phone, code, nowMs }) {
  const id = `otp_${hashToken(phone).slice(0, 32)}`;
  const row = await db.getRow(T_OTP, id);
  if (!row) return { ok: false, reason: 'no_code' };

  if (row.consumed) return { ok: false, reason: 'used' };
  if (Date.parse(row.expires_at) <= nowMs) return { ok: false, reason: 'expired' };
  if (Number(row.attempts ?? 0) >= MAX_ATTEMPTS) return { ok: false, reason: 'locked' };

  if (!hashesEqual(row.code_hash, hashToken(code))) {
    await db.updateRow(T_OTP, id, { attempts: Number(row.attempts ?? 0) + 1 });
    return { ok: false, reason: 'wrong_code' };
  }

  const session = mintToken();
  await db.updateRow(T_OTP, id, {
    consumed: true,
    session_hash: hashToken(session),
    session_expires_at: new Date(nowMs + SESSION_TTL_SEC * 1000).toISOString(),
  });
  return { ok: true, session, expiresInSec: SESSION_TTL_SEC };
}

/** The phone number a live session token belongs to, or null. */
export async function phoneForSession(db, { session, nowMs }) {
  if (!session) return null;
  const rows = await db.listRows(T_OTP, [
    Q.equal('session_hash', hashToken(session)),
    Q.limit(1),
  ]);
  const row = rows[0];
  if (!row) return null;
  if (Date.parse(row.session_expires_at) <= nowMs) return null;
  return row.phone;
}

/** Best-effort sweep of codes and sessions that have both expired. */
export async function prune(db, { nowMs }) {
  try {
    const stale = await db.listRows(T_OTP, [
      Q.lessThan('expires_at', new Date(nowMs - SESSION_TTL_SEC * 1000).toISOString()),
      Q.limit(100),
    ]);
    await Promise.all(stale.map((r) => db.deleteRow(T_OTP, r.$id).catch(() => {})));
  } catch { /* housekeeping only */ }
}

// --- delivery ----------------------------------------------------------------

async function sendSms(phone, code, { log, error }) {
  const provider = (process.env.SMS_PROVIDER || '').toLowerCase();
  const text = `${code} — dein Code für ${process.env.SHOP_NAME || "BaBa'Ssam"}. Gilt 10 Minuten.`;

  if (provider === 'twilio') {
    const sid = process.env.TWILIO_ACCOUNT_SID;
    const token = process.env.TWILIO_AUTH_TOKEN;
    const from = process.env.TWILIO_FROM;

    if (!sid || !token || !from) {
      error('SMS_PROVIDER=twilio but TWILIO_ACCOUNT_SID/AUTH_TOKEN/FROM are incomplete');
      return { sent: false, channel: 'none' };
    }

    try {
      const { request } = await import('undici');
      const res = await request(
        `https://api.twilio.com/2010-04-01/Accounts/${sid}/Messages.json`,
        {
          method: 'POST',
          headers: {
            Authorization: `Basic ${Buffer.from(`${sid}:${token}`).toString('base64')}`,
            'Content-Type': 'application/x-www-form-urlencoded',
          },
          // URLSearchParams must be explicitly cast to a string for undici.request
          body: new URLSearchParams({ To: phone, From: from, Body: text }).toString(),
        }
      );

      if (res.statusCode >= 400) {
        error(`Twilio ${res.statusCode}: ${(await res.body.text()).slice(0, 200)}`);
        return { sent: false, channel: 'twilio' };
      }

      // Consume the successful body to free memory
      await res.body.text().catch(() => {});
      return { sent: true, channel: 'twilio' };
    } catch (e) {
      error(`Twilio send failed: ${e.message}`);
      return { sent: false, channel: 'twilio' };
    }
  }

  if (String(process.env.OTP_DEV_MODE) === 'true') {
    // Explicitly opted into. The code goes to the function log and comes back
    // in the response so a shop can try the flow without an SMS account.
    log(`[DEV] OTP for ${phone}: ${code}`);
    return { sent: true, channel: 'log' };
  }

  error('No SMS provider configured (set SMS_PROVIDER=twilio, or OTP_DEV_MODE=true for piloting)');
  return { sent: false, channel: 'none' };
}
