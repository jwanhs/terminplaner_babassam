import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/brand.dart';
import '../../core/widgets/selectable_tile.dart';
import '../controllers/booking_controller.dart';
import '../data/models.dart';

/// The time grid.
///
/// Every chip here is bookable. Taken times are not greyed out — they are
/// absent, because the server never tells the app which slots are occupied,
/// only which are free. Knowing that 14:30 is taken is knowing that *somebody*
/// is in that chair at 14:30, and a public booking page has no business
/// publishing the shop's occupancy.
class TimeSlotGrid extends StatelessWidget {
  const TimeSlotGrid({super.key});

  @override
  Widget build(BuildContext context) {
    final c = Get.find<BookingController>();
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
            c.selectedService == null
                ? 'Wähle eine Leistung, um die Uhrzeiten zu sehen.'
                : c.emptyReason.value ??
                    'An diesem Tag ist nichts frei — bitte einen anderen Tag wählen.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
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

/// One bookable time. Shared with the reschedule page so both grids stay
/// identical — they are the same decision made twice.
class SlotChip extends StatelessWidget {
  const SlotChip({
    super.key,
    required this.slot,
    required this.selected,
    required this.onTap,
  });

  final Slot slot;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final b = brandOf(context);

    final bg = selected ? b.primary : b.surface;
    final fg = selected ? Colors.white : t.colorScheme.onSurface;
    final border = selected ? b.primary : b.secondary.withValues(alpha: 0.45);

    return SelectableTile(
      selected: selected,
      onTap: onTap,
      width: 71,
      minHeight: 48,
      borderRadius: 12,
      padding: const EdgeInsets.symmetric(vertical: 11),
      backgroundColor: bg,
      selectedBackgroundColor: bg,
      borderColor: border,
      selectedBorderColor: border,
      borderWidth: 1.2,
      selectedBorderWidth: 1.2,
      animationDuration: const Duration(milliseconds: 140),
      // The label is the shop's own wall clock, formatted server-side — not
      // re-derived from the instant through the device's timezone.
      semanticLabel: slot.label,
      child: Center(
        child: Text(
          slot.label,
          style: t.textTheme.titleSmall?.copyWith(color: fg),
        ),
      ),
    );
  }
}
