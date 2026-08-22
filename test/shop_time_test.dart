import 'package:babassam/core/shop_time.dart';
import 'package:flutter_test/flutter_test.dart';

/// These pin down the half of the timezone bug that lives in the client.
///
/// The other half — deciding which slots exist — moved to the server and is
/// covered by `infra/functions/booking-api/test/shoptime.test.js`. What is left
/// here is display and entry: showing a booking at the hour the *shop* means,
/// and turning "14:30" typed by a staff member into the right instant.
///
/// Runs against the default SHOP_TIMEZONE (Europe/Berlin). A build for another
/// zone would need its own fixtures.
void main() {
  group('ShopTime', () {
    test('Europe/Berlin is a supported zone', () {
      expect(ShopTime.timezone, 'Europe/Berlin');
      expect(ShopTime.isSupported, isTrue);
    });

    test('summer time is in force between the March and October transitions',
        () {
      expect(ShopTime.isSummerTime(DateTime.utc(2026, 1, 15)), isFalse);
      expect(ShopTime.isSummerTime(DateTime.utc(2026, 7, 15)), isTrue);

      // 2026 transitions: 29 March and 25 October, both at 01:00 UTC.
      expect(ShopTime.isSummerTime(DateTime.utc(2026, 3, 29, 0, 59)), isFalse);
      expect(ShopTime.isSummerTime(DateTime.utc(2026, 3, 29, 1, 0)), isTrue);
      expect(ShopTime.isSummerTime(DateTime.utc(2026, 10, 25, 0, 59)), isTrue);
      expect(ShopTime.isSummerTime(DateTime.utc(2026, 10, 25, 1, 0)), isFalse);
    });

    test('the offset is +1 in winter and +2 in summer', () {
      expect(ShopTime.shopOffset(DateTime.utc(2026, 1, 15)),
          const Duration(hours: 1));
      expect(ShopTime.shopOffset(DateTime.utc(2026, 7, 15)),
          const Duration(hours: 2));
    });

    test('an instant renders as the shop wall clock, not the device clock', () {
      // 07:00Z is 09:00 in Berlin in July…
      expect(ShopTime.timeLabel(DateTime.utc(2026, 7, 15, 7)), '09:00');
      // …and 08:00 in January.
      expect(ShopTime.timeLabel(DateTime.utc(2026, 1, 15, 7)), '08:00');
    });

    test('wall-clock entry produces the instant the shop means', () {
      expect(
        ShopTime.fromShopWall(2026, 7, 15, 9, 0),
        DateTime.utc(2026, 7, 15, 7, 0),
      );
      expect(
        ShopTime.fromShopWall(2026, 1, 15, 9, 0),
        DateTime.utc(2026, 1, 15, 8, 0),
      );
    });

    test('wall time and instant round-trip across a whole year', () {
      for (var d = 0; d < 365; d += 5) {
        final instant = DateTime.utc(2026, 1, 1, 9, 30).add(Duration(days: d));
        final wall = ShopTime.toShopWall(instant);
        final back = ShopTime.fromShopWall(
            wall.year, wall.month, wall.day, wall.hour, wall.minute);
        expect(back, instant, reason: 'failed for $instant');
      }
    });

    test('the shop day is the shop\'s, not UTC\'s', () {
      // 22:30Z on 15 July is already 00:30 on the 16th in Berlin.
      expect(ShopTime.dateKey(DateTime.utc(2026, 7, 15, 22, 30)), '2026-07-16');
      expect(ShopTime.dateKey(DateTime.utc(2026, 7, 15, 21, 30)), '2026-07-15');
    });

    test('startOfShopDay lands on shop-local midnight', () {
      final start = ShopTime.startOfShopDay(DateTime.utc(2026, 7, 15, 14));
      // Midnight in Berlin in July is 22:00Z the previous day.
      expect(start, DateTime.utc(2026, 7, 14, 22));
      expect(ShopTime.timeLabel(start), '00:00');
      expect(ShopTime.dateKey(start), '2026-07-15');
    });

    test('a day still starts at midnight on the DST changeover days', () {
      for (final key in ['2026-03-29', '2026-10-25']) {
        final parts = key.split('-').map(int.parse).toList();
        final start = ShopTime.fromShopWall(parts[0], parts[1], parts[2]);
        expect(ShopTime.timeLabel(start), '00:00', reason: 'failed for $key');
        expect(ShopTime.dateKey(start), key);
      }
    });

    test('adding a nominal day across the spring transition still lands right',
        () {
      // 28 March 10:00 local → 29 March 10:00 local is 23 real hours apart,
      // which is exactly why the strip is rebuilt through the wall clock
      // rather than by adding 24 hours to an instant.
      final before = ShopTime.fromShopWall(2026, 3, 28, 10);
      final wall =
          ShopTime.toShopWall(before.add(const Duration(days: 1, hours: 12)));
      final next = ShopTime.fromShopWall(wall.year, wall.month, wall.day, 10);
      expect(ShopTime.dateKey(next), '2026-03-29');
      expect(ShopTime.timeLabel(next), '10:00');
      expect(next.difference(before), const Duration(hours: 23));
    });
  });
}
