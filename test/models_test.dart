import 'package:babassam/customer/data/models.dart' as customer;
import 'package:babassam/staff/data/models.dart' as staff;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('customer Appointment', () {
    Map<String, dynamic> json({Map<String, dynamic> overrides = const {}}) => {
          'id': 'a1',
          'customerName': 'Sami',
          'customerPhone': '+491761234567',
          'serviceId': 'cut',
          'serviceName': 'Haarschnitt',
          'startAt': '2026-07-15T07:00:00.000Z',
          'endAt': '2026-07-15T07:30:00.000Z',
          'startLabel': '09:00',
          'dateKey': '2026-07-15',
          'status': 'confirmed',
          'paid': false,
          'paymentAmountCents': 0,
          'discountCents': 0,
          ...overrides,
        };

    test('parses the API shape and keeps instants in UTC', () {
      final a = customer.Appointment.fromJson(json());
      expect(a.id, 'a1');
      expect(a.startAt.isUtc, isTrue);
      expect(a.startLabel, '09:00');
      expect(a.paid, isFalse);
    });

    test('falls back to computing the label if the server omitted it', () {
      final a =
          customer.Appointment.fromJson(json(overrides: {'startLabel': null}));
      // 07:00Z in July is 09:00 in the shop.
      expect(a.startLabel, '09:00');
    });

    test('whenLabel reads as the shop\'s day and clock', () {
      final a = customer.Appointment.fromJson(json());
      expect(a.whenLabel, 'Mi, 15.07. um 09:00 Uhr');
    });

    test('a discount marks the booking as a spent reward', () {
      expect(customer.Appointment.fromJson(json()).rewardRedeemed, isFalse);
      expect(
        customer.Appointment.fromJson(json(overrides: {'discountCents': 2500}))
            .rewardRedeemed,
        isTrue,
      );
    });

    test('cancelled bookings are never upcoming', () {
      final a = customer.Appointment.fromJson(
          json(overrides: {'status': 'cancelled'}));
      expect(a.isCancelled, isTrue);
      expect(a.isUpcoming(DateTime.utc(2026, 7, 1)), isFalse);
    });
  });

  group('customer LoyaltyCard', () {
    test('parses the server-computed card', () {
      final c = customer.LoyaltyCard.fromJson({
        'stamps': 12,
        'stampsPerReward': 10,
        'rewardsRedeemed': 0,
        'rewardsEarned': 1,
        'rewardsAvailable': 1,
        'filled': 10,
      });
      expect(c.hasReward, isTrue);
      expect(c.untilNext, 0);
    });

    test('reports how many visits remain when no reward is ready', () {
      final c = customer.LoyaltyCard.fromJson({
        'stamps': 3,
        'stampsPerReward': 10,
        'rewardsRedeemed': 0,
        'rewardsEarned': 0,
        'rewardsAvailable': 0,
        'filled': 3,
      });
      expect(c.hasReward, isFalse);
      expect(c.untilNext, 7);
    });
  });

  group('staff DayTotals', () {
    staff.StaffAppointment appt({
      required String id,
      required staff.ApptStatus status,
      int hourUtc = 7,
      int paidCents = 0,
      int discountCents = 0,
    }) =>
        staff.StaffAppointment(
          id: id,
          customerName: 'X',
          customerPhone: '+49123456789',
          serviceId: 'cut',
          serviceName: 'Haarschnitt',
          startAt: DateTime.utc(2026, 7, 15, hourUtc),
          endAt: DateTime.utc(2026, 7, 15, hourUtc, 30),
          status: status,
          source: staff.ApptSource.online,
          paid: paidCents > 0,
          paymentAmountCents: paidCents,
          discountCents: discountCents,
        );

    final services = {
      'cut': staff.ShopService(
          id: 'cut',
          name: 'Haarschnitt',
          durationMinutes: 30,
          priceCents: 2500),
    };

    test('counts each state and sums what the day is worth', () {
      final now = DateTime.utc(2026, 7, 15, 12);
      final totals = staff.DayTotals.from([
        appt(id: '1', status: staff.ApptStatus.completed, paidCents: 2500),
        appt(id: '2', status: staff.ApptStatus.completed, hourUtc: 8),
        appt(id: '3', status: staff.ApptStatus.confirmed, hourUtc: 14),
      ], services, now);

      expect(totals.total, 3);
      expect(totals.completed, 2);
      expect(totals.upcoming, 1);
      expect(totals.expectedCents, 7500);
      expect(totals.paidCents, 2500);
      expect(totals.outstandingCents, 5000);
    });

    test('a cancelled booking is owed nothing and counted separately', () {
      final totals = staff.DayTotals.from([
        appt(id: '1', status: staff.ApptStatus.cancelled),
      ], services, DateTime.utc(2026, 7, 15, 12));

      expect(totals.cancelled, 1);
      expect(totals.expectedCents, 0);
    });

    test('a no-show owes nothing either', () {
      final totals = staff.DayTotals.from([
        appt(id: '1', status: staff.ApptStatus.noShow),
      ], services, DateTime.utc(2026, 7, 15, 12));

      expect(totals.noShows, 1);
      expect(totals.expectedCents, 0);
    });

    test('a redeemed loyalty reward reduces what is owed', () {
      final totals = staff.DayTotals.from([
        appt(
            id: '1',
            status: staff.ApptStatus.confirmed,
            hourUtc: 14,
            discountCents: 2500),
      ], services, DateTime.utc(2026, 7, 15, 12));

      expect(totals.expectedCents, 0);
      expect(totals.outstandingCents, 0);
    });
  });

  group('staff appointment rows', () {
    test('parses a row and renders the shop\'s clock', () {
      final a = staff.StaffAppointment.fromRow({
        'customer_name': 'Sami',
        'customer_phone': '+491761234567',
        'service_id': 'cut',
        'service_name': 'Haarschnitt',
        'start_at': '2026-07-15T07:00:00.000Z',
        'end_at': '2026-07-15T07:30:00.000Z',
        'status': 'confirmed',
        'source': 'walkin',
        'paid': true,
        'payment_amount_cents': 2500,
        'discount_cents': 0,
      }, 'row1');

      expect(a.id, 'row1');
      expect(a.timeRangeLabel, '09:00 – 09:30');
      expect(a.source, staff.ApptSource.walkin);
      expect(a.duration, const Duration(minutes: 30));
      expect(a.hasRealPhone, isTrue);
    });

    test('a walk-in without a number is not treated as having one', () {
      final a = staff.StaffAppointment.fromRow({
        'customer_name': 'Laufkundschaft',
        'customer_phone': '-',
        'service_id': 'cut',
        'service_name': 'Haarschnitt',
        'start_at': '2026-07-15T07:00:00.000Z',
        'end_at': '2026-07-15T07:30:00.000Z',
        'status': 'confirmed',
        'source': 'walkin',
      }, 'row2');
      expect(a.hasRealPhone, isFalse);
    });

    test('a past confirmed booking is the one staff must close out', () {
      final a = staff.StaffAppointment.fromRow({
        'customer_name': 'Sami',
        'customer_phone': '+49176',
        'service_id': 'cut',
        'service_name': 'Haarschnitt',
        'start_at': '2026-07-15T07:00:00.000Z',
        'end_at': '2026-07-15T07:30:00.000Z',
        'status': 'confirmed',
      }, 'row3');

      expect(a.needsClosing(DateTime.utc(2026, 7, 15, 12)), isTrue);
      expect(a.needsClosing(DateTime.utc(2026, 7, 15, 6)), isFalse);
      expect(a.isUpcoming(DateTime.utc(2026, 7, 15, 6)), isTrue);
    });
  });

  group('staff DayHours', () {
    test('round-trips through the row shape', () {
      final d = staff.DayHours(
        weekday: 4,
        openTime: '09:00',
        closeTime: '18:00',
        breakStart: '12:00',
        breakEnd: '13:00',
        slotMinutes: 30,
        closed: false,
      );
      final back = staff.DayHours.fromRow(d.toRow());
      expect(back.openTime, '09:00');
      expect(back.hasBreak, isTrue);
      expect(back.name, 'Freitag');
    });

    test('empty break strings mean no break, not an empty one', () {
      final d = staff.DayHours.fromRow({
        'weekday': 0,
        'open_time': '09:00',
        'close_time': '18:00',
        'break_start': '',
        'break_end': '',
      });
      expect(d.hasBreak, isFalse);
      expect(d.breakStart, isNull);
    });
  });
}
