import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/brand.dart';
import '../pages/appointments_page.dart';

/// Top masthead: tight type, gold rule, subtle barber-pole flourish.
/// Deliberately minimal — the brand should feel confident, not loud.
class BrandHeader extends StatelessWidget {
  const BrandHeader({super.key, required this.brand});
  final BrandIdentity brand;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    // Extend the header's surface colour behind the status bar by absorbing
    // the system top inset into our own padding instead of relying on a
    // SafeArea ancestor (which would paint the scaffold background there).
    final topInset = MediaQuery.of(context).padding.top;
    return Container(
      padding: EdgeInsets.fromLTRB(S.lg, S.xxl + topInset, S.lg, S.lg),
      decoration: BoxDecoration(
        color: brand.surface,
        border: Border(
          bottom: BorderSide(color: brand.secondary, width: 1.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _PoleMark(primary: brand.primary, secondary: brand.secondary),
              const SizedBox(width: S.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(brand.businessName,
                        style: t.textTheme.displaySmall?.copyWith(
                          color: brand.primary,
                          fontWeight: FontWeight.w700,
                        )),
                    const SizedBox(height: 2),
                    Text(brand.tagline.toUpperCase(),
                        style: t.textTheme.labelSmall?.copyWith(
                          color: brand.secondary,
                          letterSpacing: 1.6,
                        )),
                  ],
                ),
              ),
              _AppointmentsButton(brand: brand),
            ],
          ),
        ],
      ),
    );
  }
}

/// Right-side affordance: appointment icon with a label beneath it.
///
/// Uses [IconButton] so we get the 48 dp tap target, focus ring, ripple,
/// and tooltip for free — instead of the bespoke `InkWell` + tight padding
/// version, which sat well under the recommended mobile tap-target size.
class _AppointmentsButton extends StatelessWidget {
  const _AppointmentsButton({required this.brand});
  final BrandIdentity brand;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Tooltip(
      message: 'Termine ansehen',
      child: IconButton(
        onPressed: () => Get.to(() => const AppointmentsPage()),
        iconSize: 24,
        padding: const EdgeInsets.symmetric(horizontal: S.sm, vertical: S.xs),
        style: IconButton.styleFrom(
          foregroundColor: brand.primary,
          minimumSize: const Size(48, 48),
        ),
        icon: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.event_note_outlined, color: brand.primary),
            const SizedBox(height: 2),
            Text('Termine',
                style: t.textTheme.labelSmall?.copyWith(
                  color: brand.primary,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.6,
                )),
          ],
        ),
      ),
    );
  }
}

/// A tiny stylised barber pole — red/white/blue stripes simplified to brand
/// tones. SVG-free, draws with a CustomPainter so it scales crisply.
/// A barber scissor sits centered on top as the focal mark.
class _PoleMark extends StatelessWidget {
  const _PoleMark({required this.primary, required this.secondary});
  final Color primary;
  final Color secondary;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 40,
      height: 56,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: CustomPaint(painter: _PolePainter(primary, secondary)),
          ),
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFFFBF6EB),
              border: Border.all(color: secondary, width: 1),
            ),
          ),
          Transform.rotate(
            angle: -0.785398, // -45° so blades point up-left
            child: const Icon(Icons.content_cut, size: 18, color: Colors.black),
          ),
        ],
      ),
    );
  }
}

class _PolePainter extends CustomPainter {
  _PolePainter(this.primary, this.secondary);
  final Color primary;
  final Color secondary;

  @override
  void paint(Canvas canvas, Size size) {
    final rr = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(6),
    );
    // Cream backing.
    canvas.drawRRect(rr, Paint()..color = const Color(0xFFFBF6EB));
    // Diagonal stripes — primary on cream, then a gold band.
    canvas.save();
    canvas.clipRRect(rr);
    final stripe = Paint()..color = primary;
    final step = 10.0;
    for (var x = -size.height; x < size.width + size.height; x += step * 2) {
      final p = Path()
        ..moveTo(x, size.height)
        ..lineTo(x + step, size.height)
        ..lineTo(x + step + size.height, 0)
        ..lineTo(x + size.height, 0)
        ..close();
      canvas.drawPath(p, stripe);
    }
    canvas.restore();
    // Gold caps.
    final cap = Paint()..color = secondary;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, 4), cap);
    canvas.drawRect(Rect.fromLTWH(0, size.height - 4, size.width, 4), cap);
    // Hairline border.
    canvas.drawRRect(
        rr,
        Paint()
          ..color = secondary
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1);
  }

  @override
  bool shouldRepaint(_PolePainter old) =>
      old.primary != primary || old.secondary != secondary;
}
