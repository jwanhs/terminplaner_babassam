import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/brand.dart';
import '../data/models.dart';

/// One booking in the day view.
///
/// Reads left-to-right the way staff need it: when, who, what, and what is
/// still owed. Cancelled rows stay visible but struck through — a shop needs
/// to see the gap it left, not have it disappear.
class AppointmentTile extends StatelessWidget {
  const AppointmentTile({
    super.key,
    required this.appointment,
    required this.priceCents,
    required this.onStatus,
    required this.onMarkPaid,
    required this.onReschedule,
    this.now,
    this.chairName,
  });

  final StaffAppointment appointment;
  final int priceCents;

  /// The chair this booking sits on, or null in a shop with one chair — where
  /// naming it would be noise on every row of the day.
  final String? chairName;

  final void Function(ApptStatus) onStatus;
  final VoidCallback onMarkPaid;
  final VoidCallback onReschedule;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final b = brandOf(context);
    final a = appointment;
    final clock = now ?? DateTime.now().toUtc();

    final due = (priceCents - a.discountCents).clamp(0, 1 << 31);
    final needsClosing = a.needsClosing(clock);

    return Opacity(
      opacity: a.isCancelled ? 0.55 : 1,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: S.lg, vertical: S.xs),
        decoration: BoxDecoration(
          color: b.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: needsClosing
                ? b.secondary
                : b.secondary.withValues(alpha: 0.25),
            width: needsClosing ? 1.5 : 1,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(S.md, S.md, S.sm, S.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Time column
                  SizedBox(
                    width: 58,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          a.startLabel,
                          style: t.textTheme.titleMedium?.copyWith(
                            color: b.primary,
                            fontWeight: FontWeight.w700,
                            decoration: a.isCancelled
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                        ),
                        Text(
                          a.endLabel,
                          style: t.textTheme.bodySmall?.copyWith(
                            color: t.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: S.sm),

                  // Who and what
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          a.customerName,
                          style: t.textTheme.titleSmall?.copyWith(
                            decoration: a.isCancelled
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          a.serviceName,
                          style: t.textTheme.bodySmall?.copyWith(
                            color: t.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        if (a.notes?.trim().isNotEmpty ?? false) ...[
                          const SizedBox(height: 4),
                          Text(
                            a.notes!.trim(),
                            style: t.textTheme.bodySmall?.copyWith(
                              fontStyle: FontStyle.italic,
                              color: t.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  // Money
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '€${(due / 100).toStringAsFixed(2)}',
                        style: t.textTheme.titleSmall?.copyWith(
                          color: a.paid ? b.primary : t.colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      _StatusChip(appointment: a, needsClosing: needsClosing),
                    ],
                  ),
                ],
              ),

              // Badges
              Padding(
                padding: const EdgeInsets.only(left: 66, top: S.sm),
                child: Wrap(
                  spacing: S.xs,
                  runSpacing: S.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (chairName != null && chairName!.isNotEmpty)
                      _Badge(
                        icon: Icons.event_seat,
                        label: chairName!,
                        color: b.primary,
                      ),
                    if (a.paid)
                      _Badge(
                        icon: Icons.check_circle,
                        label: 'Bezahlt',
                        color: b.primary,
                      ),
                    if (a.rewardRedeemed)
                      _Badge(
                        icon: Icons.card_giftcard,
                        label: 'Treueprämie',
                        color: b.secondary,
                      ),
                    if (a.source != ApptSource.online)
                      _Badge(
                        icon: Icons.storefront,
                        label: a.source.label,
                        color: t.colorScheme.onSurfaceVariant,
                      ),
                  ],
                ),
              ),

              if (!a.isCancelled)
                Align(
                  alignment: Alignment.centerRight,
                  child: _Actions(
                    appointment: a,
                    onStatus: onStatus,
                    onMarkPaid: onMarkPaid,
                    onReschedule: onReschedule,
                    onCall: a.hasRealPhone
                        ? () => Clipboard.setData(
                            ClipboardData(text: a.customerPhone))
                        : null,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.appointment, required this.needsClosing});

  final StaffAppointment appointment;
  final bool needsClosing;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final (label, color) = switch (appointment.status) {
      ApptStatus.cancelled => ('Storniert', t.colorScheme.error),
      ApptStatus.completed => ('Erledigt', t.colorScheme.onSurfaceVariant),
      ApptStatus.noShow => ('No-Show', t.colorScheme.error),
      // A past booking nobody has marked done or no-show. Says what to do
      // about it rather than repeating "Offen", which the stats bar already
      // uses for bookings still to come.
      ApptStatus.confirmed => needsClosing
          ? ('Abschließen', brandOf(context).secondary)
          : ('Bestätigt', t.colorScheme.onSurfaceVariant),
    };
    return Text(
      label,
      style: t.textTheme.labelSmall?.copyWith(color: color),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.icon, required this.label, required this.color});

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 3),
        Text(label, style: t.textTheme.labelSmall?.copyWith(color: color)),
      ],
    );
  }
}

/// Closing a booking out is the action staff take dozens of times a day, so
/// "Erledigt" is a button rather than something buried in a menu. Everything
/// rarer lives behind the overflow.
class _Actions extends StatelessWidget {
  const _Actions({
    required this.appointment,
    required this.onStatus,
    required this.onMarkPaid,
    required this.onReschedule,
    this.onCall,
  });

  final StaffAppointment appointment;
  final void Function(ApptStatus) onStatus;
  final VoidCallback onMarkPaid;
  final VoidCallback onReschedule;
  final VoidCallback? onCall;

  @override
  Widget build(BuildContext context) {
    final a = appointment;
    final open = a.status == ApptStatus.confirmed;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (open)
          TextButton.icon(
            onPressed: () => onStatus(ApptStatus.completed),
            icon: const Icon(Icons.check, size: 18),
            label: const Text('Erledigt'),
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: S.sm),
            ),
          ),
        PopupMenuButton<String>(
          tooltip: 'Weitere Aktionen',
          icon: const Icon(Icons.more_horiz, size: 20),
          onSelected: (value) {
            switch (value) {
              case 'paid':
                onMarkPaid();
              case 'reschedule':
                onReschedule();
              case 'no_show':
                onStatus(ApptStatus.noShow);
              case 'cancel':
                onStatus(ApptStatus.cancelled);
              case 'reopen':
                onStatus(ApptStatus.confirmed);
              case 'copy':
                onCall?.call();
            }
          },
          itemBuilder: (context) => [
            if (!a.paid)
              const PopupMenuItem(
                value: 'paid',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.euro_symbol),
                  title: Text('Bar bezahlt'),
                ),
              ),
            if (open)
              const PopupMenuItem(
                value: 'reschedule',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.schedule),
                  title: Text('Verschieben'),
                ),
              ),
            if (onCall != null)
              PopupMenuItem(
                value: 'copy',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.phone),
                  title: Text(a.customerPhone),
                  subtitle: const Text('Nummer kopieren'),
                ),
              ),
            if (open) ...[
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'no_show',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.person_off_outlined),
                  title: Text('Nicht erschienen'),
                ),
              ),
              const PopupMenuItem(
                value: 'cancel',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.event_busy),
                  title: Text('Stornieren'),
                ),
              ),
            ] else
              const PopupMenuItem(
                value: 'reopen',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.undo),
                  title: Text('Wieder öffnen'),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
