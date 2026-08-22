// Appwrite Function — the only writer of an appointment's paid state.
//
// Trigger:   Stripe webhook (HTTP POST from Stripe, execute("any"))
// Runtime:   node-22
// Env vars:  STRIPE_SECRET_KEY      sk_...
//            STRIPE_WEBHOOK_SECRET  whsec_... from the Stripe dashboard
//            APPWRITE_API_KEY       server key (appointments is staff-only)
//            APPWRITE_FUNCTION_API_ENDPOINT / APPWRITE_FUNCTION_PROJECT_ID
//            APPWRITE_INSECURE_TLS  "true" only for self-signed self-hosting
//
// WHY: the app used to set `paid: true` itself, on a world-writable row, with
// nothing checking that money had moved. Anyone could mark any booking paid,
// and a customer whose card genuinely failed after the sheet closed still got
// a paid badge. Payment state now comes from exactly one place — Stripe,
// signature-verified — and the client can only ask what the state is.
//
// Configure in Stripe → Developers → Webhooks, pointing at this function's
// URL, subscribed to:
//   payment_intent.succeeded, payment_intent.payment_failed,
//   charge.refunded, charge.dispute.created

import Stripe from 'stripe';

const DB_ID = process.env.APPWRITE_DATABASE_ID || 'barber_db';
const T_APPOINTMENTS = 'appointments';

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

async function appwrite(method, path, body) {
  const init = {
    method,
    headers: {
      'X-Appwrite-Project': process.env.APPWRITE_FUNCTION_PROJECT_ID,
      'X-Appwrite-Key': process.env.APPWRITE_API_KEY,
      'Content-Type': 'application/json',
    },
  };
  if (body !== undefined) init.body = JSON.stringify(body);
  const d = await insecureDispatcher();
  if (d) init.dispatcher = d;

  // Node 16 (this server's Appwrite runtime pin) has no global fetch. undici's
  // request() also doesn't follow redirects, which matters because Appwrite
  // injects APPWRITE_FUNCTION_API_ENDPOINT as http:// and the self-hosted
  // proxy 301s that to https — hence the scheme rewrite below.
  const endpoint = (process.env.APPWRITE_FUNCTION_API_ENDPOINT || 'https://cloud.appwrite.io/v1')
    .replace(/\/+$/, '')
    .replace(/^http:\/\//, 'https://');
  const { request } = await import('undici');
  const r = await request(`${endpoint}/tablesdb/${DB_ID}${path}`, init);
  const text = await r.body.text();
  if (r.statusCode >= 400) {
    throw new Error(`Appwrite ${r.statusCode}: ${text.slice(0, 200)}`);
  }
  return text ? JSON.parse(text) : null;
}

const getRow = (id) =>
  appwrite('GET', `/tables/${T_APPOINTMENTS}/rows/${encodeURIComponent(id)}`).catch(() => null);

const patchRow = (id, data) =>
  appwrite('PATCH', `/tables/${T_APPOINTMENTS}/rows/${encodeURIComponent(id)}`, { data });

async function findByIntent(intentId) {
  const q = encodeURIComponent(JSON.stringify({
    method: 'equal', attribute: 'payment_intent_id', values: [intentId],
  }));
  const out = await appwrite('GET', `/tables/${T_APPOINTMENTS}/rows?queries[]=${q}`)
    .catch(() => null);
  return out?.rows?.[0] ?? null;
}

/**
 * Resolve the booking an event belongs to. Metadata first (set when the intent
 * was minted), then the stored intent id — either alone is enough, and having
 * both paths means a row that was written slightly late is still reconcilable.
 */
async function resolveAppointment(intent) {
  const fromMetadata = intent?.metadata?.appointmentId;
  if (fromMetadata) {
    const row = await getRow(fromMetadata);
    if (row) return row;
  }
  if (intent?.id) return findByIntent(intent.id);
  return null;
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
  const webhookSecret = process.env.STRIPE_WEBHOOK_SECRET;
  if (!secret || !webhookSecret) {
    error('STRIPE_SECRET_KEY / STRIPE_WEBHOOK_SECRET not set');
    return res.json({ error: 'not configured' }, 500);
  }
  if (!process.env.APPWRITE_API_KEY) {
    error('APPWRITE_API_KEY not set');
    return res.json({ error: 'not configured' }, 500);
  }

  const stripe = new Stripe(secret, { apiVersion: '2024-06-20' });

  // Signature verification needs the bytes exactly as Stripe sent them — a
  // parsed-and-restringified body will not verify. Appwrite's runtime has
  // moved this property around across versions, hence the ladder.
  const raw = req.bodyBinary ?? req.bodyRaw ?? req.bodyText ?? req.body;
  const signature = req.headers?.['stripe-signature'];
  if (!signature) {
    error('Missing stripe-signature header');
    return res.json({ error: 'unsigned' }, 400);
  }

  let event;
  try {
    event = stripe.webhooks.constructEvent(
      Buffer.isBuffer(raw) ? raw : Buffer.from(String(raw ?? ''), 'utf8'),
      signature,
      webhookSecret,
    );
  } catch (e) {
    // An unverified payload is an attacker or a misconfiguration; either way
    // it must never reach the database.
    error(`Signature verification failed: ${e.message}`);
    return res.json({ error: 'invalid signature' }, 400);
  }

  try {
    switch (event.type) {
      case 'payment_intent.succeeded': {
        const intent = event.data.object;
        const appt = await resolveAppointment(intent);
        if (!appt) {
          error(`No appointment for PaymentIntent ${intent.id}`);
          break; // still 200 — retrying will not conjure the row
        }
        if (appt.paid && appt.payment_amount_cents === intent.amount_received) {
          log(`PaymentIntent ${intent.id} already applied to ${appt.$id}`);
          break; // Stripe retries; applying twice must be harmless
        }
        await patchRow(appt.$id, {
          paid: true,
          payment_amount_cents: intent.amount_received,
          payment_intent_id: intent.id,
        });
        log(`Marked ${appt.$id} paid: ${intent.amount_received} cents (${intent.id})`);
        break;
      }

      case 'payment_intent.payment_failed': {
        const intent = event.data.object;
        log(`Payment failed for ${intent.metadata?.appointmentId ?? intent.id}: `
          + `${intent.last_payment_error?.message ?? 'unknown reason'}`);
        // Nothing to undo: the row was never marked paid in the first place.
        break;
      }

      case 'charge.refunded': {
        const charge = event.data.object;
        const intentId = typeof charge.payment_intent === 'string'
          ? charge.payment_intent
          : charge.payment_intent?.id;
        const appt = intentId ? await findByIntent(intentId) : null;
        if (!appt) {
          error(`No appointment for refunded charge ${charge.id}`);
          break;
        }
        const outstanding = charge.amount - charge.amount_refunded;
        await patchRow(appt.$id, {
          // A partial refund still leaves money paid; only a full one clears
          // the badge.
          paid: outstanding > 0,
          payment_amount_cents: Math.max(0, outstanding),
        });
        log(`Refund on ${appt.$id}: ${charge.amount_refunded} of ${charge.amount} cents`);
        break;
      }

      case 'charge.dispute.created': {
        // Money is at risk but not yet gone. Surfacing it in the logs is the
        // honest minimum; the shop settles it in the Stripe dashboard.
        const dispute = event.data.object;
        error(`DISPUTE opened on charge ${dispute.charge} for ${dispute.amount} cents`);
        break;
      }

      default:
        log(`Ignoring ${event.type}`);
    }
  } catch (e) {
    // A 500 makes Stripe retry, which is what we want for a transient
    // Appwrite failure.
    error(`Handling ${event.type} failed: ${e.message}`);
    return res.json({ error: 'processing failed' }, 500);
  }

  return res.json({ received: true });
};
