import 'dart:convert';

import 'package:appwrite/enums.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import '../../core/env.dart';
import '../core/appwrite_client.dart';
import '../widgets/card_payment_dialog.dart';
import 'booking_api.dart';
import 'models.dart';

bool get _stripeSupported =>
    kIsWeb ||
    defaultTargetPlatform == TargetPlatform.android ||
    defaultTargetPlatform == TargetPlatform.iOS;

enum PaymentOutcome { succeeded, cancelled, failed, unavailable }

/// Card payment, in three steps and one important absence.
///
///   1. Ask the `stripe-deposit` Function for a PaymentIntent. It prices the
///      charge from the service (minus any loyalty discount) and requires the
///      booking's manage token, so neither the amount nor the target booking
///      comes from this device.
///   2. Present [CardPaymentDialog], which confirms the PaymentIntent
///      directly. Not `PaymentSheet` — flutter_stripe never implemented that
///      for web, and this app is web-only, so `initPaymentSheet` throws
///      `WebUnsupportedError` on every platform this ships to.
///      `CardField` + `confirmPayment` is the part of the SDK that actually
///      is cross-platform.
///   3. Poll the booking API until the Stripe webhook has marked the booking
///      paid.
///
/// The absence: this class never writes `paid`. It used to, on a
/// world-writable row, which meant the app's word was the only evidence any
/// money had moved. Now Stripe tells the server and the server tells us.
class PaymentService {
  PaymentService({required BookingApi api, AppwriteService? aw})
      : _api = api,
        _aw = aw ?? Get.find<AppwriteService>();

  final BookingApi _api;
  final AppwriteService _aw;

  /// How long to wait for the webhook. Stripe usually delivers in a second or
  /// two; beyond this the app says "being confirmed" rather than guessing.
  static const _pollAttempts = 6;
  static const _pollInterval = Duration(seconds: 2);

  Future<PaymentOutcome> collectPayment({
    required String appointmentId,
    required String manageToken,
  }) async {
    if (!_stripeSupported || !Env.paymentsEnabled) {
      debugPrint('[PaymentService] payments unavailable '
          '(platform=$defaultTargetPlatform, configured=${Env.paymentsEnabled})');
      return PaymentOutcome.unavailable;
    }

    try {
      final intent = await _fetchIntent(appointmentId, manageToken);
      if (intent == null) return PaymentOutcome.failed;

      final result = await Get.dialog<bool>(
        CardPaymentDialog(
          clientSecret: intent.clientSecret,
          amountCents: intent.amountCents,
        ),
        barrierDismissible: false,
      );
      if (result == true) return PaymentOutcome.succeeded;
      if (result == false) return PaymentOutcome.failed;
      return PaymentOutcome.cancelled;
    } catch (e, st) {
      debugPrint('[PaymentService] $e');
      debugPrintStack(stackTrace: st, label: 'PaymentService');
      return PaymentOutcome.failed;
    }
  }

  /// Poll until the webhook has marked the booking paid, or give up.
  ///
  /// Returns the freshest appointment seen — the caller checks `paid` rather
  /// than assuming, because "Stripe took the card" and "the shop knows about
  /// it" are genuinely different moments.
  Future<Appointment?> awaitPaidState({
    required String appointmentId,
    required String manageToken,
  }) async {
    Appointment? latest;
    for (var attempt = 0; attempt < _pollAttempts; attempt++) {
      await Future<void>.delayed(_pollInterval);
      try {
        latest =
            await _api.status(appointmentId: appointmentId, auth: manageToken);
        if (latest.paid) return latest;
      } on BookingException catch (e) {
        debugPrint('[PaymentService.awaitPaidState] ${e.code}: ${e.message}');
        return latest;
      } catch (e) {
        debugPrint('[PaymentService.awaitPaidState] $e');
      }
    }
    return latest;
  }

  /// Calls the payment function. Sends only the booking id and the proof that
  /// it is ours; the amount comes back, it never goes out.
  Future<({String clientSecret, int amountCents})?> _fetchIntent(
    String appointmentId,
    String manageToken,
  ) async {
    final exec = await _aw.functions.createExecution(
      functionId: Env.stripeFunctionId,
      body: jsonEncode({'appointmentId': appointmentId, 'token': manageToken}),
      method: ExecutionMethod.pOST,
      headers: const {'content-type': 'application/json'},
    );
    if (exec.responseStatusCode >= 400) {
      debugPrint('[PaymentService] Function ${exec.responseStatusCode}: '
          '${exec.responseBody}');
      return null;
    }

    final Map<String, dynamic> decoded;
    try {
      decoded = jsonDecode(exec.responseBody) as Map<String, dynamic>;
    } catch (_) {
      debugPrint('[PaymentService] Unparseable response: ${exec.responseBody}');
      return null;
    }

    final clientSecret = decoded['clientSecret'] as String?;
    if (clientSecret == null || clientSecret.isEmpty) {
      debugPrint(
          '[PaymentService] No clientSecret in response: ${exec.responseBody}');
      return null;
    }
    return (
      clientSecret: clientSecret,
      amountCents: (decoded['amount'] as num?)?.toInt() ?? 0,
    );
  }
}
