// Appwrite Function — mints a Stripe PaymentIntent for a booking.
//
// Trigger:   HTTP execution from the Flutter client.
// Runtime:   node-22
// Env vars:  STRIPE_SECRET_KEY   the Stripe secret/restricted key (sk_...)
//            APPWRITE_API_KEY    server key — the appointments table is
//                                staff-only now, so anonymous reads are gone
//            APPWRITE_FUNCTION_API_ENDPOINT / APPWRITE_FUNCTION_PROJECT_ID
//            APPWRITE_INSECURE_TLS  "true" only for self-signed self-hosting
//
// Request body (JSON):
//   { "appointmentId": "<row-id>", "token": "<manage token>" }
//
// Response body (JSON):
//   { "clientSecret": "...", "paymentIntentId": "pi_...",
//     "amount": 2500, "currency": "eur" }
//
// SECURITY:
//   * The amount is resolved here, from the services table, minus any loyalty
//     discount already recorded on the booking. The client never sends an
//     amount and one sent anyway is ignored.
//   * The caller must present the booking's manage token. Without it, anyone
//     could mint intents against other people's bookings and learn what they
//     are paying.
//   * Minting an intent does NOT mark anything paid. Only the stripe-webhook
//     function writes `paid`, and only after Stripe says the money arrived.
//     That asymmetry is the point: a client that lies about having paid gets
//     nowhere, because it is not the one being asked.

import { createHash, timingSafeEqual } from 'node:crypto';
import Stripe from 'stripe';

const DB_ID = process.env.APPWRITE_DATABASE_ID || 'barber_db';
const T_APPOINTMENTS = 'appointments';
const T_SERVICES = 'services';
const MIN_CHARGE_CENTS = 50; // Stripe's EUR minimum (€0.50)

let dispatcher;
async function insecureDispatcher() {
  if (dispatcher !== undefined) return dispatcher;
  if (String(process.env.APPWRITE_INSECURE_TLS) !== 'true') {
    dispatcher = null;
    return dispatcher;
  }
  const { Agent } = await import('undici');
  dispatcher = new Agent({ connect: { rejectUnauthorized: false } });
  return dispatcher;
}

async function appwrite(method, path, { endpoint, projectId, apiKey }, body) {
  const init = {
    method,
    headers: {
      'X-Appwrite-Project': projectId,
      'X-Appwrite-Key': apiKey,
      'Content-Type': 'application/json',
    },
  };
  if (body !== undefined) init.body = JSON.stringify(body);
  const d = await insecureDispatcher();
  if (d) init.dispatcher = d;

  // Node 16 (this server's Appwrite runtime pin) has no global fetch. undici's
  // request() also doesn't follow redirects, which matters because Appwrite
  // injects APPWRITE_FUNCTION_API_ENDPOINT as http:// and the self-hosted
  // proxy 301s that to https — hence the scheme rewrite in cfg.endpoint below.
  const { request } = await import('undici');
  const r = await request(`${endpoint}/tablesdb/${DB_ID}${path}`, init);
  if (r.statusCode >= 400) return null;
  const text = await r.body.text();
  return text ? JSON.parse(text) : null;
}

const readRow = (cfg, table, id) =>
  appwrite('GET', `/tables/${table}/rows/${encodeURIComponent(id)}`, cfg);

const patchRow = (cfg, table, id, data) =>
  appwrite('PATCH', `/tables/${table}/rows/${encodeURIComponent(id)}`, cfg, { data });

function hashToken(t) {
  return createHash('sha256').update(String(t)).digest('hex');
}

function hashesEqual(a, b) {
  const ba = Buffer.from(String(a ?? ''), 'utf8');
  const bb = Buffer.from(String(b ?? ''), 'utf8');
  if (ba.length !== bb.length || ba.length === 0) return false;
  return timingSafeEqual(ba, bb);
}

export default async ({ req, res, log, error }) => {
  // Appwrite's function sandbox doesn't expose Web Streams globally, which
  // both the global fetch() below and the stripe package's own HTTP client
  // need the first time they touch undici's fetch internals.
  if (!globalThis.ReadableStream) {
    const webStreams = await import('node:stream/web');
    Object.assign(globalThis, webStreams);
  }

  const secret = process.env.STRIPE_SECRET_KEY;
  if (!secret) {
    error('STRIPE_SECRET_KEY env var is not set on the function');
    return res.json({ error: 'Server payment configuration missing.' }, 500);
  }
  const apiKey = process.env.APPWRITE_API_KEY;
  if (!apiKey) {
    error('APPWRITE_API_KEY env var is not set on the function');
    return res.json({ error: 'Server payment configuration missing.' }, 500);
  }

  const cfg = {
    endpoint: (process.env.APPWRITE_FUNCTION_API_ENDPOINT || 'https://cloud.appwrite.io/v1')
      .replace(/\/+$/, '')
      .replace(/^http:\/\//, 'https://'),
    projectId: process.env.APPWRITE_FUNCTION_PROJECT_ID,
    apiKey,
  };

  let body = {};
  try {
    body = req.bodyJson ?? (req.body ? JSON.parse(req.body) : {});
  } catch {
    return res.json({ error: 'Body must be JSON.' }, 400);
  }

  const appointmentId = typeof body.appointmentId === 'string' ? body.appointmentId : '';
  const token = typeof body.token === 'string' ? body.token : '';
  if (!appointmentId) return res.json({ error: 'appointmentId is required.' }, 400);

  const appt = await readRow(cfg, T_APPOINTMENTS, appointmentId);
  // One answer for "no such booking" and "not yours", so this cannot be used
  // to discover which booking ids exist.
  if (!appt || !appt.manage_token_hash || !hashesEqual(appt.manage_token_hash, hashToken(token))) {
    error(`Rejected intent request for ${appointmentId}: bad or missing manage token`);
    return res.json({ error: 'Appointment not found.' }, 404);
  }

  if (appt.status === 'cancelled') {
    return res.json({ error: 'Dieser Termin wurde storniert.' }, 409);
  }
  if (appt.paid) {
    return res.json({ error: 'Dieser Termin ist bereits bezahlt.' }, 409);
  }

  const svc = await readRow(cfg, T_SERVICES, appt.service_id);
  if (!svc || typeof svc.price_cents !== 'number') {
    error(`Service ${appt.service_id} not found or missing price_cents`);
    return res.json({ error: 'Service price unavailable.' }, 404);
  }

  // A redeemed loyalty reward is a real discount, so honour it here rather
  // than charging full price and refunding later.
  const discount = Number(appt.discount_cents ?? 0);
  const amount = Math.max(0, svc.price_cents - discount);
  if (amount === 0) {
    return res.json({ error: 'Für diesen Termin ist nichts zu zahlen.' }, 409);
  }
  if (amount < MIN_CHARGE_CENTS) {
    error(`Refusing to charge ${amount} cents (< ${MIN_CHARGE_CENTS}).`);
    return res.json({ error: 'Amount below the payable minimum.' }, 400);
  }

  try {
    const stripe = new Stripe(secret, { apiVersion: '2024-06-20' });

    // Idempotency: a customer who backs out of the sheet and taps pay again
    // should land on the same intent, not litter the dashboard with abandoned
    // ones. Reuse only while the intent is still payable and still for the
    // right amount.
    if (appt.payment_intent_id) {
      const existing = await stripe.paymentIntents.retrieve(appt.payment_intent_id)
        .catch(() => null);
      const reusable = existing
        && existing.amount === amount
        && ['requires_payment_method', 'requires_confirmation', 'requires_action']
          .includes(existing.status);
      if (reusable) {
        log(`Reusing PaymentIntent ${existing.id} for ${appointmentId}`);
        return res.json({
          clientSecret: existing.client_secret,
          paymentIntentId: existing.id,
          amount: existing.amount,
          currency: existing.currency,
        });
      }
    }

    const intent = await stripe.paymentIntents.create({
      amount,
      currency: 'eur',
      automatic_payment_methods: { enabled: true },
      description: `${svc.name || 'Termin'} – ${process.env.SHOP_NAME || "BaBa'Ssam"}`,
      // The webhook finds its way back to the row through this.
      metadata: { appointmentId, serviceId: appt.service_id },
    }, {
      // Stripe-side replay protection for this booking + amount.
      idempotencyKey: `appt_${appointmentId}_${amount}`,
    });

    // Store the handle before returning: if the customer pays and the webhook
    // arrives before we finish, it can still match on metadata, but having the
    // id on the row is what makes reconciliation possible afterwards.
    await patchRow(cfg, T_APPOINTMENTS, appointmentId, { payment_intent_id: intent.id });

    log(`PaymentIntent ${intent.id} created for ${amount} cents (service ${appt.service_id})`);
    return res.json({
      clientSecret: intent.client_secret,
      paymentIntentId: intent.id,
      amount,
      currency: 'eur',
    });
  } catch (e) {
    error(`Stripe error: ${e.message}`);
    return res.json({ error: 'Zahlung konnte nicht gestartet werden.' }, 500);
  }
};
