import 'package:flutter/material.dart';

import '../../core/brand.dart';
import '../../core/shop_time.dart';
import '../../core/widgets/app_button.dart';
import '../data/models.dart';

/// Block time off: a dentist appointment, a funeral, a fortnight in Antalya.
///
/// Anything overlapping a closure disappears from online availability
/// immediately — which is the whole point, and the thing the old schema had no
/// way to express at all.
class BlockOffSheet extends StatefulWidget {
  const BlockOffSheet({
    super.key,
    required this.day,
    this.chairs = const <Chair>[],
  });

  /// Shop-local midnight of the day the panel is showing.
  final DateTime day;

  /// The chairs that can be blocked individually. Empty or single means the
  /// block always covers the whole shop and no choice is offered.
  final List<Chair> chairs;

  static Future<BlockOffResult?> show(BuildContext context,
          {required DateTime day, List<Chair> chairs = const <Chair>[]}) =>
      showModalBottomSheet<BlockOffResult>(
        context: context,
        isScrollControlled: true,
        builder: (_) => Padding(
          padding:
              EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: BlockOffSheet(day: day, chairs: chairs),
        ),
      );

  @override
  State<BlockOffSheet> createState() => _BlockOffSheetState();
}

class BlockOffResult {
  BlockOffResult({
    required this.startsAt,
    required this.endsAt,
    required this.allDay,
    this.reason,
    this.chairId,
  });

  /// Which chair is blocked. Null means the whole shop — one barber being away
  /// and the shop being shut are different things, and reading the second as
  /// the first empties a three-chair shop's diary for nothing.
  final String? chairId;

  final DateTime startsAt;
  final DateTime endsAt;
  final bool allDay;
  final String? reason;
}

class _BlockOffSheetState extends State<BlockOffSheet> {
  final _reason = TextEditingController();

  /// Null is "the whole shop", which is the right default: a block-off is
  /// more often a closure than one barber's day off.
  Chair? _chair;

  bool _allDay = false;
  TimeOfDay _from = const TimeOfDay(hour: 12, minute: 0);
  TimeOfDay _to = const TimeOfDay(hour: 13, minute: 0);

  /// How many days the block runs for. 1 = just this day; a holiday is simply
  /// a longer one, so there is no separate "vacation" concept to maintain.
  int _days = 1;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _pick(bool isFrom) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: isFrom ? _from : _to,
    );
    if (picked == null) return;
    setState(() {
      if (isFrom) {
        _from = picked;
        // Keep the end after the start rather than silently saving a range
        // that blocks nothing.
        if (_minutes(_to) <= _minutes(picked)) {
          _to = TimeOfDay(hour: (picked.hour + 1) % 24, minute: picked.minute);
        }
      } else {
        _to = picked;
      }
    });
  }

  static int _minutes(TimeOfDay t) => t.hour * 60 + t.minute;

  bool get _valid => _allDay || _minutes(_to) > _minutes(_from);

  void _submit() {
    final wall = ShopTime.toShopWall(widget.day);
    final DateTime start;
    final DateTime end;

    if (_allDay) {
      start = ShopTime.fromShopWall(wall.year, wall.month, wall.day);
      // Shop-local midnight _days later, recomputed through ShopTime so a DST
      // transition inside a holiday does not shift its end by an hour.
      final endWall = ShopTime.toShopWall(
        start.add(Duration(days: _days, hours: 12)),
      );
      end = ShopTime.fromShopWall(endWall.year, endWall.month, endWall.day);
    } else {
      start = ShopTime.fromShopWall(
          wall.year, wall.month, wall.day, _from.hour, _from.minute);
      end = ShopTime.fromShopWall(
          wall.year, wall.month, wall.day, _to.hour, _to.minute);
    }

    Navigator.of(context).pop(BlockOffResult(
      startsAt: start,
      endsAt: end,
      allDay: _allDay,
      chairId: _chair?.id,
      reason: _reason.text,
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
                Icon(Icons.event_busy, color: b.primary),
                const SizedBox(width: S.sm),
                Text('Zeit sperren', style: t.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: S.xs),
            Text(
              'Gesperrte Zeiten verschwinden sofort aus der Online-Buchung.',
              style: t.textTheme.bodySmall
                  ?.copyWith(color: t.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: S.lg),
            TextField(
              controller: _reason,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Grund (optional)',
                hintText: 'Urlaub, Arzttermin, Fortbildung …',
                prefixIcon: Icon(Icons.notes),
              ),
            ),
            if (widget.chairs.length > 1) ...[
              const SizedBox(height: S.md),
              DropdownButtonFormField<Chair?>(
                initialValue: _chair,
                decoration: const InputDecoration(
                  labelText: 'Gilt für',
                  prefixIcon: Icon(Icons.event_seat),
                ),
                items: [
                  const DropdownMenuItem<Chair?>(
                    value: null,
                    child: Text('Ganzer Laden'),
                  ),
                  for (final chair in widget.chairs)
                    DropdownMenuItem<Chair?>(
                      value: chair,
                      child: Text('Nur ${chair.name}'),
                    ),
                ],
                onChanged: (chair) => setState(() => _chair = chair),
              ),
            ],
            const SizedBox(height: S.sm),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _allDay,
              onChanged: (v) => setState(() => _allDay = v),
              title: const Text('Ganzer Tag'),
              secondary: const Icon(Icons.today),
            ),
            if (_allDay)
              Row(
                children: [
                  const Icon(Icons.date_range),
                  const SizedBox(width: S.md),
                  Expanded(
                    child: Text(
                      _days == 1 ? '1 Tag' : '$_days Tage',
                      style: t.textTheme.bodyMedium,
                    ),
                  ),
                  IconButton(
                    onPressed: _days > 1 ? () => setState(() => _days--) : null,
                    icon: const Icon(Icons.remove_circle_outline),
                    tooltip: 'Weniger',
                  ),
                  IconButton(
                    onPressed:
                        _days < 60 ? () => setState(() => _days++) : null,
                    icon: const Icon(Icons.add_circle_outline),
                    tooltip: 'Mehr',
                  ),
                ],
              )
            else
              Row(
                children: [
                  Expanded(
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Von'),
                      subtitle: Text(_label(_from)),
                      onTap: () => _pick(true),
                    ),
                  ),
                  Expanded(
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Bis'),
                      subtitle: Text(_label(_to)),
                      onTap: () => _pick(false),
                    ),
                  ),
                ],
              ),
            const SizedBox(height: S.lg),
            AppButton(
              label: 'Sperren',
              icon: Icons.block,
              expand: true,
              onPressed: _valid ? _submit : null,
            ),
            const SizedBox(height: S.sm),
          ],
        ),
      ),
    );
  }

  static String _label(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')} Uhr';
}
