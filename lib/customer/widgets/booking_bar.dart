import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/brand.dart';
import '../../core/widgets/app_button.dart';
import '../controllers/booking_controller.dart';

/// Pinned bottom bar: live summary of the booking + confirm CTA.
/// Always present, so the user has constant feedback on what they're about
/// to commit to.
class BookingBar extends StatelessWidget {
  const BookingBar({super.key});

  @override
  Widget build(BuildContext context) {
    final c = Get.find<BookingController>();
    final t = Theme.of(context);
    final b = brandOf(context);

    return GetBuilder<BookingController>(
      builder: (_) => Obx(() {
        final svc = c.selectedService;
        final slot = c.selectedSlot.value;
        final summary = (svc == null || slot == null)
            ? 'Leistung und Uhrzeit wählen'
            : '${svc.name}\n${slot.label}';

        // Pinned to the bottom edge by `Scaffold.bottomNavigationBar`. The
        // system bottom inset (home indicator, gesture bar) is absorbed as
        // *padding inside* this container so the surface colour extends all
        // the way to the device edge — do not wrap in a SafeArea or that gap
        // would come back.
        return Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: b.surface,
            border: Border(
              top: BorderSide(color: b.secondary.withValues(alpha: 0.40)),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                offset: const Offset(0, -4),
                blurRadius: 12,
              ),
            ],
          ),
          padding: EdgeInsets.fromLTRB(
            S.lg,
            S.md,
            S.lg,
            S.md + MediaQuery.of(context).padding.bottom,
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final summaryBlock = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('DEINE BUCHUNG',
                      style: t.textTheme.labelSmall?.copyWith(
                        color: b.secondary,
                        letterSpacing: 1.6,
                      )),
                  const SizedBox(height: 2),
                  Text(summary,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: t.textTheme.titleSmall),
                ],
              );

              final priceText = Text(
                slot != null ? '€${svc?.price.toStringAsFixed(2)}' : '',
                style: t.textTheme.titleMedium?.copyWith(
                  color: b.primary,
                  fontWeight: FontWeight.bold,
                ),
              );

              final button = AppButton(
                label: 'Bestätigen',
                loading: c.submitting.value,
                onPressed: c.canSubmit ? c.submit : null,
                backgroundColor: b.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                    horizontal: S.xl, vertical: S.md + 2),
                semanticLabel: 'Buchung bestätigen',
              );

              if (constraints.maxWidth < 360) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    summaryBlock,
                    const SizedBox(height: S.md),
                    Row(
                      children: [
                        Flexible(child: priceText),
                        const SizedBox(width: S.md),
                        Flexible(child: button),
                      ],
                    ),
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(child: summaryBlock),
                  priceText,
                  const SizedBox(width: S.md),
                  button,
                ],
              );
            },
          ),
        );
      }),
    );
  }
}
