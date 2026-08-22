import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/brand.dart';
import '../../core/shop_time.dart';
import '../controllers/agenda_controller.dart';
import '../controllers/staff_auth_controller.dart';
import '../data/models.dart';
import '../widgets/appointment_tile.dart';
import '../widgets/block_off_sheet.dart';
import '../widgets/day_stats_bar.dart';
import '../widgets/walkin_sheet.dart';
import 'settings_page.dart';

/// The shop's day. This is the screen the panel exists for: every appointment
/// for a given day, what state each is in, and the handful of actions staff
/// take on them.
class AgendaPage extends StatelessWidget {
  const AgendaPage({super.key, required this.tag});

  final String tag;

  @override
  Widget build(BuildContext context) {
    final c = Get.find<AgendaController>(tag: tag);
    final auth = Get.find<StaffAuthController>();
    final b = brandOf(context);

    return Scaffold(
      appBar: AppBar(
        title: Obx(() => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(c.dayLabel,
                    style: Theme.of(context).textTheme.titleMedium),
                if (!c.isToday)
                  Text(
                    'Nicht heute',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
              ],
            )),
        actions: [
          IconButton(
            onPressed: c.previousDay,
            icon: const Icon(Icons.chevron_left),
            tooltip: 'Vorheriger Tag',
          ),
          IconButton(
            onPressed: () => _pickDay(context, c),
            icon: const Icon(Icons.calendar_month),
            tooltip: 'Datum wählen',
          ),
          IconButton(
            onPressed: c.nextDay,
            icon: const Icon(Icons.chevron_right),
            tooltip: 'Nächster Tag',
          ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              switch (v) {
                case 'today':
                  c.goToToday();
                case 'block':
                  await _blockOff(context, c);
                case 'settings':
                  await Get.to(() => StaffSettingsPage(tag: tag));
                case 'signout':
                  await auth.signOut();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'today', child: Text('Heute')),
              PopupMenuItem(value: 'block', child: Text('Zeit sperren')),
              PopupMenuDivider(),
              PopupMenuItem(
                  value: 'settings', child: Text('Öffnungszeiten & Regeln')),
              PopupMenuItem(value: 'signout', child: Text('Abmelden')),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addWalkIn(context, c),
        icon: const Icon(Icons.add),
        label: const Text('Laufkundschaft'),
        backgroundColor: b.primary,
        foregroundColor: Colors.white,
      ),
      body: Obx(() {
        if (c.loading.value) {
          return const Center(child: CircularProgressIndicator());
        }
        return RefreshIndicator(
          onRefresh: c.reload,
          child: CustomScrollView(
            slivers: [
              if (c.deviceTimezoneWarning.value)
                SliverToBoxAdapter(
                  child: _Banner(
                    icon: Icons.public_off,
                    text:
                        'Dieses Gerät steht in einer anderen Zeitzone als der '
                        'Salon. Angezeigt werden immer die Zeiten des Salons '
                        '(${ShopTime.timezone}).',
                  ),
                ),
              if (c.errorText.value != null)
                SliverToBoxAdapter(
                  child: _Banner(
                    icon: Icons.error_outline,
                    text: c.errorText.value!,
                    isError: true,
                  ),
                ),
              SliverToBoxAdapter(child: DayStatsBar(totals: c.totals)),
              if (c.closuresToday.isNotEmpty)
                SliverToBoxAdapter(
                  child: _ClosuresStrip(
                    closures: c.closuresToday,
                    onRemove: c.removeClosure,
                    chairNameFor: c.hasChairs ? c.chairNameFor : null,
                  ),
                ),
              if (c.appointments.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: _EmptyDay(),
                )
              else
                SliverList.builder(
                  itemCount: c.appointments.length,
                  itemBuilder: (context, i) {
                    final a = c.appointments[i];
                    return AppointmentTile(
                      appointment: a,
                      priceCents: c.servicesById[a.serviceId]?.priceCents ?? 0,
                      chairName:
                          c.hasChairs ? c.chairNameFor(a.resourceId) : null,
                      onStatus: (s) => _confirmStatus(context, c, a, s),
                      onMarkPaid: () => c.markPaidInPerson(a),
                      onReschedule: () => _reschedule(context, c, a),
                    );
                  },
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 96)),
            ],
          ),
        );
      }),
    );
  }

  // ─── actions ───────────────────────────────────────────────────────────────

  Future<void> _pickDay(BuildContext context, AgendaController c) async {
    final wall = ShopTime.toShopWall(c.selectedDay.value);
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(wall.year, wall.month, wall.day),
      firstDate: DateTime(wall.year - 1),
      lastDate: DateTime(wall.year + 2),
      locale: const Locale('de'),
    );
    if (picked == null) return;
    // The picker hands back a device-local calendar date; turn it into the
    // shop's day rather than an instant that depends on where the phone is.
    c.goToDay(ShopTime.fromShopWall(picked.year, picked.month, picked.day));
  }

  Future<void> _addWalkIn(BuildContext context, AgendaController c) async {
    if (c.services.isEmpty) {
      _toast(context, 'Keine Leistungen angelegt.');
      return;
    }
    final result = await WalkInSheet.show(
      context,
      services: c.services.toList(),
      day: c.selectedDay.value,
      chairs: c.chairs.toList(),
    );
    if (result == null) return;
    try {
      await c.addWalkIn(
        service: result.service,
        startAt: result.startAt,
        name: result.name,
        phone: result.phone,
        notes: result.notes,
        chairId: result.chairId,
      );
      if (context.mounted) _toast(context, 'Eingetragen.');
    } catch (_) {
      if (context.mounted) _toast(context, 'Konnte nicht eingetragen werden.');
    }
  }

  Future<void> _blockOff(BuildContext context, AgendaController c) async {
    final result = await BlockOffSheet.show(
      context,
      day: c.selectedDay.value,
      chairs: c.chairs.toList(),
    );
    if (result == null) return;
    try {
      await c.blockOff(
        startsAt: result.startsAt,
        endsAt: result.endsAt,
        reason: result.reason,
        allDay: result.allDay,
        chairId: result.chairId,
      );
      if (context.mounted) _toast(context, 'Zeit gesperrt.');
    } catch (_) {
      if (context.mounted) _toast(context, 'Sperren fehlgeschlagen.');
    }
  }

  Future<void> _reschedule(
      BuildContext context, AgendaController c, StaffAppointment a) async {
    final wall = ShopTime.toShopWall(a.startAt);
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: wall.hour, minute: wall.minute),
      helpText: 'Neue Uhrzeit',
    );
    if (time == null) return;
    final start = ShopTime.fromShopWall(
        wall.year, wall.month, wall.day, time.hour, time.minute);
    try {
      await c.reschedule(a, start);
      if (context.mounted) _toast(context, 'Verschoben.');
    } catch (_) {
      if (context.mounted) _toast(context, 'Verschieben fehlgeschlagen.');
    }
  }

  /// Cancelling and no-show are the two that a customer feels, so they ask
  /// first. Marking something done does not — an accidental tap is undone from
  /// the same menu.
  Future<void> _confirmStatus(BuildContext context, AgendaController c,
      StaffAppointment a, ApptStatus status) async {
    if (status == ApptStatus.cancelled || status == ApptStatus.noShow) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(status == ApptStatus.cancelled
              ? 'Termin stornieren?'
              : 'Als nicht erschienen markieren?'),
          content:
              Text('${a.customerName} · ${a.serviceName} um ${a.startLabel}'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Abbrechen'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(
                  status == ApptStatus.cancelled ? 'Stornieren' : 'Bestätigen'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    try {
      await c.setStatus(a, status);
    } catch (_) {
      if (context.mounted) _toast(context, 'Änderung fehlgeschlagen.');
    }
  }

  static void _toast(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _EmptyDay extends StatelessWidget {
  const _EmptyDay();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(S.xxl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.event_available,
                size: 40, color: t.colorScheme.onSurfaceVariant),
            const SizedBox(height: S.md),
            Text('Keine Termine an diesem Tag', style: t.textTheme.titleSmall),
            const SizedBox(height: S.xs),
            Text(
              'Laufkundschaft lässt sich unten eintragen.',
              textAlign: TextAlign.center,
              style: t.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _ClosuresStrip extends StatelessWidget {
  const _ClosuresStrip({
    required this.closures,
    required this.onRemove,
    this.chairNameFor,
  });

  final List<Closure> closures;
  final Future<void> Function(Closure) onRemove;

  /// Resolves a chair id to its name, or null in a one-chair shop. Whether a
  /// block covers the whole shop or one barber is the first thing staff need
  /// to know when they look at this strip.
  final String Function(String?)? chairNameFor;

  String _scopeOf(Closure closure) {
    if (chairNameFor == null) return '';
    return closure.isShopWide
        ? ' · Ganzer Laden'
        : ' · nur ${chairNameFor!(closure.resourceId)}';
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final b = brandOf(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(S.lg, S.xs, S.lg, S.sm),
      child: Column(
        children: [
          for (final c in closures)
            Container(
              margin: const EdgeInsets.only(bottom: S.xs),
              padding:
                  const EdgeInsets.symmetric(horizontal: S.md, vertical: S.sm),
              decoration: BoxDecoration(
                color: b.secondary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: b.secondary.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  Icon(Icons.block, size: 16, color: b.primary),
                  const SizedBox(width: S.sm),
                  Expanded(
                    child: Text(
                      '${c.label} · ${c.rangeLabel}${_scopeOf(c)}',
                      style: t.textTheme.bodySmall,
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.close, size: 18),
                    tooltip: 'Sperre aufheben',
                    onPressed: () => onRemove(c),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.text, this.isError = false});

  final IconData icon;
  final String text;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final color = isError ? t.colorScheme.error : brandOf(context).secondary;
    return Container(
      margin: const EdgeInsets.fromLTRB(S.lg, S.sm, S.lg, 0),
      padding: const EdgeInsets.all(S.md),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: S.sm),
          Expanded(child: Text(text, style: t.textTheme.bodySmall)),
        ],
      ),
    );
  }
}
