import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/brand.dart';
import '../../core/shop_time.dart';
import '../data/booking_api.dart';
import '../data/calendar_service.dart';
import '../data/models.dart';
import '../data/payment_service.dart';
import '../data/token_store.dart';
import '../widgets/paid_badge.dart';

/// Drives the single-screen booking page.
///
/// The shape changed with the security work: this no longer computes which
/// slots are free, no longer knows what anything costs at submit time, and no
/// longer writes to the database. It asks the booking API for a day's
/// availability, sends the customer's choice, and stores the manage token that
/// comes back. Everything the old version decided locally — and could
/// therefore be lied to about — is now decided on the server.
class BookingController extends GetxController {
  BookingController({
    required BookingApi api,
    required TokenStore tokens,
    PaymentService? payments,
    CalendarService? calendar,
  })  : _api = api,
        _tokens = tokens,
        _payments = payments ?? PaymentService(api: api),
        _calendar = calendar ?? CalendarService();

  final BookingApi _api;
  final TokenStore _tokens;
  final PaymentService _payments;
  final CalendarService _calendar;

  // ─── loading flags ─────────────────────────────────────────────────────────
  final loadingServices = false.obs;
  final loadingSlots = false.obs;
  final submitting = false.obs;

  // ─── catalogue ─────────────────────────────────────────────────────────────
  final services = <Service>[].obs;
  final rules = Rx<BookingRules>(BookingRules());

  /// Opening hours by weekday (0 = Mon … 6 = Sun), for greying out closed days
  /// in the date strip. Display only — what is actually bookable is decided by
  /// the server, and a day that looks open can still come back empty.
  final hours = <int, BusinessHours>{}.obs;

  // ─── selection ─────────────────────────────────────────────────────────────
  final selectedServiceId = RxnString();
  final selectedDate =
      Rx<DateTime>(ShopTime.startOfShopDay(DateTime.now().toUtc()));
  final selectedSlot = Rxn<Slot>();
  final slots = <Slot>[].obs;

  /// Why the grid is empty, when it is — "closed today" and "nothing left
  /// today" are different things and the customer deserves to know which.
  final emptyReason = RxnString();

  // ─── form ──────────────────────────────────────────────────────────────────
  final nameCtl = TextEditingController();
  final phoneCtl = TextEditingController();

  // ─── derived ───────────────────────────────────────────────────────────────
  Service? get selectedService =>
      services.firstWhereOrNull((s) => s.id == selectedServiceId.value);

  bool get canSubmit =>
      !submitting.value &&
      selectedService != null &&
      selectedSlot.value != null &&
      nameCtl.text.trim().length >= 2 &&
      _looksLikePhone(phoneCtl.text);

  /// The next fortnight, capped by how far ahead the shop actually opens its
  /// calendar — asking for a day beyond that just returns an empty grid.
  List<DateTime> get dateStrip {
    final days = rules.value.maxAdvanceDays.clamp(1, 14);
    final today = ShopTime.startOfShopDay(DateTime.now().toUtc());
    return List.generate(days, (i) {
      final wall = ShopTime.toShopWall(today.add(Duration(days: i, hours: 12)));
      return ShopTime.fromShopWall(wall.year, wall.month, wall.day);
    });
  }

  // ─── lifecycle ─────────────────────────────────────────────────────────────

  @override
  void onInit() {
    super.onInit();
    _bootstrap();

    nameCtl.addListener(update);
    phoneCtl.addListener(update);

    ever<String?>(selectedServiceId, (_) => refreshSlots());
    ever<DateTime>(selectedDate, (_) => refreshSlots());
  }

  @override
  void onClose() {
    nameCtl.dispose();
    phoneCtl.dispose();
    super.onClose();
  }

  Future<void> _bootstrap() async {
    loadingServices.value = true;
    try {
      final catalog = await _api.catalog();
      services.assignAll(catalog.services);
      rules.value = catalog.rules;
      hours.assignAll({for (final h in catalog.hours) h.weekday: h});
      if (services.isNotEmpty) {
        selectedServiceId.value = services.first.id;
      } else {
        await refreshSlots();
      }
    } on BookingException catch (e) {
      _snack('Verbindungsproblem', e.message);
    } catch (e, st) {
      debugPrint('[BookingController._bootstrap] $e');
      debugPrintStack(stackTrace: st, label: 'BookingController._bootstrap');
      _snack('Verbindungsproblem',
          'Leistungen konnten nicht geladen werden. Bitte erneut versuchen.');
    } finally {
      loadingServices.value = false;
    }
  }

  void pickService(String id) => selectedServiceId.value = id;

  void pickDate(DateTime d) {
    selectedDate.value = ShopTime.startOfShopDay(d.toUtc());
    selectedSlot.value = null;
  }

  void pickSlot(Slot slot) {
    selectedSlot.value = slot;
    update();
  }

  /// Ask the server what is free. Taken slots are simply absent from the
  /// answer — the app is never told who holds them.
  Future<void> refreshSlots() async {
    final svc = selectedService;
    if (svc == null) {
      slots.clear();
      emptyReason.value = null;
      return;
    }
    loadingSlots.value = true;
    try {
      final fresh = await _api.availability(
        serviceId: svc.id,
        dateKey: ShopTime.dateKey(selectedDate.value),
      );
      slots.assignAll(fresh);
      emptyReason.value = fresh.isEmpty
          ? 'An diesem Tag ist nichts mehr frei. Bitte einen anderen Tag wählen.'
          : null;

      // A slot that vanished between drawing the grid and now was taken by
      // someone else; drop the selection rather than let the customer submit
      // something the server will refuse.
      final picked = selectedSlot.value;
      if (picked != null && !fresh.any((s) => s.start == picked.start)) {
        selectedSlot.value = null;
      }
    } on BookingException catch (e) {
      slots.clear();
      emptyReason.value = e.message;
    } catch (e, st) {
      debugPrint('[BookingController.refreshSlots] $e');
      debugPrintStack(stackTrace: st, label: 'BookingController.refreshSlots');
      slots.clear();
      emptyReason.value = 'Uhrzeiten konnten nicht geladen werden.';
    } finally {
      loadingSlots.value = false;
    }
  }

  Future<void> submit() async {
    if (!canSubmit) return;
    submitting.value = true;
    final svc = selectedService!;
    final slot = selectedSlot.value!;
    try {
      final result = await _api.create(
        serviceId: svc.id,
        start: slot.start,
        name: nameCtl.text.trim(),
        phone: phoneCtl.text.trim(),
      );

      // Persist before anything else can fail: this token is handed over once,
      // and without it the customer cannot manage the booking they just made.
      await _tokens.remember(
        appointmentId: result.appointment.id,
        token: result.manageToken,
        startsAt: result.appointment.startAt,
      );

      selectedSlot.value = null;
      nameCtl.clear();
      phoneCtl.clear();
      await refreshSlots();
      _showConfirmation(result.appointment, result.manageToken);
    } on BookingException catch (e) {
      if (e.isSlotGone) {
        // Someone got there first. Redraw so the customer picks from what is
        // actually left instead of retrying into the same refusal.
        await refreshSlots();
        _snack('Termin vergeben', e.message);
      } else {
        _snack('Buchung fehlgeschlagen', e.message);
      }
    } catch (e, st) {
      debugPrint('[BookingController.submit] $e');
      debugPrintStack(stackTrace: st, label: 'BookingController.submit');
      _snack('Buchung fehlgeschlagen',
          'Termin konnte nicht gespeichert werden. Bitte erneut versuchen.');
    } finally {
      submitting.value = false;
    }
  }

  void _showConfirmation(Appointment appt, String token) {
    final live = Rx<Appointment>(appt);
    final priceCents =
        services.firstWhereOrNull((s) => s.id == appt.serviceId)?.priceCents ??
            0;
    final payLabel = priceCents > 0
        ? 'Bezahlen €${(priceCents / 100).toStringAsFixed(2)}'
        : 'Online bezahlen';

    Get.dialog(
      AlertDialog(
        title: const Text('Termin bestätigt'),
        content: Obx(() {
          final a = live.value;
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                  '${a.serviceName} bei ${brandLight.businessName}\n${a.whenLabel}.'),
              const SizedBox(height: S.md),
              if (a.paid)
                const PaidBadge(label: 'Bezahlt')
              else
                Text(
                  'Du kannst deinen Termin direkt online bezahlen oder vor Ort.',
                  style:
                      TextStyle(color: Get.theme.colorScheme.onSurfaceVariant),
                ),
            ],
          );
        }),
        actionsOverflowAlignment: OverflowBarAlignment.end,
        actions: [
          Obx(() {
            final a = live.value;
            return Wrap(
              alignment: WrapAlignment.end,
              spacing: 4,
              children: [
                TextButton.icon(
                  onPressed: () => _calendar.addAppointment(a),
                  icon: const Icon(Icons.event_available),
                  label: const Text('Zum Kalender'),
                ),
                if (!a.paid && priceCents > 0)
                  TextButton.icon(
                    onPressed: () => _pay(a, token, live),
                    icon: const Icon(Icons.euro_symbol),
                    label: Text(payLabel),
                  ),
                TextButton(
                  onPressed: () => Get.back(),
                  child: const Text('Fertig'),
                ),
              ],
            );
          }),
        ],
      ),
    );
  }

  /// Take a card payment, then *ask the server* whether it landed.
  ///
  /// The app used to mark the booking paid itself. It cannot any more — the
  /// Stripe webhook is the only writer of that flag — so the flow is: present
  /// the sheet, then poll until the webhook has been and gone.
  Future<void> _pay(Appointment a, String token, Rx<Appointment> live) async {
    final result = await _payments.collectPayment(
      appointmentId: a.id,
      manageToken: token,
    );
    switch (result) {
      case PaymentOutcome.succeeded:
        final confirmed = await _payments.awaitPaidState(
          appointmentId: a.id,
          manageToken: token,
        );
        if (confirmed != null) live.value = confirmed;
        if (confirmed?.paid ?? false) {
          _snack('Zahlung empfangen', 'Danke, deine Zahlung ist eingegangen.');
        } else {
          // Stripe accepted the card but the webhook has not caught up. Saying
          // "paid" here would be the same lie the old client told.
          _snack('Zahlung wird geprüft',
              'Deine Zahlung wird noch bestätigt. Der Termin steht.');
        }
      case PaymentOutcome.cancelled:
        break; // user dismissed the sheet — silent
      case PaymentOutcome.unavailable:
        _snack('Nicht verfügbar',
            'Online-Zahlung ist auf diesem Gerät nicht möglich.');
      case PaymentOutcome.failed:
        _snack('Zahlung fehlgeschlagen',
            'Bitte erneut versuchen oder vor Ort bezahlen.');
    }
  }

  void _snack(String title, String message) => Get.snackbar(
        title,
        message,
        snackPosition: SnackPosition.BOTTOM,
      );

  bool _looksLikePhone(String s) {
    final cleaned = s.replaceAll(RegExp(r'[\s\-()]'), '');
    return RegExp(r'^\+?\d{7,15}$').hasMatch(cleaned);
  }
}
