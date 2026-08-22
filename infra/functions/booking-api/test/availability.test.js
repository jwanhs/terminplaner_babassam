import { test } from 'node:test';
import assert from 'node:assert/strict';

import {
  computeSlots, validateSlot, slotKeyFor, pickResource, SOLO_RESOURCE,
} from '../src/availability.js';

const TZ = 'Europe/Berlin';

// A Friday well inside CEST. "now" is the small hours so lead time never
// interferes unless a test asks it to.
const DAY = '2026-08-21';
const NOW = Date.parse('2026-08-21T03:00:00Z');

const HOURS = {
  weekday: 4,
  open_time: '09:00',
  close_time: '17:00',
  slot_minutes: 30,
  closed: false,
};

const SETTINGS = {
  buffer_minutes: 0,
  lead_time_minutes: 30,
  max_advance_days: 30,
};

function labels(slots) {
  return slots.map((s) => s.label);
}

function run(overrides = {}) {
  return computeSlots({
    dateKey: DAY,
    timezone: TZ,
    hours: HOURS,
    appointments: [],
    closures: [],
    durationMinutes: 30,
    settings: SETTINGS,
    nowMs: NOW,
    ...overrides,
  });
}

test('a plain day yields every slot from open to close', () => {
  const slots = run();
  assert.equal(slots[0].label, '09:00');
  assert.equal(slots.at(-1).label, '16:30'); // 30-min service must end by 17:00
  assert.equal(slots.length, 16);
});

test('slot instants are the shop wall clock, not UTC', () => {
  const slots = run();
  // 09:00 Berlin in August is 07:00Z. Getting this wrong is the timezone bug.
  assert.equal(slots[0].start, '2026-08-21T07:00:00.000Z');
});

test('a longer service needs room before closing', () => {
  const slots = run({ durationMinutes: 90 });
  assert.equal(slots.at(-1).label, '15:30');
});

test('closed days offer nothing', () => {
  assert.deepEqual(run({ hours: { ...HOURS, closed: true } }), []);
  assert.deepEqual(run({ hours: undefined }), []);
});

test('a booked appointment removes exactly the slots it covers', () => {
  const slots = run({
    appointments: [{
      startAt: '2026-08-21T08:00:00Z', // 10:00 local
      endAt: '2026-08-21T09:00:00Z',   // 11:00 local
    }],
  });
  const got = labels(slots);
  assert.ok(!got.includes('10:00'));
  assert.ok(!got.includes('10:30'));
  assert.ok(got.includes('09:30'));
  assert.ok(got.includes('11:00'));
});

test('a 30-minute service cannot start where it would run into a booking', () => {
  // Booking 10:00–11:00 local. A 30-min slot at 09:30 ends at 10:00 — fine.
  // With a 60-min service, 09:30 would end at 10:30 and must disappear.
  const booked = [{ startAt: '2026-08-21T08:00:00Z', endAt: '2026-08-21T09:00:00Z' }];
  assert.ok(labels(run({ appointments: booked })).includes('09:30'));
  assert.ok(!labels(run({ appointments: booked, durationMinutes: 60 })).includes('09:30'));
});

test('the turnaround buffer keeps slots apart', () => {
  const booked = [{ startAt: '2026-08-21T08:00:00Z', endAt: '2026-08-21T09:00:00Z' }];
  const withBuffer = labels(run({
    appointments: booked,
    settings: { ...SETTINGS, buffer_minutes: 15 },
  }));
  // 11:00 local starts right as the booking ends — 15 minutes too soon now.
  assert.ok(!withBuffer.includes('11:00'));
  assert.ok(withBuffer.includes('11:30'));
  // And the slot before it, which would end flush against the booking.
  assert.ok(!withBuffer.includes('09:30'));
});

test('the lunch break is carved out, including services that straddle it', () => {
  const hours = { ...HOURS, break_start: '12:00', break_end: '12:30' };
  const got = labels(run({ hours }));
  assert.ok(!got.includes('12:00'));
  assert.ok(got.includes('11:30'));
  assert.ok(got.includes('12:30'));

  // A 60-minute service starting at 11:30 would run into the break.
  const long = labels(run({ hours, durationMinutes: 60 }));
  assert.ok(!long.includes('11:30'));
  assert.ok(long.includes('12:30'));
});

test('a closure blocks its window and a full-day closure blocks everything', () => {
  const partial = labels(run({
    closures: [{ startsAt: '2026-08-21T12:00:00Z', endsAt: '2026-08-21T13:00:00Z' }],
  }));
  assert.ok(!partial.includes('14:00')); // 12:00Z = 14:00 local
  assert.ok(!partial.includes('14:30'));
  assert.ok(partial.includes('15:00'));

  const allDay = run({
    closures: [{ startsAt: '2026-08-20T22:00:00Z', endsAt: '2026-08-21T22:00:00Z' }],
  });
  assert.deepEqual(allDay, []);
});

test('lead time hides slots that are too soon', () => {
  // 09:47 local on the day itself, with a 30-minute lead time.
  const nowMs = Date.parse('2026-08-21T07:47:00Z');
  const got = labels(run({ nowMs }));
  assert.ok(!got.includes('10:00')); // only 13 minutes away
  assert.ok(got.includes('10:30'));
});

test('the calendar does not open beyond max_advance_days', () => {
  assert.deepEqual(
    run({ dateKey: '2026-10-30', settings: { ...SETTINGS, max_advance_days: 30 } }),
    [],
  );
  assert.ok(
    run({ dateKey: '2026-09-18', settings: { ...SETTINGS, max_advance_days: 30 } }).length > 0,
  );
});

test('days in the past are never bookable', () => {
  assert.deepEqual(run({ dateKey: '2026-08-20' }), []);
});

test('spring-forward day drops the hour that does not exist', () => {
  // Berlin jumps 02:00 → 03:00 on 2026-03-29. A shop open 01:00–06:00 that
  // day has no 02:00 or 02:30 to sell.
  const slots = computeSlots({
    dateKey: '2026-03-29',
    timezone: TZ,
    hours: { ...HOURS, open_time: '01:00', close_time: '06:00' },
    appointments: [],
    closures: [],
    durationMinutes: 30,
    settings: SETTINGS,
    nowMs: Date.parse('2026-03-28T00:00:00Z'),
  });
  const got = labels(slots);
  assert.ok(got.includes('01:00'));
  assert.ok(got.includes('01:30'));
  assert.ok(!got.includes('02:00'));
  assert.ok(!got.includes('02:30'));
  assert.ok(got.includes('03:00'));
  // Every emitted slot is exactly 30 minutes of real elapsed time.
  for (const s of slots) {
    assert.equal(Date.parse(s.end) - Date.parse(s.start), 30 * 60000);
  }
});

test('a booking made in winter is still evaluated correctly in summer', () => {
  // Same wall-clock hour, opposite side of the DST boundary: the UTC instants
  // differ by an hour and the grid has to follow.
  const winter = computeSlots({
    dateKey: '2026-01-16',
    timezone: TZ,
    hours: HOURS,
    appointments: [],
    closures: [],
    durationMinutes: 30,
    settings: SETTINGS,
    nowMs: Date.parse('2026-01-16T03:00:00Z'),
  });
  assert.equal(winter[0].label, '09:00');
  assert.equal(winter[0].start, '2026-01-16T08:00:00.000Z');
});

// --- validateSlot ------------------------------------------------------------

test('validateSlot accepts a slot the grid offered', () => {
  const slots = run();
  const verdict = validateSlot({
    startMs: Date.parse(slots[3].start),
    durationMinutes: 30,
    timezone: TZ,
    hours: HOURS,
    appointments: [],
    closures: [],
    settings: SETTINGS,
    nowMs: NOW,
  });
  assert.equal(verdict.ok, true);
});

test('validateSlot rejects a slot taken since the grid was drawn', () => {
  // This is the double-booking race: the customer's grid is stale, and the
  // server refuses on their behalf.
  const slots = run();
  const startMs = Date.parse(slots[3].start);
  const verdict = validateSlot({
    startMs,
    durationMinutes: 30,
    timezone: TZ,
    hours: HOURS,
    appointments: [{
      startAt: new Date(startMs).toISOString(),
      endAt: new Date(startMs + 30 * 60000).toISOString(),
    }],
    closures: [],
    settings: SETTINGS,
    nowMs: NOW,
  });
  assert.equal(verdict.ok, false);
  assert.equal(verdict.reason, 'taken');
});

test('validateSlot rejects an off-grid start even when nothing is booked', () => {
  // 09:07 local — never offered, so a hand-crafted request must not take it.
  const verdict = validateSlot({
    startMs: Date.parse('2026-08-21T07:07:00Z'),
    durationMinutes: 30,
    timezone: TZ,
    hours: HOURS,
    appointments: [],
    closures: [],
    settings: SETTINGS,
    nowMs: NOW,
  });
  assert.equal(verdict.ok, false);
});

test('validateSlot rejects a time outside opening hours', () => {
  const verdict = validateSlot({
    startMs: Date.parse('2026-08-21T20:00:00Z'), // 22:00 local
    durationMinutes: 30,
    timezone: TZ,
    hours: HOURS,
    appointments: [],
    closures: [],
    settings: SETTINGS,
    nowMs: NOW,
  });
  assert.equal(verdict.ok, false);
});

test('slot keys are stable per instant and differ between instants', () => {
  const a = slotKeyFor(Date.parse('2026-08-21T07:00:00Z'));
  const b = slotKeyFor(Date.parse('2026-08-21T07:00:00.000Z'));
  const c = slotKeyFor(Date.parse('2026-08-21T07:30:00Z'));
  assert.equal(a, b); // two racing bookings of one slot collide on the index
  assert.notEqual(a, c);
});

// --- more than one chair -----------------------------------------------------
//
// Availability used to assume a single chair, which capped the product at solo
// operators — most shops worth selling to have three to five. A slot is now
// offered while ANY chair can take it, and the tests that matter are the ones
// where "any" and "all" differ.

const CHAIRS = ['chair-1', 'chair-2', 'chair-3'];

/** An appointment at [hh:mm, +minutes) shop time on the test day. */
function booking(hhmm, minutes, resource) {
  const start = Date.parse(`2026-08-21T${hhmm}:00Z`) - 2 * 3600000; // Berlin CEST
  return {
    startAt: new Date(start).toISOString(),
    endAt: new Date(start + minutes * 60000).toISOString(),
    ...(resource ? { resource } : {}),
  };
}

test('with no resources given, the shop is the single chair it always was', () => {
  // The compatibility guarantee: an existing deployment must behave
  // identically until somebody actually adds a chair.
  const solo = run({ appointments: [booking('10:00', 30)] });
  const explicit = run({
    appointments: [booking('10:00', 30)],
    resources: [SOLO_RESOURCE],
  });

  assert.deepEqual(labels(solo), labels(explicit));
  assert.ok(!labels(solo).includes('10:00'));
});

test('a booking on one chair leaves the others sellable', () => {
  const slots = run({
    resources: CHAIRS,
    appointments: [booking('10:00', 30, 'chair-1')],
  });

  const ten = slots.find((s) => s.label === '10:00');
  assert.ok(ten, '10:00 is still on sale');
  assert.deepEqual(ten.free, ['chair-2', 'chair-3']);
});

test('a slot disappears only when every chair is busy', () => {
  const slots = run({
    resources: CHAIRS,
    appointments: [
      booking('10:00', 30, 'chair-1'),
      booking('10:00', 30, 'chair-2'),
    ],
  });
  assert.ok(labels(slots).includes('10:00'), 'one chair left');

  const full = run({
    resources: CHAIRS,
    appointments: [
      booking('10:00', 30, 'chair-1'),
      booking('10:00', 30, 'chair-2'),
      booking('10:00', 30, 'chair-3'),
    ],
  });
  assert.ok(!labels(full).includes('10:00'), 'no chair left');
});

test('a booking with no chair recorded still occupies one', () => {
  // Every row written before the shop grew. Reading these as "assigned to
  // nobody" would silently hand the shop an extra chair's worth of capacity
  // on all of its history.
  const slots = run({
    resources: CHAIRS,
    appointments: [booking('10:00', 30)],
  });

  const ten = slots.find((s) => s.label === '10:00');
  assert.deepEqual(ten.free, ['chair-2', 'chair-3']);
});

test('a booking on a chair the shop no longer has still occupies one', () => {
  const slots = run({
    resources: CHAIRS,
    appointments: [booking('10:00', 30, 'chair-retired')],
  });

  const ten = slots.find((s) => s.label === '10:00');
  assert.deepEqual(ten.free, ['chair-2', 'chair-3'],
    'falls back to the first chair rather than blocking nothing');
});

test('a shop-wide closure empties the grid; a per-chair one costs one chair', () => {
  const window = {
    startsAt: '2026-08-21T08:00:00Z', // 10:00 Berlin
    endsAt: '2026-08-21T09:00:00Z',
  };

  const shopWide = run({ resources: CHAIRS, closures: [window] });
  assert.ok(!labels(shopWide).includes('10:00'), 'the shop is shut');

  const oneBarber = run({
    resources: CHAIRS,
    closures: [{ ...window, resource: 'chair-2' }],
  });
  const ten = oneBarber.find((s) => s.label === '10:00');
  assert.ok(ten, 'the other chairs still work');
  assert.deepEqual(ten.free, ['chair-1', 'chair-3']);
});

test('a shop with every chair switched off is shut', () => {
  assert.deepEqual(run({ resources: [] }), []);
});

test('duplicate chair ids do not inflate capacity', () => {
  const slots = run({
    resources: ['chair-1', 'chair-1'],
    appointments: [booking('10:00', 30, 'chair-1')],
  });
  assert.ok(!labels(slots).includes('10:00'));
});

test('validateSlot reports which chairs are free, and refuses when none are', () => {
  const args = {
    startMs: Date.parse('2026-08-21T08:00:00Z'), // 10:00 Berlin
    durationMinutes: 30,
    timezone: TZ,
    hours: HOURS,
    closures: [],
    settings: SETTINGS,
    nowMs: NOW,
    resources: CHAIRS,
  };

  const some = validateSlot({
    ...args,
    appointments: [booking('10:00', 30, 'chair-1')],
  });
  assert.equal(some.ok, true);
  assert.deepEqual(some.free, ['chair-2', 'chair-3']);

  const none = validateSlot({
    ...args,
    appointments: CHAIRS.map((c) => booking('10:00', 30, c)),
  });
  assert.equal(none.ok, false);
  assert.equal(none.reason, 'taken');
});

test('a booking does not block its own move', () => {
  // Rescheduling to 10:30 when the only thing at 10:30 is this same booking.
  const mine = { ...booking('10:30', 30, 'chair-1'), $id: 'appt-1' };

  const blocked = validateSlot({
    startMs: Date.parse('2026-08-21T08:30:00Z'),
    durationMinutes: 30,
    timezone: TZ,
    hours: HOURS,
    appointments: [mine],
    closures: [],
    settings: SETTINGS,
    nowMs: NOW,
    resources: ['chair-1'],
  });
  assert.equal(blocked.ok, false, 'without exclude it blocks itself');

  const moved = validateSlot({
    startMs: Date.parse('2026-08-21T08:30:00Z'),
    durationMinutes: 30,
    timezone: TZ,
    hours: HOURS,
    appointments: [mine],
    closures: [],
    settings: SETTINGS,
    nowMs: NOW,
    resources: ['chair-1'],
    exclude: ['appt-1'],
  });
  assert.equal(moved.ok, true);
});

test('slot keys are per chair, so one instant sells once per chair', () => {
  const at = Date.parse('2026-08-21T07:00:00Z');

  assert.notEqual(slotKeyFor(at, 'chair-1'), slotKeyFor(at, 'chair-2'));
  assert.equal(slotKeyFor(at, 'chair-1'), slotKeyFor(at, 'chair-1'));
  // The default is the implicit chair every existing row already names.
  assert.equal(slotKeyFor(at), slotKeyFor(at, SOLO_RESOURCE));
});

test('pickResource fills in the shop\'s own order, honouring a preference', () => {
  assert.equal(pickResource(['chair-2', 'chair-3']), 'chair-2');
  assert.equal(pickResource(['chair-2', 'chair-3'], 'chair-3'), 'chair-3');
  // A preference that is not actually free is ignored, not obeyed.
  assert.equal(pickResource(['chair-2', 'chair-3'], 'chair-1'), 'chair-2');
  assert.equal(pickResource([]), null);
});
