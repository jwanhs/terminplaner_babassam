import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Local store for the manage tokens that prove a booking is this device's.
///
/// The product promise is "leave a name and a number, done" — no account, no
/// password. That still has to answer "how do we know this cancellation is
/// yours?", and the answer is a token the server minted at booking time and
/// handed back exactly once. It lives here, on the device, and is sent with
/// every cancel, move or payment.
///
/// Losing the device means losing the tokens, which is why the app can also
/// verify a phone number by SMS and pull the bookings back that way.
///
/// NOT a secret store: these are bearer tokens for a haircut, and putting them
/// in the keychain would buy little against an attacker who already has the
/// unlocked phone. They are scoped to one booking each and expire with it.
class TokenStore {
  TokenStore._(this._prefs);

  static const _key = 'manage_tokens_v1';

  /// Bookings older than this are dropped: a token for last spring's haircut
  /// is dead weight, and the list is sent on every lookup.
  static const _keepFor = Duration(days: 120);

  final SharedPreferences _prefs;

  static Future<TokenStore> open() async =>
      TokenStore._(await SharedPreferences.getInstance());

  /// Stored as "appointmentId|token|isoTimestamp" triples, one per entry —
  /// plain enough to inspect and repair by hand if it ever comes to that.
  List<String> get _raw => _prefs.getStringList(_key) ?? const [];

  /// Every live token, newest first.
  List<String> get tokens =>
      _entries().map((e) => e.token).toList(growable: false);

  bool get isEmpty => tokens.isEmpty;

  String? tokenFor(String appointmentId) {
    for (final e in _entries()) {
      if (e.appointmentId == appointmentId) return e.token;
    }
    return null;
  }

  Future<void> remember({
    required String appointmentId,
    required String token,
    DateTime? startsAt,
  }) async {
    final kept = _entries()
        .where((e) => e.appointmentId != appointmentId)
        .toList()
      ..insert(
          0, _Entry(appointmentId, token, startsAt ?? DateTime.now().toUtc()));
    await _write(kept);
  }

  Future<void> forget(String appointmentId) async {
    await _write(
        _entries().where((e) => e.appointmentId != appointmentId).toList());
  }

  Future<void> clear() => _prefs.remove(_key);

  /// Drop entries for bookings long past. Called on boot.
  Future<void> prune() async {
    final cutoff = DateTime.now().toUtc().subtract(_keepFor);
    final kept = _entries().where((e) => e.startsAt.isAfter(cutoff)).toList();
    if (kept.length != _entries().length) await _write(kept);
  }

  List<_Entry> _entries() {
    final out = <_Entry>[];
    for (final line in _raw) {
      final parts = line.split('|');
      if (parts.length != 3) continue; // corrupt entry — skip rather than throw
      final when = DateTime.tryParse(parts[2]);
      if (when == null) continue;
      out.add(_Entry(parts[0], parts[1], when));
    }
    return out;
  }

  Future<void> _write(List<_Entry> entries) async {
    try {
      await _prefs.setStringList(
        _key,
        entries
            .map((e) => '${e.appointmentId}|${e.token}|'
                '${e.startsAt.toUtc().toIso8601String()}')
            .toList(),
      );
    } catch (e) {
      // A booking that succeeded server-side must not look like a failure just
      // because the device could not write to disk; the customer keeps the
      // appointment, they just cannot self-cancel from this device.
      debugPrint('[TokenStore] could not persist tokens: $e');
    }
  }
}

class _Entry {
  _Entry(this.appointmentId, this.token, this.startsAt);
  final String appointmentId;
  final String token;
  final DateTime startsAt;
}
