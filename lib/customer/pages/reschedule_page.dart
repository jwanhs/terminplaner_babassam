import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/brand.dart';
import '../../core/shop_time.dart';
import '../../core/widgets/app_button.dart';
import '../controllers/reschedule_controller.dart';
import '../data/booking_api.dart';
import '../data/models.dart';
import '../widgets/date_strip.dart';
import '../widgets/section_header.dart';
import '../widgets/time_slot_grid.dart';

/// Pick a new date/time for an existing [Appointment]. The service stays
/// locked; only the start moves.
///
/// [auth] is the caller's proof that this booking is theirs — the manage token
/// minted when it was made, or a verified phone session. The server refuses the
/// move without it, so the page cannot be reached without one.
class ReschedulePage extends StatelessWidget {
  const ReschedulePage({super.key, required this.original, required this.auth});

  final Appointment original;
  final String auth;

  @override
  Widget build(BuildContext context) {
    final tag = original.id;
    Get.put(
      RescheduleController(
        original: original,
        auth: auth,
        api: Get.find<BookingApi>(),
      ),
      tag: tag,
    );
    final t = Theme.of(context);
    final b = brandOf(context);

    return Scaffold(
      appBar: AppBar(
        title: Text('Termin verschieben',
            style: t.textTheme.headlineSmall?.copyWith(color: b.primary)),
        backgroundColor: b.surface,
        elevation: 0,
        iconTheme: IconThemeData(color: b.primary),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: S.xxl),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(S.lg, S.lg, S.lg, 0),
            child: Container(
              padding: const EdgeInsets.all(S.md),
              decoration: BoxDecoration(
                color: b.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: b.secondary.withValues(alpha: 0.35)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('AKTUELLER TERMIN',
                      style: t.textTheme.labelSmall
                          ?.copyWith(color: b.secondary, letterSpacing: 1.4)),
                  const SizedBox(height: 4),
                  Text(original.serviceName, style: t.textTheme.titleMedium),
                  Text(original.whenLabel,
                      style: t.textTheme.bodyMedium
                          ?.copyWith(color: t.colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
          ),
          const SectionHeader('Neues Datum'),
          _ResDateStrip(tag: tag),
          const SectionHeader('Neue Uhrzeit'),
          _ResSlotGrid(tag: tag),
        ],
      ),
      bottomNavigationBar: _ResBottomBar(tag: tag),
    );
  }
}

class _ResDateStrip extends StatelessWidget {
  const _ResDateStrip({required this.tag});
  final String tag;

  @override
  Widget build(BuildContext context) {
    final c = Get.find<RescheduleController>(tag: tag);

    return SizedBox(
      height: 88,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: S.lg),
        itemCount: c.dateStrip.length,
        separatorBuilder: (_, __) => const SizedBox(width: S.sm),
        itemBuilder: (_, i) {
          final d = c.dateStrip[i];
          return Obx(() {
            // Shop-local day throughout: `d` is an instant, and reading its
            // raw fields would name the wrong date on either side of UTC.
            final selected =
                ShopTime.dateKey(c.selectedDate.value) == ShopTime.dateKey(d);
            final wall = ShopTime.toShopWall(d);
            final closed = c.hours[wall.weekday - 1]?.closed ?? false;
            return DateTile(
              date: d,
              selected: selected,
              closed: closed,
              onTap: closed ? null : () => c.pickDate(d),
            );
          });
        },
      ),
    );
  }
}

class _ResSlotGrid extends StatelessWidget {
  const _ResSlotGrid({required this.tag});
  final String tag;

  @override
  Widget build(BuildContext context) {
    final c = Get.find<RescheduleController>(tag: tag);
    final t = Theme.of(context);

    return Obx(() {
      if (c.loadingSlots.value) {
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: S.xl),
          child: Center(child: CircularProgressIndicator()),
        );
      }
      if (c.slots.isEmpty) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(S.lg, S.md, S.lg, S.lg),
          child: Text(
              c.emptyReason.value ??
                  'An diesem Tag ist nichts frei — bitte einen anderen Tag wählen.',
              style: t.textTheme.bodyMedium
                  ?.copyWith(color: t.colorScheme.onSurfaceVariant)),
        );
      }
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: S.lg),
        child: Wrap(
          spacing: S.sm,
          runSpacing: S.sm,
          children: c.slots
              .map((s) => SlotChip(
                    slot: s,
                    selected: c.selectedSlot.value?.start == s.start,
                    onTap: () => c.pickSlot(s),
                  ))
              .toList(),
        ),
      );
    });
  }
}

class _ResBottomBar extends StatelessWidget {
  const _ResBottomBar({required this.tag});
  final String tag;

  @override
  Widget build(BuildContext context) {
    final c = Get.find<RescheduleController>(tag: tag);
    final t = Theme.of(context);
    final b = brandOf(context);

    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: b.surface,
          border: Border(
              top: BorderSide(color: b.secondary.withValues(alpha: 0.4))),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              offset: const Offset(0, -4),
              blurRadius: 12,
            ),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(S.lg, S.md, S.lg, S.md),
        child: Obx(() {
          final slot = c.selectedSlot.value;
          final summary = slot == null
              ? 'Neue Uhrzeit wählen'
              : '${slot.start.day.toString().padLeft(2, '0')}.'
                  '${slot.start.month.toString().padLeft(2, '0')}  '
                  '${slot.start.hour.toString().padLeft(2, '0')}:'
                  '${slot.start.minute.toString().padLeft(2, '0')}';

          return Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('NEUE ZEIT',
                        style: t.textTheme.labelSmall
                            ?.copyWith(color: b.secondary, letterSpacing: 1.6)),
                    const SizedBox(height: 2),
                    Text(summary, style: t.textTheme.titleSmall),
                  ],
                ),
              ),
              const SizedBox(width: S.md),
              AppButton(
                label: 'Verschieben',
                loading: c.submitting.value,
                onPressed: c.canSubmit
                    ? () async {
                        final updated = await c.submit();
                        if (updated != null) {
                          Get.back(result: updated);
                        }
                      }
                    : null,
                backgroundColor: b.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                    horizontal: S.xl, vertical: S.md + 2),
              ),
            ],
          );
        }),
      ),
    );
  }
}
