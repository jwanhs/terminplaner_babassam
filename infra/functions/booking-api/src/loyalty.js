// Stamp-card maths, server side.
//
// The Dart model computes the same numbers for display. This copy is the one
// that decides whether a free cut is actually granted — the client's opinion
// about how many stamps it has is a UI hint, nothing more. Keep the two in
// step: lib/customer/data/models.dart (LoyaltyCard).
//
// Stamps stay *derived* from booking history rather than stored in a counter,
// so there is no number anyone can edit — and a cancelled visit quietly takes
// its stamp back.

/**
 * @param {object[]} appts appointment rows for one phone number
 * @param {number}   nowMs
 * @param {number}   stampsPerReward
 */
export function loyaltyCard(appts, nowMs, stampsPerReward = 10) {
  let stamps = 0;
  let redeemed = 0;
  for (const a of appts) {
    if (a.status === 'cancelled') continue;
    const end = Date.parse(a.end_at ?? a.endAt);
    if (Number.isFinite(end) && end <= nowMs) stamps++;
    if ((a.discount_cents ?? a.discountCents ?? 0) > 0) redeemed++;
  }
  const earned = stampsPerReward > 0 ? Math.floor(stamps / stampsPerReward) : 0;
  const available = Math.max(0, earned - redeemed);
  return {
    stamps,
    stampsPerReward,
    rewardsRedeemed: redeemed,
    rewardsEarned: earned,
    rewardsAvailable: available,
    hasReward: available > 0,
    filled: available > 0
      ? stampsPerReward
      : (stampsPerReward > 0 ? stamps % stampsPerReward : 0),
  };
}

/**
 * May [target] be paid for with a loyalty reward?
 *
 * Guards every way this could be abused: the booking must exist, belong to the
 * phone number, still be upcoming, not already discounted, not already paid,
 * and the card must actually have an unspent reward on it.
 */
export function canRedeem({ target, appts, nowMs, stampsPerReward }) {
  if (!target) return { ok: false, reason: 'not_found' };
  if (target.status === 'cancelled') return { ok: false, reason: 'cancelled' };
  if ((target.discount_cents ?? 0) > 0) return { ok: false, reason: 'already_redeemed' };
  if (target.paid) return { ok: false, reason: 'already_paid' };
  if (Date.parse(target.start_at) <= nowMs) return { ok: false, reason: 'past' };

  const card = loyaltyCard(appts, nowMs, stampsPerReward);
  if (!card.hasReward) return { ok: false, reason: 'no_reward' };
  return { ok: true, card };
}
