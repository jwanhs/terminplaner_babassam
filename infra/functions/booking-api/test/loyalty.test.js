import { test } from 'node:test';
import assert from 'node:assert/strict';

import { loyaltyCard, canRedeem } from '../src/loyalty.js';

const NOW = Date.parse('2026-08-21T12:00:00Z');
const HOUR = 3600000;

function visit({ daysAgo = 1, status = 'confirmed', discount = 0 } = {}) {
  const end = NOW - daysAgo * 24 * HOUR;
  return {
    $id: `a${daysAgo}_${status}_${discount}`,
    start_at: new Date(end - HOUR).toISOString(),
    end_at: new Date(end).toISOString(),
    status,
    discount_cents: discount,
  };
}

test('a fresh customer has an empty card', () => {
  const card = loyaltyCard([], NOW, 10);
  assert.equal(card.stamps, 0);
  assert.equal(card.filled, 0);
  assert.equal(card.hasReward, false);
});

test('only visits that have already happened earn a stamp', () => {
  const appts = [
    visit({ daysAgo: 5 }),
    visit({ daysAgo: 2 }),
    visit({ daysAgo: -3 }), // still in the future
  ];
  assert.equal(loyaltyCard(appts, NOW, 10).stamps, 2);
});

test('a cancelled visit takes its stamp back', () => {
  const appts = [visit({ daysAgo: 5 }), visit({ daysAgo: 2, status: 'cancelled' })];
  assert.equal(loyaltyCard(appts, NOW, 10).stamps, 1);
});

test('ten visits earn one reward, and the card reads full', () => {
  const appts = Array.from({ length: 10 }, (_, i) => visit({ daysAgo: i + 1 }));
  const card = loyaltyCard(appts, NOW, 10);
  assert.equal(card.stamps, 10);
  assert.equal(card.rewardsEarned, 1);
  assert.equal(card.rewardsAvailable, 1);
  assert.equal(card.hasReward, true);
  assert.equal(card.filled, 10);
});

test('a redeemed reward is spent and cannot be counted twice', () => {
  const appts = [
    ...Array.from({ length: 10 }, (_, i) => visit({ daysAgo: i + 1 })),
    visit({ daysAgo: -1, discount: 2500 }), // upcoming free cut
  ];
  const card = loyaltyCard(appts, NOW, 10);
  assert.equal(card.rewardsEarned, 1);
  assert.equal(card.rewardsRedeemed, 1);
  assert.equal(card.rewardsAvailable, 0);
  assert.equal(card.hasReward, false);
});

test('the card rolls over past a full set of stamps', () => {
  const appts = Array.from({ length: 23 }, (_, i) => visit({ daysAgo: i + 1 }));
  const card = loyaltyCard(appts, NOW, 10);
  assert.equal(card.rewardsEarned, 2);
  assert.equal(card.rewardsAvailable, 2);
  // With rewards pending the card presents as full rather than at 3/10.
  assert.equal(card.filled, 10);
});

// --- canRedeem ---------------------------------------------------------------

const earned = Array.from({ length: 10 }, (_, i) => visit({ daysAgo: i + 1 }));

function target(overrides = {}) {
  return {
    $id: 'target',
    start_at: new Date(NOW + 24 * HOUR).toISOString(),
    end_at: new Date(NOW + 25 * HOUR).toISOString(),
    status: 'confirmed',
    discount_cents: 0,
    paid: false,
    ...overrides,
  };
}

test('a full card may be redeemed against an upcoming booking', () => {
  const verdict = canRedeem({
    target: target(), appts: [...earned, target()], nowMs: NOW, stampsPerReward: 10,
  });
  assert.equal(verdict.ok, true);
});

test('redemption is refused without an earned reward', () => {
  const verdict = canRedeem({
    target: target(),
    appts: [visit({ daysAgo: 1 }), target()],
    nowMs: NOW,
    stampsPerReward: 10,
  });
  assert.equal(verdict.ok, false);
  assert.equal(verdict.reason, 'no_reward');
});

test('redemption is refused on a booking that already carries a discount', () => {
  const t = target({ discount_cents: 2500 });
  const verdict = canRedeem({ target: t, appts: [...earned, t], nowMs: NOW, stampsPerReward: 10 });
  assert.equal(verdict.ok, false);
  assert.equal(verdict.reason, 'already_redeemed');
});

test('redemption is refused once the booking is paid, cancelled or past', () => {
  for (const [overrides, reason] of [
    [{ paid: true }, 'already_paid'],
    [{ status: 'cancelled' }, 'cancelled'],
    [{ start_at: new Date(NOW - HOUR).toISOString() }, 'past'],
  ]) {
    const t = target(overrides);
    const verdict = canRedeem({ target: t, appts: [...earned, t], nowMs: NOW, stampsPerReward: 10 });
    assert.equal(verdict.ok, false, `expected refusal for ${reason}`);
    assert.equal(verdict.reason, reason);
  }
});

test('a second redemption on a second booking needs a second full card', () => {
  // One reward earned, already spent on booking A. Booking B must be refused.
  const spent = target({ $id: 'A', discount_cents: 2500 });
  const b = target({ $id: 'B' });
  const verdict = canRedeem({
    target: b, appts: [...earned, spent, b], nowMs: NOW, stampsPerReward: 10,
  });
  assert.equal(verdict.ok, false);
  assert.equal(verdict.reason, 'no_reward');
});
