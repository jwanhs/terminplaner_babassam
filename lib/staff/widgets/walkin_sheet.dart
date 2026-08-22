import 'package:flutter/material.dart';

import '../../core/brand.dart';
import '../../core/shop_time.dart';
import '../../core/widgets/app_button.dart';
import '../data/models.dart';

/// Enter someone who walked in off the street.
///
/// Deliberately looser than the customer flow: no phone number required, no
/// slot grid, any time on the day. Staff overriding their own availability is
/// a judgement call the shop is entitled to make — the walk-in still occupies
/// the time as far as online booking is concerned.
class WalkInSheet extends StatefulWidget {
  const WalkInSheet({
    super.key,
    required this.services,
    required this.day,
    this.chairs = const <Chair>[],
  });

  final List<ShopService> services;

  /// The chairs to choose from. Empty or single means the shop has one chair
  /// and the picker is not shown at all.
  final List<Chair> chairs;

  /// Shop-local midnight of the day being edited.
  final DateTime day;

  static Future<WalkInResult?> show(
    BuildContext context, {
    required List<ShopService> services,
    required DateTime day,
    List<Chair> chairs = const <Chair>[],
  }) =>
      showModalBottomSheet<WalkInResult>(
        context: context,
        isScrollControlled: true,
        builder: (_) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: WalkInSheet(services: services, day: day, chairs: chairs),
        ),
      );

  @override
  State<WalkInSheet> createState() => _WalkInSheetState();
}

class WalkInResult {
  WalkInResult({
    required this.service,
    required this.startAt,
    required this.name,
    required this.phone,
    this.notes,
    this.chairId,
  });

  final ShopService service;
  final DateTime startAt;
  final String name;
  final String phone;
  final String? notes;

  /// Which chair the walk-in is taking. Null in a one-chair shop.
  final String? chairId;
}

class _WalkInSheetState extends State<WalkInSheet> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _notes = TextEditingController();

  ShopService? _service;
  Chair? _chair;
  late TimeOfDay _time;

  @override
  void initState() {
    super.initState();
    _service = widget.services.isNotEmpty ? widget.services.first : null;
    _chair = widget.chairs.isNotEmpty ? widget.chairs.first : null;
    // Default to now when the day being edited is today, otherwise to opening
    // time — a walk-in entered on tomorrow's page at "now" would be nonsense.
    final nowWall = ShopTime.toShopWall(DateTime.now().toUtc());
    final dayWall = ShopTime.toShopWall(widget.day);
    final isToday = nowWall.year == dayWall.year &&
        nowWall.month == dayWall.month &&
        nowWall.day == dayWall.day;
    _time = isToday
        ? TimeOfDay(hour: nowWall.hour, minute: nowWall.minute)
        : const TimeOfDay(hour: 9, minute: 0);
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _time);
    if (picked != null) setState(() => _time = picked);
  }

  void _submit() {
    final service = _service;
    if (service == null) return;
    final wall = ShopTime.toShopWall(widget.day);
    // Built through ShopTime so the instant means the shop's clock, not the
    // clock of whatever device the till happens to be.
    final startAt = ShopTime.fromShopWall(
      wall.year,
      wall.month,
      wall.day,
      _time.hour,
      _time.minute,
    );
    Navigator.of(context).pop(WalkInResult(
      service: service,
      startAt: startAt,
      name: _name.text,
      phone: _phone.text,
      notes: _notes.text,
      chairId: _chair?.id,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final b = brandOf(context);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(S.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.storefront, color: b.primary),
                const SizedBox(width: S.sm),
                Text('Laufkundschaft eintragen',
                    style: t.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: S.lg),
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Name (optional)',
                hintText: 'Laufkundschaft',
                prefixIcon: Icon(Icons.person_outline),
              ),
            ),
            const SizedBox(height: S.md),
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Telefon (optional)',
                helperText:
                    'Nur mit Nummer zählt der Besuch für die Treuekarte.',
                prefixIcon: Icon(Icons.phone_outlined),
              ),
            ),
            const SizedBox(height: S.md),
            DropdownButtonFormField<ShopService>(
              initialValue: _service,
              decoration: const InputDecoration(
                labelText: 'Leistung',
                prefixIcon: Icon(Icons.content_cut),
              ),
              items: [
                for (final s in widget.services)
                  DropdownMenuItem(
                    value: s,
                    child: Text(
                        '${s.name} · ${s.durationMinutes} Min · ${s.priceLabel}'),
                  ),
              ],
              onChanged: (s) => setState(() => _service = s),
            ),
            // Only worth asking in a shop that has more than one chair.
            if (widget.chairs.length > 1) ...[
              const SizedBox(height: S.md),
              DropdownButtonFormField<Chair>(
                initialValue: _chair,
                decoration: const InputDecoration(
                  labelText: 'Stuhl',
                  prefixIcon: Icon(Icons.event_seat),
                ),
                items: [
                  for (final chair in widget.chairs)
                    DropdownMenuItem(value: chair, child: Text(chair.name)),
                ],
                onChanged: (chair) => setState(() => _chair = chair),
              ),
            ],
            const SizedBox(height: S.md),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.schedule),
              title: const Text('Uhrzeit'),
              subtitle: Text(
                '${_time.hour.toString().padLeft(2, '0')}:'
                '${_time.minute.toString().padLeft(2, '0')} Uhr',
              ),
              trailing: TextButton(
                onPressed: _pickTime,
                child: const Text('Ändern'),
              ),
            ),
            const SizedBox(height: S.sm),
            TextField(
              controller: _notes,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Notiz (optional)',
                prefixIcon: Icon(Icons.sticky_note_2_outlined),
              ),
            ),
            const SizedBox(height: S.lg),
            AppButton(
              label: 'Eintragen',
              icon: Icons.add,
              expand: true,
              onPressed: _service == null ? null : _submit,
            ),
            const SizedBox(height: S.sm),
          ],
        ),
      ),
    );
  }
}
