import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart' as aw;

import '../../core/env.dart';
import '../../core/shop_time.dart';
import 'models.dart';

/// Everything the staff panel reads and writes.
///
/// Unlike the customer app — which must go through the booking-api Function
/// because it is anonymous — staff hold a real Appwrite session, and the tables
/// grant `team:staff` directly. So this talks to TablesDB, and the *table
/// permissions* are what stop a signed-out or non-staff user seeing anything.
/// Hiding the buttons would not be security; the grant is.
class StaffRepository {
  StaffRepository(Client client)
      : _db = TablesDB(client),
        _teams = Teams(client),
        _account = Account(client);

  final TablesDB _db;
  final Teams _teams;
  final Account _account;

  static const _dbId = Env.databaseId;
  static const _tAppointments = 'appointments';
  static const _tServices = 'services';
  static const _tHours = 'business_hours';
  static const _tClosures = 'closures';
  static const _tSettings = 'shop_settings';
  static const _tResources = 'resources';

  // ─── auth ──────────────────────────────────────────────────────────────────

  Future<aw.User> signIn(
      {required String email, required String password}) async {
    await _account.createEmailPasswordSession(email: email, password: password);
    return _account.get();
  }

  Future<aw.User?> currentUser() async {
    try {
      return await _account.get();
    } on AppwriteException {
      return null;
    }
  }

  Future<void> signOut() async {
    try {
      await _account.deleteSession(sessionId: 'current');
    } on AppwriteException {
      // Already gone server-side; the local state is what matters next.
    }
  }

  /// Is the signed-in user actually staff?
  ///
  /// Checked against the same team the table permissions name, so this agrees
  /// with what the server will allow rather than guessing at it.
  Future<bool> isStaff() async {
    try {
      final teams = await _teams.list();
      return teams.teams.any((t) => t.$id == Env.staffTeamId);
    } on AppwriteException {
      return false;
    }
  }

  // ─── appointments ──────────────────────────────────────────────────────────

  /// Every appointment touching the shop-local day containing [day],
  /// cancellations included — staff need to see what fell through, not have it
  /// quietly hidden.
  Future<List<StaffAppointment>> appointmentsForDay(DateTime day) async {
    final start = ShopTime.startOfShopDay(day);
    final end = start.add(const Duration(days: 1));
    final res = await _db.listRows(
      databaseId: _dbId,
      tableId: _tAppointments,
      queries: [
        // Widened back a day so a booking that runs past midnight still shows.
        Query.greaterThanEqual('start_at',
            start.subtract(const Duration(hours: 12)).toIso8601String()),
        Query.lessThan('start_at', end.toIso8601String()),
        Query.orderAsc('start_at'),
        Query.limit(200),
      ],
    );
    return res.rows
        .map((r) => StaffAppointment.fromRow(r.data, r.$id))
        .where((a) => a.endAt.isAfter(start) && a.startAt.isBefore(end))
        .toList(growable: false);
  }

  Future<StaffAppointment> setStatus(String id, ApptStatus status) async {
    final row = await _db.updateRow(
      databaseId: _dbId,
      tableId: _tAppointments,
      rowId: id,
      data: {
        'status': status.wire,
        // Cancelling has to release the slot key, or the unique index keeps
        // the slot reserved for a booking that is no longer happening.
        if (status == ApptStatus.cancelled) 'slot_key': 'released|$id',
      },
    );
    return StaffAppointment.fromRow(row.data, row.$id);
  }

  Future<StaffAppointment> reschedule({
    required String id,
    required DateTime startAt,
    required Duration duration,
  }) async {
    final row = await _db.updateRow(
      databaseId: _dbId,
      tableId: _tAppointments,
      rowId: id,
      data: {
        'start_at': startAt.toUtc().toIso8601String(),
        'end_at': startAt.add(duration).toUtc().toIso8601String(),
        // Staff moves keep their own key namespace: the shop is allowed to
        // deliberately put two people in one slot, the public is not.
        'slot_key': 'staff|$id',
      },
    );
    return StaffAppointment.fromRow(row.data, row.$id);
  }

  Future<void> deleteAppointment(String id) => _db.deleteRow(
        databaseId: _dbId,
        tableId: _tAppointments,
        rowId: id,
      );

  /// Someone who walked in off the street.
  ///
  /// The slot key is staff-namespaced on purpose, so this never collides with
  /// the customer-facing unique index — squeezing someone in beside an existing
  /// booking is a judgement call the shop is allowed to make. Online
  /// availability still sees the walk-in as busy time, because that check is an
  /// overlap test over every live appointment.
  Future<StaffAppointment> createWalkIn({
    required ShopService service,
    required DateTime startAt,
    required String customerName,
    String customerPhone = '',
    String? notes,
    String? chairId,
  }) async {
    final id = ID.unique();
    final end = startAt.add(Duration(minutes: service.durationMinutes));
    final row = await _db.createRow(
      databaseId: _dbId,
      tableId: _tAppointments,
      rowId: id,
      data: {
        'customer_name': customerName.trim().isEmpty
            ? 'Laufkundschaft'
            : customerName.trim(),
        // Loyalty is keyed on the phone number, so a walk-in without one earns
        // no stamps. Staff can type the real number if the customer wants them.
        'customer_phone':
            customerPhone.trim().isEmpty ? '-' : customerPhone.trim(),
        'service_id': service.id,
        'service_name': service.name,
        'start_at': startAt.toUtc().toIso8601String(),
        'end_at': end.toUtc().toIso8601String(),
        'status': ApptStatus.confirmed.wire,
        'source': ApptSource.walkin.wire,
        'paid': false,
        'payment_amount_cents': 0,
        'discount_cents': 0,
        'slot_key': 'staff|$id',
        // A walk-in still occupies a chair, and online availability has to
        // see which one — otherwise the shop sells the seat they are in.
        if (chairId != null && chairId.isNotEmpty) 'resource_id': chairId,
        if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
      },
    );
    return StaffAppointment.fromRow(row.data, row.$id);
  }

  /// Mark an appointment settled in cash at the counter.
  ///
  /// Card payments are written by the Stripe webhook and never from a client;
  /// this is the deliberate exception for money that changed hands in the shop,
  /// and it is available to staff only.
  Future<StaffAppointment> markPaidInPerson({
    required String id,
    required int amountCents,
  }) async {
    final row = await _db.updateRow(
      databaseId: _dbId,
      tableId: _tAppointments,
      rowId: id,
      data: {'paid': true, 'payment_amount_cents': amountCents},
    );
    return StaffAppointment.fromRow(row.data, row.$id);
  }

  // ─── chairs ────────────────────────────────────────────────────────────────

  /// The chairs bookings can sit on, in the order the shop fills them.
  ///
  /// An empty list is the normal state of a one-chair shop, not an error: the
  /// booking API falls back to an implicit resource and the panel hides every
  /// mention of chairs. A deployment that has not re-run setup_barber_db.sh
  /// has no such table at all, which must read the same way rather than
  /// breaking the agenda.
  Future<List<Chair>> chairs() async {
    try {
      final res = await _db.listRows(
        databaseId: _dbId,
        tableId: _tResources,
        queries: [
          Query.equal('active', true),
          Query.orderAsc('display_order'),
          Query.limit(50),
        ],
      );
      return res.rows
          .map((r) => Chair.fromRow(r.data, r.$id))
          .toList(growable: false);
    } catch (_) {
      return const <Chair>[];
    }
  }

  // ─── services ──────────────────────────────────────────────────────────────

  Future<List<ShopService>> services() async {
    final res = await _db.listRows(
      databaseId: _dbId,
      tableId: _tServices,
      queries: [Query.orderAsc('display_order'), Query.limit(50)],
    );
    return res.rows
        .map((r) => ShopService.fromRow(r.data, r.$id))
        .toList(growable: false);
  }

  // ─── business hours ────────────────────────────────────────────────────────

  Future<List<DayHours>> hours() async {
    final res = await _db.listRows(
      databaseId: _dbId,
      tableId: _tHours,
      queries: [Query.limit(7)],
    );
    final byWeekday = <int, DayHours>{
      for (final r in res.rows)
        (r.data['weekday'] as int? ?? 0): DayHours.fromRow(r.data),
    };
    // Always hand back all seven days: a weekday with no row is a day the shop
    // is closed, and the editor needs something to switch on.
    return List.generate(7, (i) => byWeekday[i] ?? DayHours.closedOn(i));
  }

  /// Upsert one weekday's hours. Row ids are `hours_<weekday>` so this stays
  /// idempotent without a lookup.
  Future<void> saveHours(DayHours day) async {
    final rowId = 'hours_${day.weekday}';
    try {
      await _db.updateRow(
        databaseId: _dbId,
        tableId: _tHours,
        rowId: rowId,
        data: day.toRow(),
      );
    } on AppwriteException catch (e) {
      if (e.code != 404) rethrow;
      await _db.createRow(
        databaseId: _dbId,
        tableId: _tHours,
        rowId: rowId,
        data: day.toRow(),
      );
    }
  }

  // ─── closures ──────────────────────────────────────────────────────────────

  Future<List<Closure>> closures({DateTime? from, DateTime? to}) async {
    final start =
        from ?? DateTime.now().toUtc().subtract(const Duration(days: 1));
    final end = to ?? DateTime.now().toUtc().add(const Duration(days: 120));
    final res = await _db.listRows(
      databaseId: _dbId,
      tableId: _tClosures,
      queries: [
        Query.lessThan('starts_at', end.toUtc().toIso8601String()),
        Query.greaterThanEqual('ends_at', start.toUtc().toIso8601String()),
        Query.orderAsc('starts_at'),
        Query.limit(100),
      ],
    );
    return res.rows
        .map((r) => Closure.fromRow(r.data, r.$id))
        .toList(growable: false);
  }

  Future<Closure> createClosure({
    required DateTime startsAt,
    required DateTime endsAt,
    String? reason,
    bool allDay = false,
    String? chairId,
  }) async {
    final row = await _db.createRow(
      databaseId: _dbId,
      tableId: _tClosures,
      rowId: ID.unique(),
      data: {
        'starts_at': startsAt.toUtc().toIso8601String(),
        'ends_at': endsAt.toUtc().toIso8601String(),
        'all_day': allDay,
        // Empty means the whole shop is shut, which is a different thing from
        // one barber being away.
        if (chairId != null && chairId.isNotEmpty) 'resource_id': chairId,
        if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
      },
    );
    return Closure.fromRow(row.data, row.$id);
  }

  Future<void> deleteClosure(String id) => _db.deleteRow(
        databaseId: _dbId,
        tableId: _tClosures,
        rowId: id,
      );

  // ─── settings ──────────────────────────────────────────────────────────────

  Future<ShopSettings> settings() async {
    try {
      final row = await _db.getRow(
        databaseId: _dbId,
        tableId: _tSettings,
        rowId: 'default',
      );
      return ShopSettings.fromRow(row.data);
    } on AppwriteException {
      return ShopSettings();
    }
  }

  Future<void> saveSettings(ShopSettings s) async {
    try {
      await _db.updateRow(
        databaseId: _dbId,
        tableId: _tSettings,
        rowId: 'default',
        data: s.toRow(),
      );
    } on AppwriteException catch (e) {
      if (e.code != 404) rethrow;
      await _db.createRow(
        databaseId: _dbId,
        tableId: _tSettings,
        rowId: 'default',
        data: s.toRow(),
      );
    }
  }
}
