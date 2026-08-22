import 'package:flutter/material.dart';

import '../../core/brand.dart';

/// Small pill badge that marks an appointment as "deposit paid".
/// Pulls colours from [brandOf] so it works in both light & dark themes.
class PaidBadge extends StatelessWidget {
  const PaidBadge({super.key, this.label = 'Anzahlung bezahlt'});

  final String label;

  @override
  Widget build(BuildContext context) {
    final b = brandOf(context);
    final t = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: b.secondary.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: b.secondary.withValues(alpha: 0.55)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle, size: 14, color: b.secondary),
          const SizedBox(width: 4),
          Text(label,
              style: t.textTheme.labelSmall?.copyWith(
                color: b.onSurface,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.4,
              )),
        ],
      ),
    );
  }
}
