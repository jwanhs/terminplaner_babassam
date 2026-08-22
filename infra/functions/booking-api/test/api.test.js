// End-to-end tests for the booking API's access-control rules.
//
// These are the regression tests for the holes that made the old design
// unshippable: world-readable appointments, anyone able to cancel anyone's
// booking, client-set prices and paid flags, free rewards on request, and two
// customers landing in the same chair.

import { test } from 'node:test';
import assert from 'node:assert/strict';

import { handle } from '../src/main.js';
import { FakeDb, fakeRes } from './fake-db.js';

// The day before the fixture day, so bookings sit outside the 12-hour
// cancellation cutoff and the self-service paths are exercisable.
const NOW = Date.parse('2026-08-20T03:00:00Z'); // Thursday, CEST
const SLOT = '2026-08-21T08:00:00.000Z';        // Friday 10:00 local

function seed() {
  return new FakeDb({
    services: [
      { $id: 'cut', name: 'Haarschnitt', duration_minutes: 30, price_cents: 2500, display_order: 1, active: true },
      { $id: 'beard', name: 'Bart', duration_minutes: 60, price_cents: 1500, display_order: 2, active: true },
    ],
    business_hours: [
      { $id: 'h4', weekday: 4, open_time: '09:00', close_time: '17:00', slot_minutes: 30, closed: false },
    ],
    shop_settings: [
      {
        $id: 'default',
        timezone: 'Europe/Berlin',
        buffer_minutes: 0,
        lead_time_minutes: 30,
        cancel_cutoff_hours: 12,
        max_advance_days: 30,
        max_open_per_phone: 3,
      },
    ],
    appointments: [],
    closures: [],
  });
}

// Every call runs at a fixed instant, so the suite behaves the same today as
// it will next spring — a booking test that silently starts passing for the
// wrong reason once its fixture date goes past is worse than no test.
async function call(db, body, headers = {}) {
  const { res, out } = fakeRes();
  await handle({
    req: { bodyJson: body, headers },
    res,
    log: () => {},
    error: () => {},
    db,
    nowMs: NOW,
  });
  return out;
}

async function book(db, overrides = {}) {
  return call(db, {
    action: 'create',
    serviceId: 'cut',
    start: SLOT,
    name: 'Sami',
    phone: '0176 1234567',
    ...overrides,
  });
}

// --- booking -----------------------------------------------------------------

test('a valid booking succeeds and returns a manage token exactly once', async () => {
  const db = seed();
  const out = await book(db);
  assert.equal(out.status, 200);
  assert.equal(out.body.ok, true);
  assert.match(out.body.manageToken, /^[A-Za-z0-9_-]{43}$/);
  assert.equal(out.body.appointment.startLabel, '10:00');
  assert.equal(out.body.appointment.paid, false);

  // The token's hash is stored; the token itself is not, and never comes back.
  const row = [...db.tables.appointments.values()][0];
  assert.ok(row.manage_token_hash);
  assert.ok(!JSON.stringify(row).includes(out.body.manageToken));
  assert.equal(out.body.appointment.manage_token_hash, undefined);
});

test('the phone number is normalised on the way in', async () => {
  const db = seed();
  await book(db, { phone: '0176 1234567' });
  const row = [...db.tables.appointments.values()][0];
  assert.equal(row.customer_phone, '+491761234567');
});

test('two bookings of the same slot cannot both land', async () => {
  const db = seed();
  const first = await book(db);
  const second = await book(db, { name: 'Alex', phone: '0176 7654321' });

  assert.equal(first.body.ok, true);
  assert.equal(second.status, 409);
  assert.equal(second.body.error, 'slot_taken');

  const live = [...db.tables.appointments.values()].filter((a) => a.status !== 'cancelled');
  assert.equal(live.length, 1);
});

test('an overlapping booking at a different start is also refused', async () => {
  const db = seed();
  await book(db, { serviceId: 'beard' }); // 60 minutes from 10:00
  const overlap = await book(db, {
    serviceId: 'cut',
    start: '2026-08-21T08:30:00.000Z', // 10:30, inside the beard trim
    name: 'Alex',
    phone: '0176 7654321',
  });
  assert.equal(overlap.status, 409);
});

test('the client cannot dictate price, paid state or duration', async () => {
  const db = seed();
  const out = await book(db, {
    priceCents: 1,
    paid: true,
    payment_amount_cents: 1,
    discount_cents: 2500,
    duration_minutes: 5,
    status: 'completed',
    end: '2026-08-21T08:05:00.000Z',
  });
  assert.equal(out.body.ok, true);

  const row = [...db.tables.appointments.values()][0];
  assert.equal(row.paid, false);
  assert.equal(row.payment_amount_cents, 0);
  assert.equal(row.discount_cents, 0);
  assert.equal(row.status, 'confirmed');
  // Duration came from the service, not the request.
  assert.equal(Date.parse(row.end_at) - Date.parse(row.start_at), 30 * 60000);
});

test('a slot the grid never offered is refused', async () => {
  const db = seed();
  const out = await book(db, { start: '2026-08-21T08:07:00.000Z' }); // 10:07
  assert.equal(out.status, 409);
});

test('a booking outside opening hours is refused', async () => {
  const db = seed();
  const out = await book(db, { start: '2026-08-21T20:00:00.000Z' }); // 22:00
  assert.equal(out.status, 409);
});

test('a booking beyond the advance window is refused', async () => {
  const db = seed();
  const out = await book(db, { start: '2026-11-20T08:00:00.000Z' });
  assert.equal(out.status, 409);
});

test('missing or bogus contact details are refused', async () => {
  const db = seed();
  assert.equal((await book(db, { name: 'x' })).status, 400);
  assert.equal((await book(db, { phone: '123' })).status, 400);
  assert.equal((await book(db, { serviceId: 'nope' })).status, 404);
});

test('one number cannot hold unlimited open bookings', async () => {
  const db = seed();
  const starts = [
    '2026-08-21T08:00:00.000Z',
    '2026-08-21T09:00:00.000Z',
    '2026-08-21T10:00:00.000Z',
    '2026-08-21T11:00:00.000Z',
  ];
  const results = [];
  for (const start of starts) results.push(await book(db, { start }));
  assert.deepEqual(results.map((r) => r.status), [200, 200, 200, 409]);
  assert.equal(results[3].body.error, 'too_many_open');
});

// --- ownership ---------------------------------------------------------------

test('a stranger cannot cancel someone else’s booking', async () => {
  const db = seed();
  const booked = await book(db);
  const id = booked.body.appointment.id;

  // No token at all.
  assert.equal((await call(db, { action: 'cancel', appointmentId: id })).status, 404);
  // A wrong token.
  assert.equal(
    (await call(db, { action: 'cancel', appointmentId: id, token: 'not-the-token' })).status,
    404,
  );
  // Still confirmed.
  assert.equal(db.tables.appointments.get(id).status, 'confirmed');
});

test('the manage token cancels, and frees the slot for the next customer', async () => {
  const db = seed();
  const booked = await book(db);
  const { id } = booked.body.appointment;

  const out = await call(db, {
    action: 'cancel', appointmentId: id, token: booked.body.manageToken,
  });
  assert.equal(out.body.ok, true);
  assert.equal(out.body.appointment.status, 'cancelled');

  // The freed slot is bookable again — the unique key was released.
  const next = await book(db, { name: 'Alex', phone: '0176 7654321' });
  assert.equal(next.body.ok, true);
});

test('an unknown appointment and an unowned one are indistinguishable', async () => {
  const db = seed();
  const booked = await book(db);
  const real = await call(db, { action: 'cancel', appointmentId: booked.body.appointment.id, token: 'wrong' });
  const fake = await call(db, { action: 'cancel', appointmentId: 'does-not-exist', token: 'wrong' });
  assert.equal(real.status, fake.status);
  assert.deepEqual(real.body, fake.body);
});

test('lookup returns only bookings the caller can prove are theirs', async () => {
  const db = seed();
  const mine = await book(db);
  await book(db, {
    start: '2026-08-21T09:00:00.000Z', name: 'Someone Else', phone: '0176 9999999',
  });

  const out = await call(db, { action: 'my', tokens: [mine.body.manageToken] });
  assert.equal(out.body.ok, true);
  assert.equal(out.body.appointments.length, 1);
  assert.equal(out.body.appointments[0].customerName, 'Sami');
});

test('lookup with no proof returns nothing at all', async () => {
  const db = seed();
  await book(db);
  const out = await call(db, { action: 'my', tokens: [] });
  assert.equal(out.body.appointments.length, 0);
});

test('a phone number alone no longer reveals a history', async () => {
  const db = seed();
  await book(db);
  // The old API took a phone number and answered. There is now no action that
  // accepts one without a verified session.
  const out = await call(db, { action: 'my', phone: '+491761234567' });
  assert.equal(out.body.appointments.length, 0);
});

test('an OTP session unlocks exactly one number’s bookings', async () => {
  const db = seed();
  process.env.OTP_DEV_MODE = 'true';
  try {
    const mine = await book(db);
    await book(db, {
      start: '2026-08-21T09:00:00.000Z', name: 'Someone Else', phone: '0176 9999999',
    });

    const req = await call(db, { action: 'otp_request', phone: '0176 1234567' });
    assert.equal(req.body.ok, true);
    const verify = await call(db, {
      action: 'otp_verify', phone: '0176 1234567', code: req.body.devCode,
    });
    assert.equal(verify.body.ok, true);

    const out = await call(db, { action: 'my', session: verify.body.session });
    assert.equal(out.body.appointments.length, 1);
    assert.equal(out.body.verifiedPhone, '+491761234567');
    assert.equal(out.body.appointments[0].id, mine.body.appointment.id);
  } finally {
    delete process.env.OTP_DEV_MODE;
  }
});

test('a wrong OTP is refused and a forged session is worthless', async () => {
  const db = seed();
  process.env.OTP_DEV_MODE = 'true';
  try {
    await book(db);
    await call(db, { action: 'otp_request', phone: '0176 1234567' });
    const bad = await call(db, { action: 'otp_verify', phone: '0176 1234567', code: '000000' });
    assert.equal(bad.status, 401);

    const forged = await call(db, { action: 'my', session: 'made-up-session' });
    assert.equal(forged.status, 401);
  } finally {
    delete process.env.OTP_DEV_MODE;
  }
});

test('OTP delivery is refused when no provider is configured', async () => {
  const db = seed();
  const out = await call(db, { action: 'otp_request', phone: '0176 1234567' });
  assert.equal(out.status, 503);
  assert.equal(out.body.devCode, undefined);
});

// --- rescheduling ------------------------------------------------------------

test('rescheduling with the token moves the booking and keeps the slot unique', async () => {
  const db = seed();
  const booked = await book(db);
  const out = await call(db, {
    action: 'reschedule',
    appointmentId: booked.body.appointment.id,
    token: booked.body.manageToken,
    start: '2026-08-21T09:00:00.000Z', // 11:00 local
  });
  assert.equal(out.body.ok, true);
  assert.equal(out.body.appointment.startLabel, '11:00');

  // The vacated 10:00 is available again.
  const next = await book(db, { name: 'Alex', phone: '0176 7654321' });
  assert.equal(next.body.ok, true);
});

test('rescheduling onto a taken slot is refused', async () => {
  const db = seed();
  const a = await book(db);
  await book(db, {
    start: '2026-08-21T09:00:00.000Z', name: 'Alex', phone: '0176 7654321',
  });
  const out = await call(db, {
    action: 'reschedule',
    appointmentId: a.body.appointment.id,
    token: a.body.manageToken,
    start: '2026-08-21T09:00:00.000Z',
  });
  assert.equal(out.status, 409);
});

test('the cancellation cutoff applies to customers', async () => {
  const db = seed();
  const booked = await book(db);
  const id = booked.body.appointment.id;
  // Move the booking to two hours from now, inside the 12-hour cutoff.
  await db.updateRow('appointments', id, {
    start_at: new Date(NOW + 2 * 3600000).toISOString(),
    end_at: new Date(NOW + 2.5 * 3600000).toISOString(),
  });
  const out = await call(db, {
    action: 'cancel', appointmentId: id, token: booked.body.manageToken,
  });
  assert.equal(out.status, 409);
  assert.equal(out.body.error, 'too_late');
});

// --- loyalty -----------------------------------------------------------------

test('a reward cannot be claimed without the visits behind it', async () => {
  const db = seed();
  const booked = await book(db);
  const out = await call(db, {
    action: 'redeem', appointmentId: booked.body.appointment.id, token: booked.body.manageToken,
  });
  assert.equal(out.status, 409);
  assert.equal(out.body.error, 'no_reward');
  assert.equal(db.tables.appointments.get(booked.body.appointment.id).discount_cents, 0);
});

test('a full card redeems for the service’s real price, not a client-sent one', async () => {
  const db = seed();
  const booked = await book(db);
  const phone = '+491761234567';
  // Ten past visits for the same number.
  for (let i = 1; i <= 10; i++) {
    await db.createRow('appointments', `past${i}`, {
      customer_phone: phone,
      service_id: 'cut',
      service_name: 'Haarschnitt',
      start_at: new Date(NOW - i * 7 * 86400000).toISOString(),
      end_at: new Date(NOW - i * 7 * 86400000 + 1800000).toISOString(),
      status: 'completed',
      discount_cents: 0,
      slot_key: `past|${i}`,
    });
  }

  const out = await call(db, {
    action: 'redeem',
    appointmentId: booked.body.appointment.id,
    token: booked.body.manageToken,
    discountCents: 999999, // ignored
  });
  assert.equal(out.body.ok, true);
  assert.equal(out.body.appointment.discountCents, 2500); // the service price
  assert.equal(out.body.loyalty.rewardsAvailable, 0);

  // A second attempt on the same booking is refused.
  const again = await call(db, {
    action: 'redeem', appointmentId: booked.body.appointment.id, token: booked.body.manageToken,
  });
  assert.equal(again.status, 409);
});

// --- shaping -----------------------------------------------------------------

test('availability leaks times only, never who holds them', async () => {
  const db = seed();
  await book(db);
  const out = await call(db, { action: 'availability', serviceId: 'cut', date: '2026-08-21' });
  assert.equal(out.body.ok, true);

  const serialised = JSON.stringify(out.body);
  assert.ok(!serialised.includes('Sami'));
  assert.ok(!serialised.includes('1761234567'));
  for (const slot of out.body.slots) {
    assert.deepEqual(Object.keys(slot).sort(), ['end', 'label', 'start']);
  }
  // The booked 10:00 is simply absent.
  assert.ok(!out.body.slots.some((s) => s.label === '10:00'));
});

test('the catalog exposes prices but no internal fields', async () => {
  const db = seed();
  const out = await call(db, { action: 'catalog' });
  assert.equal(out.body.services.length, 2);
  assert.equal(out.body.services[0].priceCents, 2500);
  assert.equal(out.body.settings.timezone, 'Europe/Berlin');
});

test('an unknown action is rejected rather than falling through', async () => {
  const db = seed();
  const out = await call(db, { action: 'drop_everything' });
  assert.equal(out.status, 400);
  assert.equal(out.body.error, 'unknown_action');
});

test('a malformed body does not crash the function', async () => {
  const db = seed();
  const { res, out } = fakeRes();
  await handle({
    req: { body: '{not json', headers: {} },
    res, log: () => {}, error: () => {}, db,
  });
  assert.equal(out.status, 400);
});

// --- more than one chair -----------------------------------------------------
//
// Availability assumed a single chair, which meant the product could only be
// sold to solo operators. These cover the paths where that assumption used to
// be baked in: how many people can hold one time, which chair they land on,
// and what a customer is allowed to learn about the shop's occupancy.

function seedChairs() {
  const db = seed();
  db.tables.resources = new Map([
    ['chair-1', { $id: 'chair-1', name: 'Stuhl 1', display_order: 1, active: true }],
    ['chair-2', { $id: 'chair-2', name: 'Stuhl 2', display_order: 2, active: true }],
    ['chair-3', { $id: 'chair-3', name: 'Stuhl 3', display_order: 3, active: true }],
  ]);
  return db;
}

const CUSTOMERS = [
  { name: 'Sami', phone: '0176 1111111' },
  { name: 'Jonas', phone: '0176 2222222' },
  { name: 'Mert', phone: '0176 3333333' },
  { name: 'Lukas', phone: '0176 4444444' },
];

test('a three-chair shop takes three bookings at one time', async () => {
  const db = seedChairs();

  for (const who of CUSTOMERS.slice(0, 3)) {
    const out = await book(db, who);
    assert.equal(out.body.ok, true, `${who.name} should get a chair`);
  }

  const fourth = await book(db, CUSTOMERS[3]);
  assert.equal(fourth.body.ok, false);
  assert.equal(fourth.body.error, 'slot_taken');
});

test('chairs are filled in the shop\'s own order', async () => {
  const db = seedChairs();
  for (const who of CUSTOMERS.slice(0, 3)) await book(db, who);

  const rows = await db.listRows('appointments', []);
  const assigned = rows
    .sort((a, b) => a.customer_name.localeCompare(b.customer_name))
    .map((r) => [r.customer_name, r.resource_id]);

  // Jonas, Mert, Sami alphabetically — booked in the order Sami, Jonas, Mert.
  assert.deepEqual(assigned.sort(), [
    ['Jonas', 'chair-2'],
    ['Mert', 'chair-3'],
    ['Sami', 'chair-1'],
  ].sort());
});

test('every chair gets its own slot key, so the index still stops doubles', async () => {
  const db = seedChairs();
  for (const who of CUSTOMERS.slice(0, 3)) await book(db, who);

  const rows = await db.listRows('appointments', []);
  const keys = rows.map((r) => r.slot_key);
  assert.equal(new Set(keys).size, 3, 'three distinct keys for one instant');
  for (const key of keys) assert.ok(key.endsWith(`|${SLOT}`));
});

test('a customer still cannot see how busy the shop is', async () => {
  const db = seedChairs();
  await book(db, CUSTOMERS[0]);

  const out = await call(db, {
    action: 'availability', serviceId: 'cut', date: '2026-08-21',
  });

  // 10:00 is still on sale — but nothing says two of three chairs are free.
  const ten = out.body.slots.find((s) => s.label === '10:00');
  assert.ok(ten);
  for (const slot of out.body.slots) {
    assert.deepEqual(Object.keys(slot).sort(), ['end', 'label', 'start']);
  }
  assert.ok(!JSON.stringify(out.body).includes('chair-'));
});

test('the last chair at a time is the last booking taken', async () => {
  const db = seedChairs();
  for (const who of CUSTOMERS.slice(0, 3)) await book(db, who);

  const out = await call(db, {
    action: 'availability', serviceId: 'cut', date: '2026-08-21',
  });
  assert.ok(!out.body.slots.some((s) => s.label === '10:00'),
    '10:00 is gone once every chair is taken');
});

test('rescheduling keeps the customer on their own chair when it is free', async () => {
  const db = seedChairs();
  const first = await book(db, CUSTOMERS[0]);
  const token = first.body.manageToken;
  const id = first.body.appointment.id;

  const before = (await db.listRows('appointments', []))
    .find((r) => r.$id === id).resource_id;

  const moved = await call(db, {
    action: 'reschedule',
    appointmentId: id,
    token,
    start: '2026-08-21T08:30:00.000Z', // 10:30 local
  });
  assert.equal(moved.body.ok, true);

  const after = (await db.listRows('appointments', []))
    .find((r) => r.$id === id).resource_id;
  assert.equal(after, before, 'same barber, different time');
});

test('a one-chair shop is unchanged by any of this', async () => {
  // No resources rows at all — the shape every existing deployment is in.
  const db = seed();
  const first = await book(db, CUSTOMERS[0]);
  assert.equal(first.body.ok, true);

  const second = await book(db, CUSTOMERS[1]);
  assert.equal(second.body.ok, false);
  assert.equal(second.body.error, 'slot_taken');

  const rows = await db.listRows('appointments', []);
  assert.equal(rows[0].slot_key, `shop|${SLOT}`,
    'the implicit chair every existing row already names');
});
