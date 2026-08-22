// Plain-data models for the customer app.
//
// These now mirror the booking API's JSON rather than raw Appwrite rows: the
// app no longer reads the appointments table, so the row shape is none of its
// business. Note what is missing compared with before — no manage-token hash,
// no Stripe handles, no other customer's anything. The server decides what a
// customer may see, and this is the shape of that answer.

import '../../core/shop_time.dart';

class Service {
  Service({
    required this.id,
    required this.name,
    required this.durationMinutes,
    required this.priceCents,
    this.description,
    this.displayOrder = 100,
  });

  final String id;
  final String name;
  final String? description;
  final int durationMinutes;
  final int priceCents;
  final int displayOrder;

  double get price => priceCents / 100;
  String get priceLabel => '€${(priceCents / 100).toStringAsFixed(2)}';

  factory Service.fromJson(Map<String, dynamic> j) => Service(
        id: j['id'] as String,
        name: j['name'] as String,
        description: j['description'] as String?,
        durationMinutes: (j['durationMinutes'] as num).toInt(),
        priceCents: (j['priceCents'] as num).toInt(),
        displayOrder: (j['displayOrder'] as num?)?.toInt() ?? 100,
      );
}

/// A bookable slot, as decided by the server.
///
/// [label] is the shop's own wall clock, computed server-side — the app renders
/// it verbatim rather than reformatting [start] through the device's timezone,
/// which is what used to shift every displayed time by an hour for half the
/// year and for anyone travelling.
class Slot {
  Slot({required this.start, required this.end, required this.label});

  final DateTime start;
  final DateTime end;
  final String label;

  factory Slot.fromJson(Map<String, dynamic> j) => Slot(
        start: DateTime.parse(j['start'] as String).toUtc(),
        end: DateTime.parse(j['end'] as String).toUtc(),
        label: j['label'] as String,
      );

  @override
  bool operator ==(Object other) => other is Slot && other.start == start;

  @override
  int get hashCode => start.hashCode;
}

enum AppointmentStatus { confirmed, cancelled, completed, noShow }

extension AppointmentStatusX on AppointmentStatus {
  String get wire => switch (this) {
        AppointmentStatus.confirmed => 'confirmed',
        AppointmentStatus.cancelled => 'cancelled',
        AppointmentStatus.completed => 'completed',
        AppointmentStatus.noShow => 'no_show',
      };

  static AppointmentStatus fromWire(String? s) => switch (s) {
        'cancelled' => AppointmentStatus.cancelled,
        'completed' => AppointmentStatus.completed,
        'no_show' => AppointmentStatus.noShow,
        _ => AppointmentStatus.confirmed,
      };
}

class Appointment {
  Appointment({
    required this.id,
    required this.customerName,
    required this.customerPhone,
    required this.serviceId,
    required this.serviceName,
    required this.startAt,
    required this.endAt,
    required this.status,
    required this.startLabel,
    required this.dateKey,
    this.notes,
    this.paid = false,
    this.paymentAmountCents = 0,
    this.discountCents = 0,
  });

  final String id;
  final String customerName;
  final String customerPhone;
  final String serviceId;
  final String serviceName;

  /// UTC instants. Render through [startLabel] or [ShopTime], never
  /// `toLocal()` — the shop's clock is the one that matters.
  final DateTime startAt;
  final DateTime endAt;

  final AppointmentStatus status;

  /// "HH:mm" on the shop's clock, as the server rendered it.
  final String startLabel;

  /// "YYYY-MM-DD" of the shop-local day.
  final String dateKey;

  final String? notes;

  /// Written only by the Stripe webhook after money actually arrives. The app
  /// can read this; it can no longer set it.
  final bool paid;
  final int paymentAmountCents;

  /// Loyalty discount applied to this booking, in cents.
  final int discountCents;

  bool get rewardRedeemed => discountCents > 0;
  bool get isCancelled => status == AppointmentStatus.cancelled;
  bool isUpcoming(DateTime now) => !isCancelled && endAt.isAfter(now);

  String get endLabel => ShopTime.timeLabel(endAt);

  /// "Fr, 21.08. um 10:00 Uhr" — the shop's day and the shop's clock.
  String get whenLabel {
    final w = ShopTime.toShopWall(startAt);
    const days = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];
    final weekday = days[(w.weekday - 1).clamp(0, 6)];
    return '$weekday, ${w.day.toString().padLeft(2, '0')}.'
        '${w.month.toString().padLeft(2, '0')}. um $startLabel Uhr';
  }

  factory Appointment.fromJson(Map<String, dynamic> j) => Appointment(
        id: j['id'] as String,
        customerName: (j['customerName'] as String?) ?? '',
        customerPhone: (j['customerPhone'] as String?) ?? '',
        serviceId: (j['serviceId'] as String?) ?? '',
        serviceName: (j['serviceName'] as String?) ?? '',
        startAt: DateTime.parse(j['startAt'] as String).toUtc(),
        endAt: DateTime.parse(j['endAt'] as String).toUtc(),
        status: AppointmentStatusX.fromWire(j['status'] as String?),
        startLabel: (j['startLabel'] as String?) ??
            ShopTime.timeLabel(DateTime.parse(j['startAt'] as String).toUtc()),
        dateKey: (j['dateKey'] as String?) ??
            ShopTime.dateKey(DateTime.parse(j['startAt'] as String).toUtc()),
        notes: j['notes'] as String?,
        paid: (j['paid'] as bool?) ?? false,
        paymentAmountCents: (j['paymentAmountCents'] as num?)?.toInt() ?? 0,
        discountCents: (j['discountCents'] as num?)?.toInt() ?? 0,
      );
}

/// Opening hours, for display only. Availability is computed on the server.
class BusinessHours {
  BusinessHours({
    required this.weekday,
    required this.openTime,
    required this.closeTime,
    this.breakStart,
    this.breakEnd,
    this.closed = false,
  });

  final int weekday; // 0 = Mon … 6 = Sun
  final String openTime;
  final String closeTime;
  final String? breakStart;
  final String? breakEnd;
  final bool closed;

  bool get hasBreak =>
      (breakStart?.isNotEmpty ?? false) && (breakEnd?.isNotEmpty ?? false);

  factory BusinessHours.fromJson(Map<String, dynamic> j) => BusinessHours(
        weekday: (j['weekday'] as num).toInt(),
        openTime: (j['openTime'] as String?) ?? '09:00',
        closeTime: (j['closeTime'] as String?) ?? '18:00',
        breakStart: j['breakStart'] as String?,
        breakEnd: j['breakEnd'] as String?,
        closed: (j['closed'] as bool?) ?? false,
      );
}

/// The booking rules, so the app can explain them instead of letting the
/// customer discover them by being refused.
class BookingRules {
  BookingRules({
    this.timezone = 'Europe/Berlin',
    this.cancelCutoffHours = 12,
    this.maxAdvanceDays = 30,
    this.leadTimeMinutes = 30,
  });

  final String timezone;
  final int cancelCutoffHours;
  final int maxAdvanceDays;
  final int leadTimeMinutes;

  factory BookingRules.fromJson(Map<String, dynamic> j) => BookingRules(
        timezone: (j['timezone'] as String?) ?? 'Europe/Berlin',
        cancelCutoffHours: (j['cancelCutoffHours'] as num?)?.toInt() ?? 12,
        maxAdvanceDays: (j['maxAdvanceDays'] as num?)?.toInt() ?? 30,
        leadTimeMinutes: (j['leadTimeMinutes'] as num?)?.toInt() ?? 30,
      );
}

class CatalogResult {
  CatalogResult({
    required this.services,
    required this.hours,
    required this.rules,
    required this.stampsPerReward,
  });

  final List<Service> services;
  final List<BusinessHours> hours;
  final BookingRules rules;
  final int stampsPerReward;

  factory CatalogResult.fromJson(Map<String, dynamic> j) => CatalogResult(
        services: (j['services'] as List<dynamic>)
            .map((s) => Service.fromJson(s as Map<String, dynamic>))
            .toList(growable: false),
        hours: ((j['hours'] as List<dynamic>?) ?? const [])
            .map((h) => BusinessHours.fromJson(h as Map<String, dynamic>))
            .toList(growable: false),
        rules: BookingRules.fromJson(
            (j['settings'] as Map<String, dynamic>?) ?? const {}),
        stampsPerReward: ((j['loyalty']
                    as Map<String, dynamic>?)?['stampsPerReward'] as num?)
                ?.toInt() ??
            10,
      );
}

/// A customer's stamp card.
///
/// Computed on the server from booking history — the client used to derive it
/// locally *and* was able to write the discount that spends it, which meant a
/// free cut for anyone willing to send one HTTP request. The numbers here are
/// for display; the entitlement is re-checked server-side on every redemption.
class LoyaltyCard {
  LoyaltyCard({
    required this.stamps,
    required this.stampsPerReward,
    required this.rewardsRedeemed,
    required this.rewardsEarned,
    required this.rewardsAvailable,
    required this.filled,
  });

  final int stamps;
  final int stampsPerReward;
  final int rewardsRedeemed;
  final int rewardsEarned;
  final int rewardsAvailable;

  /// Filled slots on the current card (0..stampsPerReward).
  final int filled;

  bool get hasReward => rewardsAvailable > 0;

  /// Visits still needed for the next free cut (0 when one is ready).
  int get untilNext => hasReward ? 0 : stampsPerReward - filled;

  factory LoyaltyCard.fromJson(Map<String, dynamic> j) => LoyaltyCard(
        stamps: (j['stamps'] as num?)?.toInt() ?? 0,
        stampsPerReward: (j['stampsPerReward'] as num?)?.toInt() ?? 10,
        rewardsRedeemed: (j['rewardsRedeemed'] as num?)?.toInt() ?? 0,
        rewardsEarned: (j['rewardsEarned'] as num?)?.toInt() ?? 0,
        rewardsAvailable: (j['rewardsAvailable'] as num?)?.toInt() ?? 0,
        filled: (j['filled'] as num?)?.toInt() ?? 0,
      );
}

class MyBookings {
  MyBookings({
    required this.appointments,
    this.loyalty,
    this.verifiedPhone,
  });

  final List<Appointment> appointments;

  /// Only present once a phone number has been verified: a card derived from
  /// the handful of tokens on one device would under-count and mislead.
  final LoyaltyCard? loyalty;

  final String? verifiedPhone;

  factory MyBookings.fromJson(Map<String, dynamic> j) => MyBookings(
        appointments: ((j['appointments'] as List<dynamic>?) ?? const [])
            .map((a) => Appointment.fromJson(a as Map<String, dynamic>))
            .toList(growable: false),
        loyalty: j['loyalty'] == null
            ? null
            : LoyaltyCard.fromJson(j['loyalty'] as Map<String, dynamic>),
        verifiedPhone: j['verifiedPhone'] as String?,
      );
}
