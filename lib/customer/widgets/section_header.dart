import 'package:flutter/material.dart';

import '../../core/brand.dart';

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.label, {super.key, this.trailing});
  final String label;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final b = brandOf(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(S.lg, S.xl, S.lg, S.sm),
      child: Row(
        children: [
          Text(label.toUpperCase(),
              style: t.textTheme.labelMedium?.copyWith(
                color: b.secondary,
                letterSpacing: 1.8,
                fontWeight: FontWeight.w600,
              )),
          const SizedBox(width: S.sm),
          Expanded(
              child: Container(
                  height: 1, color: b.secondary.withValues(alpha: 0.30))),
          if (trailing != null) ...[const SizedBox(width: S.sm), trailing!],
        ],
      ),
    );
  }
}
