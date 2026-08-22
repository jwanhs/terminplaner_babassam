import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Visual variant. Maps to the underlying Material 3 button kind.
enum AppButtonVariant { filled, outlined, text }

/// Mobile-first wrapper around Material 3 buttons.
///
/// Guarantees:
///   • 48 dp minimum tap target (Material/iOS HIG).
///   • Light haptic on tap (selectionClick — quieter than impact).
///   • Loading state replaces the label with a same-sized spinner and
///     suppresses presses, so callers never have to gate `onPressed` on
///     a separate `submitting` flag to avoid double-submits.
///   • Theme-driven colors: pass [backgroundColor]/[foregroundColor] only
///     to override the active theme. The default is the theme's button
///     styling, not a per-call-site recolor.
class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = AppButtonVariant.filled,
    this.icon,
    this.loading = false,
    this.expand = false,
    this.backgroundColor,
    this.foregroundColor,
    this.padding,
    this.semanticLabel,
  });

  final String label;
  final VoidCallback? onPressed;
  final AppButtonVariant variant;
  final IconData? icon;
  final bool loading;

  /// If true, stretches to the parent's full width.
  final bool expand;

  final Color? backgroundColor;
  final Color? foregroundColor;
  final EdgeInsetsGeometry? padding;

  /// Screen-reader label. Falls back to [label] when unset.
  final String? semanticLabel;

  static const Size _minSize = Size(64, 48);

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;
    final handler = enabled
        ? () {
            HapticFeedback.selectionClick();
            onPressed!();
          }
        : null;

    final spinnerColor = foregroundColor ??
        (variant == AppButtonVariant.filled
            ? Theme.of(context).colorScheme.onPrimary
            : Theme.of(context).colorScheme.primary);

    final child = loading
        ? SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2.4,
              valueColor: AlwaysStoppedAnimation<Color>(spinnerColor),
            ),
          )
        : (icon == null
            ? Text(label)
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 18),
                  const SizedBox(width: 8),
                  Flexible(child: Text(label)),
                ],
              ));

    Widget button;
    switch (variant) {
      case AppButtonVariant.filled:
        button = FilledButton(
          onPressed: handler,
          style: FilledButton.styleFrom(
            minimumSize: _minSize,
            backgroundColor: backgroundColor,
            foregroundColor: foregroundColor,
            padding: padding,
          ),
          child: child,
        );
      case AppButtonVariant.outlined:
        button = OutlinedButton(
          onPressed: handler,
          style: OutlinedButton.styleFrom(
            minimumSize: _minSize,
            foregroundColor: foregroundColor,
            padding: padding,
          ),
          child: child,
        );
      case AppButtonVariant.text:
        button = TextButton(
          onPressed: handler,
          style: TextButton.styleFrom(
            minimumSize: _minSize,
            foregroundColor: foregroundColor,
            padding: padding,
          ),
          child: child,
        );
    }

    final wrapped = Semantics(
      label: semanticLabel ?? label,
      button: true,
      enabled: enabled,
      child: button,
    );

    return expand ? SizedBox(width: double.infinity, child: wrapped) : wrapped;
  }
}
