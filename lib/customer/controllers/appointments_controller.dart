import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../data/booking_api.dart';
import '../data/calendar_service.dart';
import '../data/models.dart';
import '../data/payment_service.dart';
import '../data/token_store.dart';
import '../pages/reschedule_page.dart';

/// Drives "Meine Termine".
///
/// The old version took a phone number and handed back that person's entire
/// visit history — to anyone who typed it. Numbers are guessable and
/// enumerable, so that was a directory of who gets their hair cut where and
/// when. It is replaced by two paths:
///
///   * **This device.** Bookings made here carry a manage token in local
///     storage; they appear immediately, no code, no friction. This is the
///     common case and it keeps the product's "no account" promise intact.
///   * **A new device.** Enter the number, receive a one-time code by SMS,
///     and the server hands back a short-lived session. Costs one SMS and
///     closes the enumeration hole.
class AppointmentsController extends GetxController {
  AppointmentsController({
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

  final phoneCtl = TextEditingController();
  final codeCtl = TextEditingController();

  final loading = false.obs;
  final searched = false.obs;
  final results = <Appointment>[].obs;
  final card = Rxn<LoyaltyCard>();

  /// True once a code has been sent and we are waiting for the customer to
  /// type it.
  final awaitingCode = false.obs;

  /// Set when the function is running in pilot mode without an SMS provider,
  /// so the code can be shown on screen instead of arriving by text.
  final devCode = RxnString();

  final errorText = RxnString();

  /// Live OTP session, once a number has been verified. Prefixed so the API
  /// client can tell it apart from a booking's manage token.
  final _session = RxnString();

  final _servicePrices = <String, int>{};

  bool get hasVerifiedPhone => _session.value != null;

  @override
  void onInit() {
    super.onInit();
    _loadServicePrices();
    loadLocal();
  }

  @override
  void onClose() {
    phoneCtl.dispose();
    codeCtl.dispose();
    super.onClose();
  }

  Future<void> _loadServicePrices() async {
    try {
      final catalog = await _api.catalog();
      _servicePrices
        ..clear()
        ..addEntries(catalog.services.map((s) => MapEntry(s.id, s.priceCents)));
    } catch (e) {
      // Non-fatal: redemption is authorised server-side regardless of what the
      // UI thinks a cut is worth.
      debugPrint('[AppointmentsController._loadServicePrices] $e');
    }
  }

  /// Price of [serviceId] in cents, or null. Display only.
  int? priceCentsFor(String serviceId) => _servicePrices[serviceId];

  /// The bookings this device can prove are its own. No code needed.
  Future<void> loadLocal() async {
    if (_tokens.isEmpty) return;
    loading.value = true;
    try {
      final mine = await _api.mine(tokens: _tokens.tokens);
      _apply(mine);
      searched.value = true;
    } on BookingException catch (e) {
      errorText.value = e.message;
    } catch (e, st) {
      debugPrint('[AppointmentsController.loadLocal] $e');
      debugPrintStack(
          stackTrace: st, label: 'AppointmentsController.loadLocal');
    } finally {
      loading.value = false;
    }
  }

  /// Step one of the new-device path: send a one-time code.
  Future<void> requestCode() async {
    final phone = phoneCtl.text.trim();
    if (phone.length < 5) {
      errorText.value = 'Bitte Telefonnummer eingeben.';
      return;
    }
    loading.value = true;
    errorText.value = null;
    try {
      devCode.value = await _api.requestCode(phone);
      awaitingCode.value = true;
    } on BookingException catch (e) {
      errorText.value = e.code == 'sms_unavailable'
          ? 'Code-Versand ist gerade nicht möglich. Bitte im Salon anrufen.'
          : e.message;
    } catch (e, st) {
      debugPrint('[AppointmentsController.requestCode] $e');
      debugPrintStack(
          stackTrace: st, label: 'AppointmentsController.requestCode');
      errorText.value = 'Code konnte nicht gesendet werden.';
    } finally {
      loading.value = false;
    }
  }

  /// Step two: exchange the code for a session and load the history.
  Future<void> verifyCode() async {
    final code = codeCtl.text.trim();
    if (code.length != 6) {
      errorText.value = 'Bitte den 6-stelligen Code eingeben.';
      return;
    }
    loading.value = true;
    errorText.value = null;
    try {
      final session = await _api.verifyCode(
        phone: phoneCtl.text.trim(),
        code: code,
      );
      _session.value = session;
      awaitingCode.value = false;
      codeCtl.clear();
      devCode.value = null;

      final mine = await _api.mine(
        tokens: _tokens.tokens,
        session: session,
      );
      _apply(mine);
      searched.value = true;
    } on BookingException catch (e) {
      errorText.value = e.message;
    } catch (e, st) {
      debugPrint('[AppointmentsController.verifyCode] $e');
      debugPrintStack(
          stackTrace: st, label: 'AppointmentsController.verifyCode');
      errorText.value = 'Bestätigung fehlgeschlagen.';
    } finally {
      loading.value = false;
    }
  }

  /// Start over — used when the customer wants to check a different number.
  void reset() {
    _session.value = null;
    awaitingCode.value = false;
    devCode.value = null;
    errorText.value = null;
    codeCtl.clear();
    results.clear();
    card.value = null;
    searched.value = false;
    loadLocal();
  }

  /// Re-fetch whatever the caller can prove is theirs.
  ///
  /// Named `reload` rather than `refresh` because GetxController already has
  /// a `refresh()` that notifies listeners; overriding it would break that.
  Future<void> reload() async {
    loading.value = true;
    try {
      final mine = await _api.mine(
        tokens: _tokens.tokens,
        session: _session.value,
      );
      _apply(mine);
    } on BookingException catch (e) {
      if (e.isSessionExpired) {
        _session.value = null;
        errorText.value = 'Bestätigung abgelaufen. Bitte erneut bestätigen.';
      } else {
        errorText.value = e.message;
      }
    } catch (e, st) {
      debugPrint('[AppointmentsController.reload] $e');
      debugPrintStack(stackTrace: st, label: 'AppointmentsController.reload');
    } finally {
      loading.value = false;
    }
  }

  void _apply(MyBookings mine) {
    final active = <Appointment>[];
    final cancelled = <Appointment>[];
    for (final a in mine.appointments) {
      (a.isCancelled ? cancelled : active).add(a);
    }
    results.assignAll([...active, ...cancelled]);
    card.value = mine.loyalty;
    errorText.value = null;
  }

  // ─── actions ───────────────────────────────────────────────────────────────

  /// Proof of ownership for [a]: the booking's own manage token if this device
  /// holds it, otherwise the verified phone session. Null means we cannot act
  /// on it and the UI should not offer to.
  String? authFor(Appointment a) {
    final token = _tokens.tokenFor(a.id);
    if (token != null) return token;
    final session = _session.value;
    if (session != null) return '${BookingApi.sessionPrefix}$session';
    return null;
  }

  bool canManage(Appointment a) => authFor(a) != null;

  /// Online payment needs the booking's own manage token, not just a verified
  /// phone: the payment function authenticates with it, so a session that
  /// merely proves "this number is mine" cannot start a charge.
  bool canPayOnline(Appointment a) => _tokens.tokenFor(a.id) != null;

  Future<void> cancel(Appointment a) async {
    final auth = authFor(a);
    if (auth == null) return;

    final ok = await Get.dialog<bool>(
      AlertDialog(
        title: const Text('Termin stornieren?'),
        content: Text('${a.serviceName} ${a.whenLabel} stornieren?'),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: const Text('Behalten'),
          ),
          TextButton(
            onPressed: () => Get.back(result: true),
            child: const Text('Stornieren'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      final updated = await _api.cancel(appointmentId: a.id, auth: auth);
      _replaceLocal(updated);
      await _tokens.forget(a.id);
    } on BookingException catch (e) {
      // The cutoff is a real rule, not a bug — say so plainly and point at the
      // phone, which still works.
      Get.snackbar(
        e.isTooLate ? 'Zu kurzfristig' : 'Stornierung fehlgeschlagen',
        e.message,
        snackPosition: SnackPosition.BOTTOM,
      );
    } catch (e, st) {
      debugPrint('[AppointmentsController.cancel] $e');
      debugPrintStack(stackTrace: st, label: 'AppointmentsController.cancel');
      Get.snackbar('Stornierung fehlgeschlagen',
          'Der Termin konnte nicht storniert werden.',
          snackPosition: SnackPosition.BOTTOM);
    }
  }

  Future<void> reschedule(Appointment a) async {
    final auth = authFor(a);
    if (auth == null) return;
    final updated = await Get.to<Appointment>(
      () => ReschedulePage(original: a, auth: auth),
    );
    if (updated == null) return;
    _replaceLocal(updated);
    Get.snackbar(
        'Termin verschoben', '${updated.serviceName} ${updated.whenLabel}.',
        snackPosition: SnackPosition.BOTTOM);
  }

  Future<void> addToCalendar(Appointment a) async {
    final ok = await _calendar.addAppointment(a);
    if (!ok) {
      Get.snackbar('Kalender', 'Termin konnte nicht übernommen werden.',
          snackPosition: SnackPosition.BOTTOM);
    }
  }

  Future<void> payDeposit(Appointment a) async {
    final token = _tokens.tokenFor(a.id);
    if (token == null) {
      // The payment function authenticates with the booking's own token; a
      // phone session is not enough to move money.
      Get.snackbar(
          'Nicht möglich',
          'Online-Zahlung geht nur auf dem Gerät, mit dem gebucht wurde. '
              'Vor Ort zahlen ist immer möglich.',
          snackPosition: SnackPosition.BOTTOM);
      return;
    }

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
        if (confirmed != null) _replaceLocal(confirmed);
        Get.snackbar(
          confirmed?.paid ?? false
              ? 'Zahlung empfangen'
              : 'Zahlung wird geprüft',
          confirmed?.paid ?? false
              ? 'Danke, deine Zahlung ist eingegangen.'
              : 'Deine Zahlung wird noch bestätigt.',
          snackPosition: SnackPosition.BOTTOM,
        );
      case PaymentOutcome.cancelled:
        break;
      case PaymentOutcome.unavailable:
        Get.snackbar('Nicht verfügbar',
            'Online-Zahlung ist auf diesem Gerät nicht möglich.',
            snackPosition: SnackPosition.BOTTOM);
      case PaymentOutcome.failed:
        Get.snackbar('Zahlung fehlgeschlagen',
            'Bitte erneut versuchen oder vor Ort bezahlen.',
            snackPosition: SnackPosition.BOTTOM);
    }
  }

  /// Spend a loyalty reward. The server re-derives the entitlement from the
  /// customer's history and sets the discount to the service's real price —
  /// this only asks.
  Future<void> redeemReward(Appointment a) async {
    final auth = authFor(a);
    if (auth == null) return;

    final ok = await Get.dialog<bool>(
      AlertDialog(
        title: const Text('Prämie einlösen?'),
        content: Text(
          'Dieser Termin (${a.serviceName}) wird als Gratis-Schnitt eingelöst.',
        ),
        actions: [
          TextButton(
              onPressed: () => Get.back(result: false),
              child: const Text('Abbrechen')),
          TextButton(
              onPressed: () => Get.back(result: true),
              child: const Text('Einlösen')),
        ],
      ),
    );
    if (ok != true) return;

    try {
      final updated = await _api.redeemReward(appointmentId: a.id, auth: auth);
      _replaceLocal(updated);
      await reload(); // the card changed too
      Get.snackbar('Prämie eingelöst', 'Dieser Termin geht aufs Haus.',
          snackPosition: SnackPosition.BOTTOM);
    } on BookingException catch (e) {
      Get.snackbar('Einlösen nicht möglich', e.message,
          snackPosition: SnackPosition.BOTTOM);
    } catch (e, st) {
      debugPrint('[AppointmentsController.redeemReward] $e');
      debugPrintStack(
          stackTrace: st, label: 'AppointmentsController.redeemReward');
      Get.snackbar('Einlösen nicht möglich', 'Bitte später erneut versuchen.',
          snackPosition: SnackPosition.BOTTOM);
    }
  }

  void _replaceLocal(Appointment updated) {
    final i = results.indexWhere((a) => a.id == updated.id);
    if (i >= 0) results[i] = updated;
  }
}
