import 'package:flutter/material.dart';

import '../../core/brand.dart';
import '../data/models.dart';

/// The customer's Treuekarte (stamp card). Renders one slot per stamp the card
/// holds, fills the earned ones, and calls out a ready reward. Purely
/// presentational — the parent owns the redeem action (a chip on the matching
/// appointment tile).
class LoyaltyCardView extends StatelessWidget {
  const LoyaltyCardView({super.key, required this.card});

  final LoyaltyCard card;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final b = brandOf(context);
    final ready = card.hasReward;

    return Padding(
      padding: const EdgeInsets.fromLTRB(S.lg, S.sm, S.lg, S.sm),
      child: Container(
        padding: const EdgeInsets.all(S.lg),
        decoration: BoxDecoration(
          color: b.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: ready ? b.secondary : b.secondary.withValues(alpha: 0.35),
            width: ready ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.content_cut, size: 18, color: b.primary),
                const SizedBox(width: S.sm),
                Text('Treuekarte',
                    style: t.textTheme.titleMedium?.copyWith(
                      color: b.primary,
                      fontWeight: FontWeight.w700,
                    )),
                const Spacer(),
                Text(
                  card.stamps == 1 ? '1 Besuch' : '${card.stamps} Besuche',
                  style: t.textTheme.labelMedium?.copyWith(
                    color: t.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: S.md),
            _Stamps(filled: card.filled, total: card.stampsPerReward, brand: b),
            const SizedBox(height: S.md),
            if (ready)
              _RewardBanner(brand: b, t: t, count: card.rewardsAvailable)
            else
              Text(
                card.untilNext == 1
                    ? 'Noch 1 Besuch bis zum Gratis-Schnitt.'
                    : 'Noch ${card.untilNext} Besuche bis zum Gratis-Schnitt.',
                style: t.textTheme.bodyMedium?.copyWith(
                  color: t.colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A row of stamp slots: filled ones carry the scissors mark, empty ones are
/// hairline rings. Wraps onto multiple lines on narrow screens.
class _Stamps extends StatelessWidget {
  const _Stamps({
    required this.filled,
    required this.total,
    required this.brand,
  });

  final int filled;
  final int total;
  final BrandIdentity brand;

  @override
  Widget build(BuildContext context) {
    const maxDiameter = 32.0;
    const minGap = 4.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        // Largest circle that still lets all [total] stamps fit on one row,
        // capped so a low-count card doesn't render giant dots. Any leftover
        // width is shared as even spacing by the Row below.
        final fitted = total <= 1
            ? maxDiameter
            : (constraints.maxWidth - minGap * (total - 1)) / total;
        final double d = fitted.clamp(12.0, maxDiameter).toDouble();
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(total, (i) {
            final on = i < filled;
            return Container(
              width: d,
              height: d,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: on ? brand.secondary : Colors.transparent,
                border: Border.all(
                  color: on
                      ? brand.secondary
                      : brand.secondary.withValues(alpha: 0.5),
                  width: 1.5,
                ),
              ),
              child: on
                  ? Icon(Icons.content_cut, size: d * 0.5, color: brand.primary)
                  : null,
            );
          }),
        );
      },
    );
  }
}

/// The "your free cut is ready" call-out, shown in place of the progress line
/// once at least one voucher is available.
class _RewardBanner extends StatelessWidget {
  const _RewardBanner({
    required this.brand,
    required this.t,
    required this.count,
  });

  final BrandIdentity brand;
  final ThemeData t;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: S.md, vertical: S.sm),
      decoration: BoxDecoration(
        color: brand.primary,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.card_giftcard, size: 18, color: Colors.white),
          const SizedBox(width: S.sm),
          Expanded(
            child: Text(
              count > 1
                  ? '$count Gratis-Schnitte bereit! Zeig diese Karte beim Friseur.'
                  : 'Gratis-Schnitt bereit! Zeig diese Karte beim Friseur.',
              style: t.textTheme.bodyMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
