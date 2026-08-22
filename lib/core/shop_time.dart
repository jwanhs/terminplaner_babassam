import 'env.dart';

/// Wall-clock time in the *shop's* timezone, independent of the device's.
///
/// Availability and booking are decided on the server, so this is not in the
/// business of choosing slots. It exists for the two places the client still
/// has to reason about wall-clock time:
///
///   * the staff panel, which reads the appointments table directly and must
///     show "10:00" for a booking at 10:00 in the shop — even if the owner is
///     checking tomorrow's diary from a beach in another timezone;
///   * a staff member entering a walk-in at "14:30", which has to become the
///     instant 14:30 *in the shop* means.
///
/// `DateTime.toLocal()` answers a different question — what the device's clock
/// reads — and gives the right answer only by coincidence, when the device
/// happens to sit in the shop's zone. It also silently changed every displayed
/// time twice a year, which is the DST half of the timezone bug this replaces.
///
/// SCOPE: implements the EU rule (DST from 01:00 UTC on the last Sunday in
/// March to 01:00 UTC on the last Sunday in October), which covers every
/// `Europe/*` zone. [isSupported] is false for anything else; a shop outside
/// the EU needs a real tz database (the `timezone` package) wiring in here, and
/// [shopOffset] falls back to the device offset rather than inventing an answer.
class ShopTime {
  const ShopTime._();

  /// Standard-time offsets for the EU zones a white-labelled build might use.
  static const Map<String, Duration> _standardOffsets = {
    'Europe/Berlin': Duration(hours: 1),
    'Europe/Vienna': Duration(hours: 1),
    'Europe/Zurich': Duration(hours: 1),
    'Europe/Paris': Duration(hours: 1),
    'Europe/Madrid': Duration(hours: 1),
    'Europe/Rome': Duration(hours: 1),
    'Europe/Amsterdam': Duration(hours: 1),
    'Europe/Brussels': Duration(hours: 1),
    'Europe/Prague': Duration(hours: 1),
    'Europe/Warsaw': Duration(hours: 1),
    'Europe/Copenhagen': Duration(hours: 1),
    'Europe/Stockholm': Duration(hours: 1),
    'Europe/Oslo': Duration(hours: 1),
    'Europe/London': Duration.zero,
    'Europe/Dublin': Duration.zero,
    'Europe/Lisbon': Duration.zero,
    'Europe/Helsinki': Duration(hours: 2),
    'Europe/Athens': Duration(hours: 2),
    'Europe/Bucharest': Duration(hours: 2),
  };

  static String get timezone => Env.shopTimezone;

  static bool get isSupported => _standardOffsets.containsKey(timezone);

  /// True while EU summer time is in force at [instant].
  ///
  /// The transitions are defined in UTC — 01:00 UTC on the last Sunday of
  /// March and of October — which is why every EU zone switches at the same
  /// moment rather than at a local hour that would need per-zone handling.
  static bool isSummerTime(DateTime instant) {
    final utc = instant.toUtc();
    final start = _lastSundayOfMonth(utc.year, DateTime.march);
    final end = _lastSundayOfMonth(utc.year, DateTime.october);
    return !utc.isBefore(start) && utc.isBefore(end);
  }

  /// The shop's UTC offset at [instant].
  static Duration shopOffset(DateTime instant) {
    final standard = _standardOffsets[timezone];
    if (standard == null) {
      // Unknown zone: the device's own offset is the best available answer,
      // and pretending otherwise would be worse than admitting it.
      return instant.toLocal().timeZoneOffset;
    }
    return isSummerTime(instant)
        ? standard + const Duration(hours: 1)
        : standard;
  }

  /// [instant] expressed as the shop's wall clock.
  ///
  /// The result is a `DateTime` whose *fields* read as the shop's clock; it is
  /// flagged UTC so nothing re-applies the device offset on top. Use it for
  /// display and for `.year/.month/.day/.hour`, never as an instant.
  static DateTime toShopWall(DateTime instant) =>
      instant.toUtc().add(shopOffset(instant));

  /// The instant at which the shop's clock reads the given wall-clock fields.
  ///
  /// Inverse of [toShopWall]. Two-pass, because the offset depends on the
  /// instant we are solving for: guess with the offset at the naive reading,
  /// then correct if that guess landed on the other side of a transition.
  static DateTime fromShopWall(
    int year,
    int month,
    int day, [
    int hour = 0,
    int minute = 0,
  ]) {
    final naive = DateTime.utc(year, month, day, hour, minute);
    var instant = naive.subtract(shopOffset(naive));
    instant = naive.subtract(shopOffset(instant));
    return instant;
  }

  /// Shop-local midnight of the day containing [instant], as an instant.
  static DateTime startOfShopDay(DateTime instant) {
    final wall = toShopWall(instant);
    return fromShopWall(wall.year, wall.month, wall.day);
  }

  /// "YYYY-MM-DD" for the shop-local day containing [instant] — the form the
  /// booking API expects.
  static String dateKey(DateTime instant) {
    final w = toShopWall(instant);
    return '${w.year.toString().padLeft(4, '0')}-'
        '${w.month.toString().padLeft(2, '0')}-'
        '${w.day.toString().padLeft(2, '0')}';
  }

  /// "HH:mm" on the shop's clock.
  static String timeLabel(DateTime instant) {
    final w = toShopWall(instant);
    return '${w.hour.toString().padLeft(2, '0')}:'
        '${w.minute.toString().padLeft(2, '0')}';
  }

  /// True when the device's clock disagrees with the shop's.
  ///
  /// Worth surfacing in the staff panel: a phone in the wrong timezone is a
  /// support call waiting to happen, and silently correcting it without saying
  /// so leaves everyone confused about which time is real.
  static bool deviceDisagrees(DateTime instant) =>
      instant.toLocal().timeZoneOffset != shopOffset(instant);

  /// 01:00 UTC on the last Sunday of [month] — an EU DST transition.
  static DateTime _lastSundayOfMonth(int year, int month) {
    // Day 0 of the next month is the last day of this one.
    final lastDay = DateTime.utc(year, month + 1, 0);
    final sunday = lastDay.day - (lastDay.weekday % 7);
    return DateTime.utc(year, month, sunday, 1);
  }
}
