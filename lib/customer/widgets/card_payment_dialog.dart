import 'package:flutter/material.dart';
import 'package:flutter_stripe/flutter_stripe.dart';

import '../../core/brand.dart';

/// A card-entry dialog that confirms a Stripe PaymentIntent directly, instead
/// of `PaymentSheet` — which flutter_stripe never implemented for web. This
/// path (`CardField` + `Stripe.instance.confirmPayment`) is the one part of
/// the SDK that actually is cross-platform: on web it binds to a Stripe
/// Elements card iframe, on iOS/Android to the native card field, and
/// `confirmPayment` reads whichever of those is currently mounted.
///
/// Pops with `true` on a successful confirmation, `false` on a card error the
/// customer can retry, or `null` if they dismissed the dialog.
class CardPaymentDialog extends StatefulWidget {
  const CardPaymentDialog({
    super.key,
    required this.clientSecret,
    required this.amountCents,
  });

  final String clientSecret;
  final int amountCents;

  @override
  State<CardPaymentDialog> createState() => _CardPaymentDialogState();
}

class _CardPaymentDialogState extends State<CardPaymentDialog> {
  bool _cardComplete = false;
  bool _submitting = false;
  String? _error;

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final intent = await Stripe.instance.confirmPayment(
        paymentIntentClientSecret: widget.clientSecret,
        data: const PaymentMethodParams.card(
          paymentMethodData: PaymentMethodData(),
        ),
      );
      if (!mounted) return;
      if (intent.status == PaymentIntentsStatus.Succeeded) {
        Navigator.of(context).pop(true);
      } else {
        // Requires further action Stripe couldn't resolve inline, or the
        // intent otherwise didn't land — the booking API poll after this
        // dialog closes is what decides "paid" either way.
        setState(() {
          _submitting = false;
          _error = 'Zahlung konnte nicht abgeschlossen werden.';
        });
      }
    } on StripeException catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = e.error.localizedMessage ?? e.error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = 'Zahlung fehlgeschlagen. Bitte erneut versuchen.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = brandOf(context);
    final t = Theme.of(context);
    return AlertDialog(
      title: Text(
          'Kartenzahlung €${(widget.amountCents / 100).toStringAsFixed(2)}'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CardField(
              enablePostalCode: false,
              style: t.textTheme.bodyMedium,
              decoration: InputDecoration(
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide:
                      BorderSide(color: b.secondary.withValues(alpha: 0.5)),
                ),
              ),
              onCardChanged: (details) {
                setState(() => _cardComplete = details?.complete ?? false);
              },
            ),
            if (_error != null) ...[
              const SizedBox(height: S.sm),
              Text(_error!, style: TextStyle(color: t.colorScheme.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(null),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: _cardComplete && !_submitting ? _submit : null,
          child: _submitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Bezahlen'),
        ),
      ],
    );
  }
}
