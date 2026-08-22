import 'dart:convert';

import 'package:appwrite/appwrite.dart';
import 'package:appwrite/enums.dart';
import 'package:flutter/foundation.dart';

import '../../core/env.dart';
import 'models.dart';

/// The customer app's only way to reach booking data.
///
/// It used to write the appointments table directly, which is how every
/// customer's name and phone number ended up world-readable and every booking
/// world-editable. That table is staff-only now; everything here goes through
/// the `booking-api` Appwrite Function, which enforces ownership and decides
/// prices, durations and availability itself.
///
/// What that means for this class: it sends intent, never facts. No amounts,
/// no paid flags, no end times, no "this slot is free" — the server works all
/// of that out and this renders the answer.
class BookingApi {
  BookingApi(this._functions);

  final Functions _functions;

  Future<CatalogResult> catalog() async {
    final json = await _call({'action': 'catalog'});
    return CatalogResult.fromJson(json);
  }

  /// Free slots for one day and service, already filtered by the shop's hours,
  /// breaks, closures, buffer and lead time — and already in the shop's
  /// timezone. A taken slot is simply absent; the app is never told who has it.
  Future<List<Slot>> availability({
    required String serviceId,
    required String dateKey,
  }) async {
    final json = await _call({
      'action': 'availability',
      'serviceId': serviceId,
      'date': dateKey,
    });
    return (json['slots'] as List<dynamic>)
        .map((s) => Slot.fromJson(s as Map<String, dynamic>))
        .toList(growable: false);
  }

  /// Book [start] for [serviceId].
  ///
  /// Returns the saved booking *and* the manage token, which is handed over
  /// exactly once and must be persisted immediately — it is the only proof of
  /// ownership this device will ever get for it.
  Future<BookingResult> create({
    required String serviceId,
    required DateTime start,
    required String name,
    required String phone,
    String? notes,
  }) async {
    final json = await _call({
      'action': 'create',
      'serviceId': serviceId,
      'start': start.toUtc().toIso8601String(),
      'name': name,
      'phone': phone,
      if (notes != null && notes.isNotEmpty) 'notes': notes,
    });
    return BookingResult(
      appointment:
          Appointment.fromJson(json['appointment'] as Map<String, dynamic>),
      manageToken: json['manageToken'] as String,
    );
  }

  /// Bookings this caller can prove are theirs: by manage tokens held on the
  /// device, by a verified phone session, or both.
  Future<MyBookings> mine({
    List<String> tokens = const [],
    String? session,
  }) async {
    final json = await _call({
      'action': 'my',
      'tokens': tokens,
      if (session != null) 'session': session,
    });
    return MyBookings.fromJson(json);
  }

  Future<Appointment> cancel(
          {required String appointmentId, required String auth}) =>
      _mutate('cancel', appointmentId, auth);

  Future<Appointment> redeemReward({
    required String appointmentId,
    required String auth,
  }) =>
      _mutate('redeem', appointmentId, auth);

  /// Current server-side state of a booking. Used to find out whether a card
  /// payment actually landed — the client cannot mark itself paid any more, so
  /// after the Stripe sheet closes it has to ask.
  Future<Appointment> status(
          {required String appointmentId, required String auth}) =>
      _mutate('status', appointmentId, auth);

  Future<Appointment> reschedule({
    required String appointmentId,
    required String auth,
    required DateTime start,
  }) async {
    final json = await _call({
      'action': 'reschedule',
      'appointmentId': appointmentId,
      ..._auth(auth),
      'start': start.toUtc().toIso8601String(),
    });
    return Appointment.fromJson(json['appointment'] as Map<String, dynamic>);
  }

  // ─── phone verification ────────────────────────────────────────────────────

  /// Send a one-time code so a customer on a new device can see their history.
  /// Returns a dev code only when the function is explicitly in pilot mode.
  Future<String?> requestCode(String phone) async {
    final json = await _call({'action': 'otp_request', 'phone': phone});
    return json['devCode'] as String?;
  }

  /// Exchange a code for a short-lived session token.
  Future<String> verifyCode(
      {required String phone, required String code}) async {
    final json = await _call({
      'action': 'otp_verify',
      'phone': phone,
      'code': code,
    });
    return json['session'] as String;
  }

  // ─── plumbing ──────────────────────────────────────────────────────────────

  Future<Appointment> _mutate(
      String action, String appointmentId, String auth) async {
    final json = await _call({
      'action': action,
      'appointmentId': appointmentId,
      ..._auth(auth),
    });
    return Appointment.fromJson(json['appointment'] as Map<String, dynamic>);
  }

  /// A manage token and an OTP session are both bearer proofs; the server
  /// accepts either. Sessions are distinguishable because they are minted by
  /// the OTP flow, so the caller tags which one it holds.
  Map<String, String> _auth(String auth) => auth.startsWith(sessionPrefix)
      ? {'session': auth.substring(sessionPrefix.length)}
      : {'token': auth};

  /// Marker the controllers use to say "this proof is a phone session, not a
  /// booking token".
  static const sessionPrefix = 'session:';

  Future<Map<String, dynamic>> _call(Map<String, dynamic> body) async {
    final exec = await _functions.createExecution(
      functionId: Env.bookingFunctionId,
      body: jsonEncode(body),
      method: ExecutionMethod.pOST,
      headers: const {'content-type': 'application/json'},
    );

    Map<String, dynamic>? json;
    try {
      json = jsonDecode(exec.responseBody) as Map<String, dynamic>;
    } catch (_) {
      // An empty or non-JSON body means the function itself fell over.
      debugPrint('[BookingApi] ${body['action']}: '
          'HTTP ${exec.responseStatusCode}, body="${exec.responseBody}"');
      throw const BookingException('server_error',
          'Verbindung zum Salon fehlgeschlagen. Bitte erneut versuchen.');
    }

    if (json['ok'] != true) {
      throw BookingException(
        (json['error'] as String?) ?? 'server_error',
        (json['message'] as String?) ?? 'Etwas ist schiefgelaufen.',
      );
    }
    return json;
  }
}

/// A refusal from the booking API, carrying a code the UI can branch on and a
/// message already written for the customer.
class BookingException implements Exception {
  const BookingException(this.code, this.message);

  final String code;
  final String message;

  /// The slot went while the customer was filling in the form.
  bool get isSlotGone => code == 'slot_taken' || code == 'slot_unavailable';

  /// Too close to the appointment to change it online.
  bool get isTooLate => code == 'too_late';

  bool get isRateLimited => code == 'rate_limited';

  bool get isSessionExpired => code == 'session_expired';

  @override
  String toString() => 'BookingException($code): $message';
}

class BookingResult {
  BookingResult({required this.appointment, required this.manageToken});
  final Appointment appointment;
  final String manageToken;
}
