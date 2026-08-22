import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/brand.dart';
import '../../core/widgets/selectable_tile.dart';
import '../controllers/booking_controller.dart';
import '../data/models.dart';

class ServicePicker extends StatelessWidget {
  const ServicePicker({super.key});

  @override
  Widget build(BuildContext context) {
    final c = Get.find<BookingController>();
    return Obx(() {
      if (c.loadingServices.value && c.services.isEmpty) {
        return const SizedBox(
          height: 110,
          child: Center(child: CircularProgressIndicator()),
        );
      }
      if (c.services.isEmpty) {
        return _emptyState(context);
      }
      return SizedBox(
        height: 130,
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: S.lg),
          scrollDirection: Axis.horizontal,
          itemCount: c.services.length,
          separatorBuilder: (_, __) => const SizedBox(width: S.md),
          itemBuilder: (_, i) {
            final s = c.services[i];
            return Obx(() {
              final selected = c.selectedServiceId.value == s.id;
              return _ServiceCard(
                service: s,
                selected: selected,
                onTap: () => c.pickService(s.id),
              );
            });
          },
        ),
      );
    });
  }

  Widget _emptyState(BuildContext context) => Padding(
        padding: const EdgeInsets.all(S.lg),
        child: Text(
          'Keine Leistungen gefunden. infra/setup_barber_db.sh und infra/seed_barber_db.sh ausführen, um sie anzulegen.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      );
}

class _ServiceCard extends StatelessWidget {
  const _ServiceCard({
    required this.service,
    required this.selected,
    required this.onTap,
  });

  final Service service;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final b = brandOf(context);
    return SelectableTile(
      selected: selected,
      onTap: onTap,
      width: 170,
      borderRadius: 18,
      padding: const EdgeInsets.all(S.md),
      backgroundColor: b.surface,
      selectedBackgroundColor: b.primary,
      borderColor: b.secondary.withValues(alpha: 0.7),
      selectedBorderColor: b.secondary.withValues(alpha: 0.7),
      selectedBorderWidth: 1.9,
      animationDuration: const Duration(milliseconds: 180),
      boxShadow: selected
          ? [
              BoxShadow(
                color: b.primary.withValues(alpha: 0.18),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ]
          : null,
      semanticLabel:
          '${service.name}, ${service.durationMinutes} Minuten, ${service.price.toStringAsFixed(2)} Euro',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            service.name,
            style: t.textTheme.titleMedium?.copyWith(
              color: selected ? Colors.white : t.colorScheme.onSurface,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const Spacer(),
          Row(
            children: [
              Icon(Icons.schedule,
                  size: 14, color: selected ? Colors.white70 : b.secondary),
              const SizedBox(width: 4),
              Text(
                '${service.durationMinutes} Min.',
                style: t.textTheme.labelSmall?.copyWith(
                  color: selected
                      ? Colors.white70
                      : t.colorScheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              Text(
                '€${service.price.toStringAsFixed(2)}',
                style: t.textTheme.titleSmall?.copyWith(
                  color: selected ? Colors.white : b.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
