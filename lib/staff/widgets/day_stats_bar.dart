import 'package:flutter/material.dart';

import '../../core/brand.dart';
import '../data/models.dart';

/// The day at a glance: how many bookings, how many still to come, what the
/// day is worth and how much of it is still outstanding.
class DayStatsBar extends StatelessWidget {
  const DayStatsBar({super.key, required this.totals});

  final DayTotals totals;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final b = brandOf(context);

    return Container(
      margin: const EdgeInsets.fromLTRB(S.lg, S.sm, S.lg, S.sm),
      padding: const EdgeInsets.symmetric(horizontal: S.lg, vertical: S.md),
      decoration: BoxDecoration(
        color: b.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: b.secondary.withValues(alpha: 0.35)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              _Stat(label: 'Termine', value: '${totals.total}'),
              _Divider(color: b.secondary),
              _Stat(label: 'Anstehend', value: '${totals.upcoming}'),
              _Divider(color: b.secondary),
              _Stat(label: 'Erledigt', value: '${totals.completed}'),
              if (totals.noShows > 0) ...[
                _Divider(color: b.secondary),
                _Stat(
                  label: 'No-Show',
                  value: '${totals.noShows}',
                  color: t.colorScheme.error,
                ),
              ],
            ],
          ),
          if (totals.expectedCents > 0) ...[
            const SizedBox(height: S.md),
            Divider(height: 1, color: b.secondary.withValues(alpha: 0.25)),
            const SizedBox(height: S.md),
            Row(
              children: [
                _Stat(label: 'Umsatz', value: _euro(totals.expectedCents)),
                _Divider(color: b.secondary),
                _Stat(
                  label: 'Bezahlt',
                  value: _euro(totals.paidCents),
                  color: totals.paidCents > 0 ? b.primary : null,
                ),
                _Divider(color: b.secondary),
                _Stat(
                  label: 'Ausstehend',
                  value: _euro(totals.outstandingCents),
                  color: totals.outstandingCents > 0
                      ? t.colorScheme.onSurfaceVariant
                      : null,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  static String _euro(int cents) => '€${(cents / 100).toStringAsFixed(2)}';
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: t.textTheme.titleLarge?.copyWith(
              color: color ?? t.colorScheme.onSurface,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: t.textTheme.labelSmall
                ?.copyWith(color: t.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        width: 1,
        height: 28,
        color: color.withValues(alpha: 0.25),
      );
}
