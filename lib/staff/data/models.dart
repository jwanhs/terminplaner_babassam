import '../../core/shop_time.dart';

/// Row-shaped models for the staff panel.
///
/// Deliberately separate from the customer app's models: staff are
/// authenticated and read the tables directly, so they see rows — including
/// fields the customer API strips before it answers anyone (internal notes,
/// payment handles, the booking's source). The customer app consumes the
/// booking API's sanitised JSON instead, and the two shapes should be free to
/// diverge.

enum ApptStatus { confirmed, cancelled, completed, noShow }

extension ApptStatusX on ApptStatus {
  String get wire => switch (this) {
        ApptStatus.confirmed => 'confirmed',
        ApptStatus.cancelled => 'cancelled',
        ApptStatus.completed => 'completed',
        ApptStatus.noShow => 'no_show',
      };

  String get label => switch (this) {
        ApptStatus.confirmed => 'Bestätigt',
        ApptStatus.cancelled => 'Storniert',
        ApptStatus.completed => 'Erledigt',
        ApptStatus.noShow => 'Nicht erschienen',
      };

  static ApptStatus fromWire(String? s) => switch (s) {
        'cancelled' => ApptStatus.cancelled,
        'completed' => ApptStatus.completed,
        'no_show' => ApptStatus.noShow,
        _ => ApptStatus.confirmed,
      };
}

enum ApptSource { online, walkin, staff }

extension ApptSourceX on ApptSource {
  String get wire => name;
  String get label => switch (this) {
        ApptSource.online => 'Online',
        ApptSource.walkin => 'Laufkundschaft',
        ApptSource.staff => 'Vom Team',
      };
  static ApptSource fromWire(String? s) => switch (s) {
        'walkin' => ApptSource.walkin,
        'staff' => ApptSource.staff,
        _ => ApptSource.online,
      };
}

class StaffAppointment {
  StaffAppointment({
    required this.id,
    required this.customerName,
    required this.customerPhone,
    required this.serviceId,
    required this.serviceName,
    required this.startAt,
    required this.endAt,
    required this.status,
    required this.source,
    this.notes,
    this.paid = false,
    this.paymentAmountCents = 0,
    this.discountCents = 0,
    this.resourceId,
  });

  final String id;
  final String customerName;
  final String customerPhone;
  final String serviceId;
  final String serviceName;

  /// Always a UTC instant. Render through [ShopTime], never `toLocal()`.
  final DateTime startAt;
  final DateTime endAt;

  final ApptStatus status;
  final ApptSource source;
  final String? notes;
  final bool paid;
  final int paymentAmountCents;
  final int discountCents;

  /// Which chair this booking sits on — a [Chair] id, or null on every row
  /// written before the shop had more than one. A one-chair shop leaves this
  /// null forever and nothing in the panel shows a chair at all.
  final String? resourceId;

  String get startLabel => ShopTime.timeLabel(startAt);
  String get endLabel => ShopTime.timeLabel(endAt);
  String get timeRangeLabel => '$startLabel – $endLabel';

  Duration get duration => endAt.difference(startAt);

  bool get isCancelled => status == ApptStatus.cancelled;
  bool get hasRealPhone => customerPhone.trim().length > 3;
  bool get rewardRedeemed => discountCents > 0;

  /// Still open business: it has not happened yet and nobody has closed it out.
  bool isUpcoming(DateTime now) =>
      status == ApptStatus.confirmed && endAt.isAfter(now);

  /// Confirmed, but the slot has already passed — the row staff need to close
  /// out as done or as a no-show.
  bool needsClosing(DateTime now) =>
      status == ApptStatus.confirmed && !endAt.isAfter(now);

  factory StaffAppointment.fromRow(Map<String, dynamic> d, String id) =>
      StaffAppointment(
        id: id,
        customerName: (d['customer_name'] as String?) ?? '—',
        customerPhone: (d['customer_phone'] as String?) ?? '',
        serviceId: (d['service_id'] as String?) ?? '',
        serviceName: (d['service_name'] as String?) ?? '—',
        startAt: DateTime.parse(d['start_at'] as String).toUtc(),
        endAt: DateTime.parse(d['end_at'] as String).toUtc(),
        status: ApptStatusX.fromWire(d['status'] as String?),
        source: ApptSourceX.fromWire(d['source'] as String?),
        notes: d['notes'] as String?,
        paid: (d['paid'] as bool?) ?? false,
        paymentAmountCents: (d['payment_amount_cents'] as int?) ?? 0,
        discountCents: (d['discount_cents'] as int?) ?? 0,
        resourceId: _emptyToNull(d['resource_id'] as String?),
      );
}

String? _emptyToNull(String? value) =>
    (value == null || value.isEmpty) ? null : value;

/// A chair, station or barber that can take a booking alongside the others.
///
/// A shop with no chairs configured is a one-chair shop: the booking API falls
/// back to an implicit resource, and the panel hides every mention of chairs
/// rather than showing a solo barber a column header they did not ask for.
class Chair {
  const Chair({
    required this.id,
    required this.name,
    this.displayOrder = 100,
    this.active = true,
  });

  final String id;
  final String name;
  final int displayOrder;
  final bool active;

  factory Chair.fromRow(Map<String, dynamic> d, String id) => Chair(
        id: id,
        name: (d['name'] as String?) ?? '—',
        displayOrder: (d['display_order'] as int?) ?? 100,
        active: (d['active'] as bool?) ?? true,
      );
}

class ShopService {
  ShopService({
    required this.id,
    required this.name,
    required this.durationMinutes,
    required this.priceCents,
    this.active = true,
  });

  final String id;
  final String name;
  final int durationMinutes;
  final int priceCents;
  final bool active;

  String get priceLabel => '€${(priceCents / 100).toStringAsFixed(2)}';

  factory ShopService.fromRow(Map<String, dynamic> d, String id) => ShopService(
        id: id,
        name: (d['name'] as String?) ?? '—',
        durationMinutes: (d['duration_minutes'] as int?) ?? 30,
        priceCents: (d['price_cents'] as int?) ?? 0,
        active: (d['active'] as bool?) ?? true,
      );
}

/// One weekday's opening template. `weekday` is 0 = Mon … 6 = Sun.
class DayHours {
  DayHours({
    required this.weekday,
    required this.openTime,
    required this.closeTime,
    this.breakStart,
    this.breakEnd,
    this.slotMinutes = 30,
    this.closed = false,
  });

  final int weekday;
  final String openTime;
  final String closeTime;
  final String? breakStart;
  final String? breakEnd;
  final int slotMinutes;
  final bool closed;

  bool get hasBreak =>
      (breakStart?.isNotEmpty ?? false) && (breakEnd?.isNotEmpty ?? false);

  static const names = [
    'Montag',
    'Dienstag',
    'Mittwoch',
    'Donnerstag',
    'Freitag',
    'Samstag',
    'Sonntag',
  ];

  String get name => names[weekday.clamp(0, 6)];

  DayHours copyWith({
    String? openTime,
    String? closeTime,
    String? breakStart,
    String? breakEnd,
    int? slotMinutes,
    bool? closed,
  }) =>
      DayHours(
        weekday: weekday,
        openTime: openTime ?? this.openTime,
        closeTime: closeTime ?? this.closeTime,
        breakStart: breakStart ?? this.breakStart,
        breakEnd: breakEnd ?? this.breakEnd,
        slotMinutes: slotMinutes ?? this.slotMinutes,
        closed: closed ?? this.closed,
      );

  Map<String, dynamic> toRow() => {
        'weekday': weekday,
        'open_time': openTime,
        'close_time': closeTime,
        'break_start': breakStart ?? '',
        'break_end': breakEnd ?? '',
        'slot_minutes': slotMinutes,
        'closed': closed,
      };

  factory DayHours.fromRow(Map<String, dynamic> d) => DayHours(
        weekday: (d['weekday'] as int?) ?? 0,
        openTime: (d['open_time'] as String?) ?? '09:00',
        closeTime: (d['close_time'] as String?) ?? '18:00',
        breakStart: (d['break_start'] as String?)?.trim().isEmpty ?? true
            ? null
            : (d['break_start'] as String).trim(),
        breakEnd: (d['break_end'] as String?)?.trim().isEmpty ?? true
            ? null
            : (d['break_end'] as String).trim(),
        slotMinutes: (d['slot_minutes'] as int?) ?? 30,
        closed: (d['closed'] as bool?) ?? false,
      );

  factory DayHours.closedOn(int weekday) => DayHours(
        weekday: weekday,
        openTime: '09:00',
        closeTime: '18:00',
        closed: true,
      );
}

/// A holiday, a sick day, or an hour blocked off for the dentist.
class Closure {
  Closure({
    required this.id,
    required this.startsAt,
    required this.endsAt,
    this.reason,
    this.allDay = false,
    this.resourceId,
  });

  final String id;
  final DateTime startsAt;
  final DateTime endsAt;
  final String? reason;
  final bool allDay;

  /// Which chair is blocked. Null means the whole shop — the difference
  /// between "closed Monday" and "Ali is on holiday".
  final String? resourceId;

  bool get isShopWide => resourceId == null;

  String get label =>
      reason?.trim().isNotEmpty == true ? reason!.trim() : 'Geschlossen';

  String get rangeLabel => allDay
      ? 'Ganzer Tag'
      : '${ShopTime.timeLabel(startsAt)} – ${ShopTime.timeLabel(endsAt)}';

  factory Closure.fromRow(Map<String, dynamic> d, String id) => Closure(
        id: id,
        startsAt: DateTime.parse(d['starts_at'] as String).toUtc(),
        endsAt: DateTime.parse(d['ends_at'] as String).toUtc(),
        reason: d['reason'] as String?,
        allDay: (d['all_day'] as bool?) ?? false,
        resourceId: _emptyToNull(d['resource_id'] as String?),
      );
}

/// The booking rules, editable from the panel so changing them needs no app
/// release.
class ShopSettings {
  ShopSettings({
    this.timezone = 'Europe/Berlin',
    this.bufferMinutes = 0,
    this.leadTimeMinutes = 30,
    this.cancelCutoffHours = 12,
    this.maxAdvanceDays = 30,
    this.maxOpenPerPhone = 3,
  });

  final String timezone;

  /// Turnaround wedged after every appointment.
  final int bufferMinutes;

  /// How soon before a slot it may still be booked online.
  final int leadTimeMinutes;

  /// How late a customer may still cancel or move a booking themselves.
  final int cancelCutoffHours;

  /// How far ahead the calendar opens.
  final int maxAdvanceDays;

  /// Cap on live bookings per phone number.
  final int maxOpenPerPhone;

  ShopSettings copyWith({
    int? bufferMinutes,
    int? leadTimeMinutes,
    int? cancelCutoffHours,
    int? maxAdvanceDays,
    int? maxOpenPerPhone,
  }) =>
      ShopSettings(
        timezone: timezone,
        bufferMinutes: bufferMinutes ?? this.bufferMinutes,
        leadTimeMinutes: leadTimeMinutes ?? this.leadTimeMinutes,
        cancelCutoffHours: cancelCutoffHours ?? this.cancelCutoffHours,
        maxAdvanceDays: maxAdvanceDays ?? this.maxAdvanceDays,
        maxOpenPerPhone: maxOpenPerPhone ?? this.maxOpenPerPhone,
      );

  Map<String, dynamic> toRow() => {
        'timezone': timezone,
        'buffer_minutes': bufferMinutes,
        'lead_time_minutes': leadTimeMinutes,
        'cancel_cutoff_hours': cancelCutoffHours,
        'max_advance_days': maxAdvanceDays,
        'max_open_per_phone': maxOpenPerPhone,
      };

  factory ShopSettings.fromRow(Map<String, dynamic> d) => ShopSettings(
        timezone: (d['timezone'] as String?) ?? 'Europe/Berlin',
        bufferMinutes: (d['buffer_minutes'] as int?) ?? 0,
        leadTimeMinutes: (d['lead_time_minutes'] as int?) ?? 30,
        cancelCutoffHours: (d['cancel_cutoff_hours'] as int?) ?? 12,
        maxAdvanceDays: (d['max_advance_days'] as int?) ?? 30,
        maxOpenPerPhone: (d['max_open_per_phone'] as int?) ?? 3,
      );
}

/// What the shop made, and is owed, on one day.
class DayTotals {
  DayTotals({
    required this.total,
    required this.upcoming,
    required this.completed,
    required this.noShows,
    required this.cancelled,
    required this.expectedCents,
    required this.paidCents,
  });

  final int total;
  final int upcoming;
  final int completed;
  final int noShows;
  final int cancelled;

  /// Price of everything still standing, less loyalty discounts.
  final int expectedCents;

  /// What Stripe has actually confirmed.
  final int paidCents;

  int get outstandingCents => (expectedCents - paidCents).clamp(0, 1 << 31);

  factory DayTotals.from(
    List<StaffAppointment> appts,
    Map<String, ShopService> services,
    DateTime now,
  ) {
    var upcoming = 0, completed = 0, noShows = 0, cancelled = 0;
    var expected = 0, paid = 0;

    for (final a in appts) {
      switch (a.status) {
        case ApptStatus.cancelled:
          cancelled++;
          continue; // a cancelled booking is neither owed nor counted
        case ApptStatus.completed:
          completed++;
        case ApptStatus.noShow:
          noShows++;
        case ApptStatus.confirmed:
          if (a.isUpcoming(now)) upcoming++;
      }
      // A no-show owes nothing; everything else does.
      if (a.status != ApptStatus.noShow) {
        final price = services[a.serviceId]?.priceCents ?? 0;
        expected += (price - a.discountCents).clamp(0, 1 << 31);
      }
      paid += a.paymentAmountCents;
    }

    return DayTotals(
      total: appts.length,
      upcoming: upcoming,
      completed: completed,
      noShows: noShows,
      cancelled: cancelled,
      expectedCents: expected,
      paidCents: paid,
    );
  }
}
