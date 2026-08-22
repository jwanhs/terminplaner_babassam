import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../../core/brand.dart';
import '../../core/shop_time.dart';
import '../../core/widgets/selectable_tile.dart';
import '../controllers/booking_controller.dart';

/// The day picker.
///
/// Each entry is an *instant* at shop-local midnight, so tapping one asks the
/// server for the right day no matter where the phone is. Everything shown —
/// the weekday, the number, the month — is derived through [ShopTime] rather
/// than from the instant's own fields, which would be UTC and could name the
/// wrong day entirely (shop midnight in a German summer is 22:00 the previous
/// day in UTC).
class DateStrip extends StatelessWidget {
  const DateStrip({super.key});

  @override
  Widget build(BuildContext context) {
    final c = Get.find<BookingController>();
    return SizedBox(
      height: 88,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: S.lg),
        itemCount: c.dateStrip.length,
        separatorBuilder: (_, __) => const SizedBox(width: S.sm),
        itemBuilder: (_, i) {
          final d = c.dateStrip[i];
          return Obx(() {
            final selected =
                ShopTime.dateKey(c.selectedDate.value) == ShopTime.dateKey(d);
            final wall = ShopTime.toShopWall(d);
            final closed = c.hours[wall.weekday - 1]?.closed ?? false;
            return DateTile(
              date: d,
              selected: selected,
              closed: closed,
              onTap: closed ? null : () => c.pickDate(d),
            );
          });
        },
      ),
    );
  }
}

/// One day in the strip. Shared with the reschedule page so both read the same.
class DateTile extends StatelessWidget {
  const DateTile({
    super.key,
    required this.date,
    required this.selected,
    required this.closed,
    required this.onTap,
  });

  /// An instant at shop-local midnight.
  final DateTime date;
  final bool selected;
  final bool closed;
  final VoidCallback? onTap;

  static const _weekdays = ['MO', 'DI', 'MI', 'DO', 'FR', 'SA', 'SO'];

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final b = brandOf(context);

    // The shop's calendar day, not the device's.
    final wall = ShopTime.toShopWall(date);
    final weekday = _weekdays[wall.weekday - 1];
    final month = DateFormat.MMM('de_DE').format(wall);
    final long = DateFormat('EEEE, d. MMMM', 'de_DE').format(wall);

    final fg = selected
        ? Colors.white
        : closed
            ? t.colorScheme.onSurfaceVariant.withValues(alpha: 0.5)
            : t.colorScheme.onSurface;

    return SelectableTile(
      selected: selected,
      disabled: closed,
      onTap: onTap,
      width: 64,
      borderRadius: 14,
      backgroundColor: b.surface,
      selectedBackgroundColor: b.primary,
      borderColor: b.secondary.withValues(alpha: 0.7),
      selectedBorderColor: b.primary,
      semanticLabel: closed ? '$long, geschlossen' : long,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: S.sm),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(weekday,
                style: t.textTheme.labelSmall
                    ?.copyWith(color: fg, letterSpacing: 1.1)),
            const SizedBox(height: 2),
            Text('${wall.day}',
                style: t.textTheme.titleLarge
                    ?.copyWith(color: fg, fontWeight: FontWeight.w700)),
            Text(month, style: t.textTheme.labelSmall?.copyWith(color: fg)),
          ],
        ),
      ),
    );
  }
}
