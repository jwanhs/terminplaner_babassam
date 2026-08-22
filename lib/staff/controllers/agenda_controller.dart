import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import '../../core/shop_time.dart';
import '../data/models.dart';
import '../data/staff_repository.dart';

/// Drives the day view — the screen the shop actually runs on.
///
/// Everything is anchored to the *shop's* day, not the device's: [selectedDay]
/// is an instant at shop-local midnight, so an owner checking tomorrow's diary
/// from another timezone sees the shop's tomorrow.
class AgendaController extends GetxController {
  AgendaController(this._repo);

  final StaffRepository _repo;

  final loading = false.obs;
  final refreshing = false.obs;
  final errorText = RxnString();

  final selectedDay =
      Rx<DateTime>(ShopTime.startOfShopDay(DateTime.now().toUtc()));
  final appointments = <StaffAppointment>[].obs;
  final closures = <Closure>[].obs;
  final services = <ShopService>[].obs;
  final settings = Rx<ShopSettings>(ShopSettings());

  /// The shop's chairs. Empty is the ordinary state of a one-chair shop, and
  /// the panel shows nothing about chairs at all in that case — a solo barber
  /// should not have to look past a column header to read their day.
  final chairs = <Chair>[].obs;

  /// Wall-clock mismatch between this device and the shop, surfaced as a
  /// banner rather than silently corrected — staff should know their phone
  /// disagrees with the till.
  final deviceTimezoneWarning = false.obs;

  Timer? _poll;

  Map<String, ShopService> get servicesById =>
      {for (final s in services) s.id: s};

  /// Whether anything in the panel should mention chairs at all.
  bool get hasChairs => chairs.length > 1;

  /// The chair's name for display. Falls back to the first chair, which is how
  /// the booking API reads a row with no chair recorded — the panel must agree
  /// with it or staff will be told a booking is somewhere it is not.
  String chairNameFor(String? id) {
    if (chairs.isEmpty) return '';
    for (final chair in chairs) {
      if (chair.id == id) return chair.name;
    }
    return chairs.first.name;
  }

  DayTotals get totals =>
      DayTotals.from(appointments, servicesById, DateTime.now().toUtc());

  bool get isToday =>
      ShopTime.dateKey(selectedDay.value) ==
      ShopTime.dateKey(DateTime.now().toUtc());

  String get dayLabel {
    final w = ShopTime.toShopWall(selectedDay.value);
    final weekday = DayHours.names[(w.weekday - 1).clamp(0, 6)];
    return '$weekday, ${w.day.toString().padLeft(2, '0')}.'
        '${w.month.toString().padLeft(2, '0')}.${w.year}';
  }

  /// Closures overlapping the selected day.
  List<Closure> get closuresToday {
    final start = selectedDay.value;
    final end = start.add(const Duration(days: 1));
    return closures
        .where((c) => c.startsAt.isBefore(end) && c.endsAt.isAfter(start))
        .toList(growable: false);
  }

  @override
  void onInit() {
    super.onInit();
    deviceTimezoneWarning.value = ShopTime.deviceDisagrees(DateTime.now());
    _bootstrap();
    // A shop panel is left open on a counter all day. Polling keeps it honest
    // about bookings taken online in the meantime without the reconnect
    // storms the realtime channel caused on older Appwrite servers.
    _poll = Timer.periodic(
        const Duration(seconds: 45), (_) => reload(silent: true));
  }

  @override
  void onClose() {
    _poll?.cancel();
    super.onClose();
  }

  Future<void> _bootstrap() async {
    loading.value = true;
    try {
      final results = await Future.wait([
        _repo.services(),
        _repo.settings(),
        _repo.appointmentsForDay(selectedDay.value),
        _repo.closures(),
        _repo.chairs(),
      ]);
      services.assignAll(results[0] as List<ShopService>);
      settings.value = results[1] as ShopSettings;
      appointments.assignAll(results[2] as List<StaffAppointment>);
      closures.assignAll(results[3] as List<Closure>);
      chairs.assignAll(results[4] as List<Chair>);
      errorText.value = null;
    } catch (e, st) {
      debugPrint('[Agenda._bootstrap] $e');
      debugPrintStack(stackTrace: st, label: 'Agenda._bootstrap');
      errorText.value = 'Termine konnten nicht geladen werden.';
    } finally {
      loading.value = false;
    }
  }

  /// Reload the selected day. [silent] is the background poll: it must not
  /// flash a spinner over a panel someone is reading.
  ///
  /// Deliberately not called `refresh` — GetxController already has one, and
  /// overriding it would replace the notify-listeners behaviour GetBuilder
  /// depends on.
  Future<void> reload({bool silent = false}) async {
    if (!silent) refreshing.value = true;
    try {
      final results = await Future.wait([
        _repo.appointmentsForDay(selectedDay.value),
        _repo.closures(),
      ]);
      appointments.assignAll(results[0] as List<StaffAppointment>);
      closures.assignAll(results[1] as List<Closure>);
      errorText.value = null;
    } catch (e, st) {
      debugPrint('[Agenda.reload] $e');
      if (!silent) {
        debugPrintStack(stackTrace: st, label: 'Agenda.reload');
        errorText.value = 'Aktualisieren fehlgeschlagen.';
      }
    } finally {
      refreshing.value = false;
    }
  }

  void goToDay(DateTime day) {
    selectedDay.value = ShopTime.startOfShopDay(day.toUtc());
    reload();
  }

  void previousDay() =>
      goToDay(selectedDay.value.subtract(const Duration(hours: 23)));
  void nextDay() => goToDay(selectedDay.value.add(const Duration(hours: 25)));
  void goToToday() => goToDay(DateTime.now().toUtc());

  // ─── actions ───────────────────────────────────────────────────────────────

  Future<void> setStatus(StaffAppointment appt, ApptStatus status) =>
      _mutate(() => _repo.setStatus(appt.id, status));

  Future<void> markPaidInPerson(StaffAppointment appt) {
    final price = servicesById[appt.serviceId]?.priceCents ?? 0;
    final due = (price - appt.discountCents).clamp(0, 1 << 31);
    return _mutate(() => _repo.markPaidInPerson(id: appt.id, amountCents: due));
  }

  Future<void> reschedule(StaffAppointment appt, DateTime startAt) =>
      _mutate(() => _repo.reschedule(
            id: appt.id,
            startAt: startAt,
            duration: appt.duration,
          ));

  Future<void> addWalkIn({
    required ShopService service,
    required DateTime startAt,
    required String name,
    String phone = '',
    String? notes,
    String? chairId,
  }) =>
      _mutate(() => _repo.createWalkIn(
            service: service,
            startAt: startAt,
            customerName: name,
            customerPhone: phone,
            notes: notes,
            chairId: chairId,
          ));

  Future<void> blockOff({
    required DateTime startsAt,
    required DateTime endsAt,
    String? reason,
    bool allDay = false,
    String? chairId,
  }) async {
    try {
      await _repo.createClosure(
        startsAt: startsAt,
        endsAt: endsAt,
        reason: reason,
        allDay: allDay,
        chairId: chairId,
      );
      await reload();
    } catch (e, st) {
      debugPrint('[Agenda.blockOff] $e');
      debugPrintStack(stackTrace: st, label: 'Agenda.blockOff');
      errorText.value = 'Sperrzeit konnte nicht gespeichert werden.';
      rethrow;
    }
  }

  Future<void> removeClosure(Closure c) async {
    try {
      await _repo.deleteClosure(c.id);
      await reload();
    } catch (e, st) {
      debugPrint('[Agenda.removeClosure] $e');
      debugPrintStack(stackTrace: st, label: 'Agenda.removeClosure');
      errorText.value = 'Sperrzeit konnte nicht entfernt werden.';
    }
  }

  Future<void> saveSettings(ShopSettings s) async {
    await _repo.saveSettings(s);
    settings.value = s;
  }

  Future<void> _mutate(Future<StaffAppointment> Function() action) async {
    try {
      final updated = await action();
      // Patch the row in place so the list does not jump under the finger that
      // just tapped it; the poll will reconcile anything else.
      final i = appointments.indexWhere((a) => a.id == updated.id);
      if (i >= 0) {
        appointments[i] = updated;
      } else {
        await reload();
      }
      errorText.value = null;
    } catch (e, st) {
      debugPrint('[Agenda._mutate] $e');
      debugPrintStack(stackTrace: st, label: 'Agenda._mutate');
      errorText.value = 'Änderung fehlgeschlagen.';
      await reload();
      rethrow;
    }
  }
}
