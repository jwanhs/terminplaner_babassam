import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/brand.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/selectable_tile.dart';
import '../controllers/appointments_controller.dart';
import '../data/booking_api.dart';
import '../data/models.dart';
import '../data/token_store.dart';
import '../widgets/loyalty_card.dart';
import '../widgets/paid_badge.dart';
import '../widgets/section_header.dart';

class AppointmentsPage extends StatelessWidget {
  const AppointmentsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final c = Get.put(AppointmentsController(
      api: Get.find<BookingApi>(),
      tokens: Get.find<TokenStore>(),
    ));
    final t = Theme.of(context);
    final b = brandOf(context);

    return Scaffold(
      appBar: AppBar(
        title: Text('Meine Termine',
            style: t.textTheme.headlineSmall?.copyWith(color: b.primary)),
        backgroundColor: b.surface,
        elevation: 0,
        iconTheme: IconThemeData(color: b.primary),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: S.xxl),
        children: [
          // Bookings made on this device need no code at all — the manage
          // token is already here. The number + code path exists for a new
          // phone, and is what stopped this page handing anyone's history to
          // anyone who could guess their number.
          Obx(() {
            if (c.hasVerifiedPhone) {
              return _VerifiedBar(phone: c.phoneCtl.text, onReset: c.reset);
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionHeader('Auf einem anderen Gerät gebucht?'),
                Padding(
                  padding: const EdgeInsets.fromLTRB(S.lg, 0, S.lg, S.sm),
                  child: Text(
                    'Wir schicken dir einen Code per SMS, damit niemand sonst '
                    'deine Termine sehen kann.',
                    style: t.textTheme.bodySmall
                        ?.copyWith(color: t.colorScheme.onSurfaceVariant),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: S.lg),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: c.phoneCtl,
                          keyboardType: TextInputType.phone,
                          enabled: !c.awaitingCode.value,
                          onSubmitted: (_) => c.requestCode(),
                          decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.phone_outlined),
                            labelText: 'Deine Telefonnummer',
                          ),
                        ),
                      ),
                      const SizedBox(width: S.sm),
                      AppButton(
                        label: c.awaitingCode.value ? 'Neu' : 'Code',
                        loading: c.loading.value && !c.awaitingCode.value,
                        onPressed: c.loading.value ? null : c.requestCode,
                        backgroundColor: b.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: S.lg, vertical: S.md + 4),
                      ),
                    ],
                  ),
                ),
                if (c.awaitingCode.value) ...[
                  const SizedBox(height: S.sm),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: S.lg),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: c.codeCtl,
                            keyboardType: TextInputType.number,
                            maxLength: 6,
                            autofocus: true,
                            onSubmitted: (_) => c.verifyCode(),
                            decoration: const InputDecoration(
                              prefixIcon: Icon(Icons.sms_outlined),
                              labelText: '6-stelliger Code',
                              counterText: '',
                            ),
                          ),
                        ),
                        const SizedBox(width: S.sm),
                        AppButton(
                          label: 'Bestätigen',
                          loading: c.loading.value,
                          onPressed: c.loading.value ? null : c.verifyCode,
                          backgroundColor: b.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: S.lg, vertical: S.md + 4),
                        ),
                      ],
                    ),
                  ),
                ],
                // Only ever set when the backend is deliberately running
                // without an SMS provider, so a shop can pilot the flow.
                if (c.devCode.value != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(S.lg, 0, S.lg, S.sm),
                    child: Text('Testmodus — dein Code: ${c.devCode.value}',
                        style: t.textTheme.bodySmall
                            ?.copyWith(color: b.secondary)),
                  ),
                if (c.errorText.value != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(S.lg, S.xs, S.lg, S.sm),
                    child: Text(c.errorText.value!,
                        style: t.textTheme.bodySmall
                            ?.copyWith(color: t.colorScheme.error)),
                  ),
              ],
            );
          }),
          Obx(() {
            if (!c.searched.value) return const SizedBox.shrink();
            if (c.results.isEmpty) {
              return Padding(
                padding: const EdgeInsets.all(S.xl),
                child: Text('Keine Termine gefunden.',
                    style: t.textTheme.bodyMedium
                        ?.copyWith(color: t.colorScheme.onSurfaceVariant)),
              );
            }
            return Column(
              children: [
                if (c.card.value != null) LoyaltyCardView(card: c.card.value!),
                const SectionHeader('Buchungen'),
                ...c.results.map((a) => _AppointmentTile(
                      appt: a,
                      card: c.card.value,
                      // False only for a booking seen through a verified phone
                      // session that this device never made and cannot pay for.
                      canManage: c.canManage(a),
                      canPay: c.canPayOnline(a),
                      servicePriceCents: c.priceCentsFor(a.serviceId),
                      onCancel: () => c.cancel(a),
                      onReschedule: () => c.reschedule(a),
                      onAddToCalendar: () => c.addToCalendar(a),
                      onPayDeposit: () => c.payDeposit(a),
                      onRedeemReward: () => c.redeemReward(a),
                    )),
              ],
            );
          }),
        ],
      ),
    );
  }
}

/// Shown once a phone number has been confirmed by code. The session is short
/// lived by design, so the way out is offered rather than hidden.
class _VerifiedBar extends StatelessWidget {
  const _VerifiedBar({required this.phone, required this.onReset});

  final String phone;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final b = brandOf(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(S.lg, S.md, S.lg, S.sm),
      padding: const EdgeInsets.symmetric(horizontal: S.md, vertical: S.sm),
      decoration: BoxDecoration(
        color: b.secondary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: b.secondary.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(Icons.verified_user_outlined, size: 18, color: b.primary),
          const SizedBox(width: S.sm),
          Expanded(
            child: Text(
              phone.isEmpty ? 'Nummer bestätigt' : 'Bestätigt: $phone',
              style: t.textTheme.bodySmall,
            ),
          ),
          TextButton(onPressed: onReset, child: const Text('Andere Nummer')),
        ],
      ),
    );
  }
}

class _AppointmentTile extends StatelessWidget {
  const _AppointmentTile({
    required this.appt,
    required this.card,
    required this.canManage,
    required this.canPay,
    required this.servicePriceCents,
    required this.onCancel,
    required this.onReschedule,
    required this.onAddToCalendar,
    required this.onPayDeposit,
    required this.onRedeemReward,
  });

  final Appointment appt;
  final LoyaltyCard? card;

  /// Whether this device can prove the booking is the caller's.
  final bool canManage;

  /// Online payment additionally needs the booking's own manage token; a
  /// phone session is not enough to move money.
  final bool canPay;

  final int? servicePriceCents;
  final VoidCallback onCancel;
  final VoidCallback onReschedule;
  final VoidCallback onAddToCalendar;
  final VoidCallback onPayDeposit;
  final VoidCallback onRedeemReward;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final b = brandOf(context);
    final cancelled = appt.isCancelled;
    final upcoming = appt.isUpcoming(DateTime.now().toUtc());

    // Amount still owed online = service price minus any loyalty discount.
    // null when the price isn't loaded yet; 0 means a fully-covered free cut.
    final price = servicePriceCents;
    final netCents =
        price == null ? null : (price - appt.discountCents).clamp(0, price);
    final payLabel = netCents == null
        ? 'Online bezahlen'
        : 'Bezahlen €${(netCents / 100).toStringAsFixed(2)}';

    return Padding(
      padding: const EdgeInsets.fromLTRB(S.lg, 0, S.lg, S.sm),
      child: Container(
        padding: const EdgeInsets.all(S.md),
        decoration: BoxDecoration(
          color: b.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: b.secondary.withValues(alpha: 0.35),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(appt.serviceName,
                          style: t.textTheme.titleMedium?.copyWith(
                            decoration:
                                cancelled ? TextDecoration.lineThrough : null,
                          )),
                      const SizedBox(height: 2),
                      Text(appt.whenLabel,
                          style: t.textTheme.bodyMedium?.copyWith(
                            color: t.colorScheme.onSurfaceVariant,
                          )),
                      if (cancelled)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text('Storniert',
                              style: t.textTheme.labelSmall?.copyWith(
                                color: t.colorScheme.error,
                                letterSpacing: 1.4,
                              )),
                        ),
                      if (appt.rewardRedeemed && !cancelled)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: _FreeCutLine(originalCents: servicePriceCents),
                        ),
                    ],
                  ),
                ),
                if ((appt.paid || appt.rewardRedeemed) && !cancelled)
                  Padding(
                    padding: const EdgeInsets.only(left: S.sm),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        if (appt.paid) const PaidBadge(label: 'Bezahlt'),
                        if (appt.rewardRedeemed) ...[
                          if (appt.paid) const SizedBox(height: 4),
                          const _RewardBadge(),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
            if (upcoming && canManage) ...[
              const SizedBox(height: S.sm),
              Wrap(
                spacing: S.sm,
                runSpacing: S.sm,
                children: [
                  _ActionChip(
                    icon: Icons.event_available,
                    label: 'Kalender',
                    onTap: onAddToCalendar,
                  ),
                  _ActionChip(
                    icon: Icons.schedule,
                    label: 'Verschieben',
                    onTap: onReschedule,
                  ),
                  if (card != null && card!.hasReward && !appt.rewardRedeemed)
                    _ActionChip(
                      icon: Icons.card_giftcard,
                      label: 'Gratis-Schnitt einlösen',
                      onTap: onRedeemReward,
                      highlight: true,
                    ),
                  if (!appt.paid && netCents != 0 && canPay)
                    _ActionChip(
                      icon: Icons.euro_symbol,
                      label: payLabel,
                      onTap: onPayDeposit,
                      // Demote to a quiet chip when the free-cut CTA is present,
                      // so there's a single dominant action per tile.
                      highlight: !(card != null &&
                          card!.hasReward &&
                          !appt.rewardRedeemed),
                    ),
                  _ActionChip(
                    icon: Icons.close,
                    label: 'Stornieren',
                    onTap: onCancel,
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Pill-shaped action button shown beneath an appointment summary.
///
/// Built on [SelectableTile] — so it has the right ripple, semantics,
/// and tap-target on mobile, even though the visual is a chip rather
/// than a Material button.
class _ActionChip extends StatelessWidget {
  const _ActionChip({
    required this.icon,
    required this.label,
    required this.onTap,
    this.highlight = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final b = brandOf(context);
    final fg = highlight ? Colors.white : b.primary;
    final bg = highlight ? b.primary : b.surface;
    final border = highlight ? b.primary : b.secondary.withValues(alpha: 0.55);

    return SelectableTile(
      selected: highlight,
      onTap: onTap,
      borderRadius: 999,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      backgroundColor: bg,
      selectedBackgroundColor: bg,
      borderColor: border,
      selectedBorderColor: border,
      borderWidth: 1,
      selectedBorderWidth: 1,
      semanticLabel: label,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: fg),
          const SizedBox(width: 6),
          Text(label,
              style: t.textTheme.labelMedium?.copyWith(
                color: fg,
                fontWeight: FontWeight.w600,
              )),
        ],
      ),
    );
  }
}

/// Badge marking an appointment as a redeemed free cut (loyalty reward).
/// Mirrors [PaidBadge] but in antique gold with a gift icon.
class _RewardBadge extends StatelessWidget {
  const _RewardBadge();

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
          Icon(Icons.card_giftcard, size: 14, color: b.secondary),
          const SizedBox(width: 4),
          Text('Gratis-Schnitt',
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

/// "€X  Gratis" line shown beneath a redeemed appointment — the original price
/// struck through, the reward called out. Falls back to just "Gratis" when the
/// service price isn't known.
class _FreeCutLine extends StatelessWidget {
  const _FreeCutLine({required this.originalCents});

  final int? originalCents;

  @override
  Widget build(BuildContext context) {
    final b = brandOf(context);
    final t = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (originalCents != null && originalCents! > 0) ...[
          Text('€${(originalCents! / 100).toStringAsFixed(2)}',
              style: t.textTheme.bodySmall?.copyWith(
                color: t.colorScheme.onSurfaceVariant,
                decoration: TextDecoration.lineThrough,
              )),
          const SizedBox(width: 6),
        ],
        Text('Gratis',
            style: t.textTheme.bodyMedium?.copyWith(
              color: b.secondary,
              fontWeight: FontWeight.w700,
            )),
      ],
    );
  }
}
