import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A selectable container with a visible ink ripple and built-in semantics.
///
/// Replaces the `InkWell` → `AnimatedContainer(decoration: …)` pattern that
/// hides the ripple under the container's solid fill. The fix is to nest a
/// transparent [Material] between the decorated container and the [InkWell]
/// so the splash paints *above* the decoration instead of below it.
///
/// Behaviour:
///   • Visible ripple regardless of background color.
///   • [HapticFeedback.selectionClick] on tap (the quiet "tick", which is
///     the iOS-native feel for picking an option).
///   • [Semantics] reports `selected` + `button` + `enabled` so screen
///     readers describe the state, not just the label.
///   • Tap target enforced via [minHeight] (default 48 dp).
class SelectableTile extends StatelessWidget {
  const SelectableTile({
    super.key,
    required this.selected,
    required this.onTap,
    required this.child,
    this.borderRadius = 12,
    this.padding,
    this.width,
    this.height,
    this.minHeight = 48,
    this.backgroundColor,
    this.selectedBackgroundColor,
    this.borderColor,
    this.selectedBorderColor,
    this.borderWidth = 1,
    this.selectedBorderWidth = 1.5,
    this.disabled = false,
    this.semanticLabel,
    this.animationDuration = const Duration(milliseconds: 160),
    this.boxShadow,
    this.opacity = 1.0,
  });

  final bool selected;
  final VoidCallback? onTap;
  final Widget child;
  final double borderRadius;
  final EdgeInsetsGeometry? padding;
  final double? width;
  final double? height;
  final double minHeight;
  final Color? backgroundColor;
  final Color? selectedBackgroundColor;
  final Color? borderColor;
  final Color? selectedBorderColor;
  final double borderWidth;
  final double selectedBorderWidth;
  final bool disabled;
  final String? semanticLabel;
  final Duration animationDuration;
  final List<BoxShadow>? boxShadow;

  /// Multiplier applied to the whole tile — used to dim closed/unavailable
  /// states without overriding every color individually.
  final double opacity;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(borderRadius);

    final bg = (selected ? selectedBackgroundColor : backgroundColor) ??
        (selected ? cs.primary : cs.surface);
    final border = (selected ? selectedBorderColor : borderColor) ??
        (selected ? cs.primary : cs.outlineVariant);

    final enabled = !disabled && onTap != null;
    final handler = enabled
        ? () {
            HapticFeedback.selectionClick();
            onTap!();
          }
        : null;

    return Semantics(
      label: semanticLabel,
      selected: selected,
      button: true,
      enabled: enabled,
      child: Opacity(
        opacity: opacity,
        child: AnimatedContainer(
          duration: animationDuration,
          width: width,
          height: height,
          constraints: BoxConstraints(minHeight: minHeight),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: radius,
            border: Border.all(
              color: border,
              width: selected ? selectedBorderWidth : borderWidth,
            ),
            boxShadow: boxShadow,
          ),
          // Material(transparent) sits between the decorated container and
          // the InkWell so the splash paints on the Material's surface,
          // which is *above* the AnimatedContainer's fill.
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: handler,
              borderRadius: radius,
              child: Padding(
                padding: padding ?? EdgeInsets.zero,
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
