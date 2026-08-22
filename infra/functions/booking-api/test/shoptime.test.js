import { test } from 'node:test';
import assert from 'node:assert/strict';

import {
  tzOffsetMs, wallPartsOf, zonedWallToUtc, wallClockLabel, shopDateKey,
  parseHm, parseDateKey, addDays, daysBetween,
} from '../src/shoptime.js';

const TZ = 'Europe/Berlin';
const H = 3600000;

test('Berlin runs at UTC+1 in winter and UTC+2 in summer', () => {
  assert.equal(tzOffsetMs(Date.parse('2026-01-15T12:00:00Z'), TZ), 1 * H);
  assert.equal(tzOffsetMs(Date.parse('2026-07-15T12:00:00Z'), TZ), 2 * H);
});

test('wall time converts to the right UTC instant on both sides of DST', () => {
  // 09:00 in Berlin is 08:00Z in winter…
  assert.equal(
    zonedWallToUtc({ year: 2026, month: 1, day: 15, hour: 9, minute: 0 }, TZ),
    Date.parse('2026-01-15T08:00:00Z'),
  );
  // …and 07:00Z in summer. A client computing this locally gets it wrong by an
  // hour for half the year, which is the bug this module exists to kill.
  assert.equal(
    zonedWallToUtc({ year: 2026, month: 7, day: 15, hour: 9, minute: 0 }, TZ),
    Date.parse('2026-07-15T07:00:00Z'),
  );
});

test('the hour skipped by spring-forward has no instant', () => {
  // 2026-03-29: Berlin jumps 02:00 → 03:00. 02:30 never happens.
  assert.equal(zonedWallToUtc({ year: 2026, month: 3, day: 29, hour: 2, minute: 30 }, TZ), null);
  // The hours either side are fine.
  assert.ok(zonedWallToUtc({ year: 2026, month: 3, day: 29, hour: 1, minute: 30 }, TZ));
  assert.ok(zonedWallToUtc({ year: 2026, month: 3, day: 29, hour: 3, minute: 30 }, TZ));
});

test('the repeated hour on fall-back resolves to the earlier instant', () => {
  // 2026-10-25: Berlin repeats 02:00–03:00. 02:30 exists twice; we take the
  // first (still CEST, +2) occurrence.
  const ts = zonedWallToUtc({ year: 2026, month: 10, day: 25, hour: 2, minute: 30 }, TZ);
  assert.equal(ts, Date.parse('2026-10-25T00:30:00Z'));
  assert.equal(wallClockLabel(ts, TZ), '02:30');
});

test('round-trip: instant → label → instant is stable across a year', () => {
  for (let d = 0; d < 365; d += 7) {
    const ts = Date.parse('2026-01-01T09:30:00Z') + d * 24 * H;
    const parts = wallPartsOf(ts, TZ);
    const back = zonedWallToUtc(parts, TZ);
    assert.equal(back, ts, `failed for ${new Date(ts).toISOString()}`);
  }
});

test('shopDateKey uses the shop day, not the UTC day', () => {
  // 23:30Z in July is 01:30 the next day in Berlin.
  assert.equal(shopDateKey(Date.parse('2026-07-15T23:30:00Z'), TZ), '2026-07-16');
  assert.equal(shopDateKey(Date.parse('2026-07-15T21:30:00Z'), TZ), '2026-07-15');
});

test('weekday is ISO-with-Monday-zero, matching business_hours', () => {
  // 2026-08-17 is a Monday.
  assert.equal(wallPartsOf(Date.parse('2026-08-17T10:00:00Z'), TZ).weekday, 0);
  // 2026-08-23 is a Sunday.
  assert.equal(wallPartsOf(Date.parse('2026-08-23T10:00:00Z'), TZ).weekday, 6);
});

test('parseHm accepts real times and rejects nonsense', () => {
  assert.equal(parseHm('09:30'), 570);
  assert.equal(parseHm('9:30'), 570);
  assert.equal(parseHm('00:00'), 0);
  assert.equal(parseHm('23:59'), 1439);
  assert.equal(parseHm('24:00'), null);
  assert.equal(parseHm('09:60'), null);
  assert.equal(parseHm(''), null);
  assert.equal(parseHm(null), null);
  assert.equal(parseHm('halb zehn'), null);
});

test('date keys parse, add and subtract across month and DST boundaries', () => {
  assert.deepEqual(parseDateKey('2026-03-29'), { year: 2026, month: 3, day: 29 });
  assert.throws(() => parseDateKey('29.03.2026'));
  assert.throws(() => parseDateKey('2026-13-01'));

  assert.equal(addDays('2026-03-28', 1), '2026-03-29');
  assert.equal(addDays('2026-12-31', 1), '2027-01-01');
  assert.equal(addDays('2026-03-01', -1), '2026-02-28');

  assert.equal(daysBetween('2026-08-14', '2026-08-21'), 7);
  assert.equal(daysBetween('2026-08-21', '2026-08-14'), -7);
  // Spanning the spring-forward day is still exactly one day apart.
  assert.equal(daysBetween('2026-03-28', '2026-03-30'), 2);
});
