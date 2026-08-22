import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/shop_time.dart';
import '../data/booking_api.dart';
import '../data/models.dart';

/// Drives the reschedule page: same service, new day and time.
///
/// Availability comes from the same server endpoint the booking grid uses, and
/// the server excludes the appointment being moved from its own conflict check
/// — so its current slot stays offered and moving a booking onto itself is a
/// harmless no-op rather than a "slot taken" refusal.
class RescheduleController extends GetxController {
  RescheduleController({
    required this.original,
    required String auth,
    required BookingApi api,
  })  : _auth = auth,
        _api = api;

  final Appointment original;
  final String _auth;
  final BookingApi _api;

  final loadingSlots = false.obs;
  final submitting = false.obs;
  final emptyReason = RxnString();

  late final Rx<DateTime> selectedDate =
      Rx<DateTime>(ShopTime.startOfShopDay(original.startAt));
  final selectedSlot = Rxn<Slot>();
  final slots = <Slot>[].obs;

  final rules = Rx<BookingRules>(BookingRules());

  /// Opening hours by weekday (0 = Mon … 6 = Sun), for the date strip.
  final hours = <int, BusinessHours>{}.obs;

  bool get canSubmit =>
      !submitting.value &&
      selectedSlot.value != null &&
      selectedSlot.value!.start != original.startAt;

  List<DateTime> get dateStrip {
    final days = rules.value.maxAdvanceDays.clamp(1, 14);
    final today = ShopTime.startOfShopDay(DateTime.now().toUtc());
    return List.generate(days, (i) {
      final wall = ShopTime.toShopWall(today.add(Duration(days: i, hours: 12)));
      return ShopTime.fromShopWall(wall.year, wall.month, wall.day);
    });
  }

  @override
  void onInit() {
    super.onInit();
    _bootstrap();
    ever<DateTime>(selectedDate, (_) => _refreshSlots());
  }

  Future<void> _bootstrap() async {
    try {
      final catalog = await _api.catalog();
      rules.value = catalog.rules;
      hours.assignAll({for (final h in catalog.hours) h.weekday: h});
    } catch (e) {
      debugPrint('[RescheduleController._bootstrap] $e');
    }
    await _refreshSlots();
  }

  void pickDate(DateTime d) {
    selectedDate.value = ShopTime.startOfShopDay(d.toUtc());
    selectedSlot.value = null;
  }

  void pickSlot(Slot slot) {
    selectedSlot.value = slot;
    update();
  }

  Future<void> _refreshSlots() async {
    loadingSlots.value = true;
    try {
      final fresh = await _api.availability(
        serviceId: original.serviceId,
        dateKey: ShopTime.dateKey(selectedDate.value),
      );
      slots.assignAll(fresh);
      emptyReason.value = fresh.isEmpty
          ? 'An diesem Tag ist nichts frei. Bitte einen anderen Tag wählen.'
          : null;

      final picked = selectedSlot.value;
      if (picked != null && !fresh.any((s) => s.start == picked.start)) {
        selectedSlot.value = null;
      }
    } on BookingException catch (e) {
      slots.clear();
      emptyReason.value = e.message;
    } catch (e, st) {
      debugPrint('[RescheduleController._refreshSlots] $e');
      debugPrintStack(
          stackTrace: st, label: 'RescheduleController._refreshSlots');
      slots.clear();
      emptyReason.value = 'Uhrzeiten konnten nicht geladen werden.';
    } finally {
      loadingSlots.value = false;
    }
  }

  Future<Appointment?> submit() async {
    if (!canSubmit) return null;
    submitting.value = true;
    try {
      return await _api.reschedule(
        appointmentId: original.id,
        auth: _auth,
        start: selectedSlot.value!.start,
      );
    } on BookingException catch (e) {
      if (e.isSlotGone) await _refreshSlots();
      Get.snackbar(
        e.isTooLate ? 'Zu kurzfristig' : 'Verschieben fehlgeschlagen',
        e.message,
        snackPosition: SnackPosition.BOTTOM,
      );
      return null;
    } catch (e, st) {
      debugPrint('[RescheduleController.submit] $e');
      debugPrintStack(stackTrace: st, label: 'RescheduleController.submit');
      Get.snackbar('Verschieben fehlgeschlagen',
          'Termin konnte nicht verschoben werden.',
          snackPosition: SnackPosition.BOTTOM);
      return null;
    } finally {
      submitting.value = false;
    }
  }
}
