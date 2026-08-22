import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/brand.dart';
import '../../core/shop_time.dart';
import '../../core/widgets/app_button.dart';
import '../controllers/agenda_controller.dart';
import '../data/models.dart';
import '../data/staff_repository.dart';

/// Opening hours and booking rules.
///
/// These used to be compile-time constants in the Flutter source, so changing
/// the lunch break meant a release. They live in `business_hours` and
/// `shop_settings` now, and the availability function reads them on every
/// request — a change here is live for the next customer who opens the app.
class StaffSettingsPage extends StatefulWidget {
  const StaffSettingsPage({super.key, required this.tag});

  final String tag;

  @override
  State<StaffSettingsPage> createState() => _StaffSettingsPageState();
}

class _StaffSettingsPageState extends State<StaffSettingsPage> {
  late final AgendaController _agenda =
      Get.find<AgendaController>(tag: widget.tag);
  late final StaffRepository _repo = Get.find<StaffRepository>();

  List<DayHours> _hours = [];
  late ShopSettings _settings;
  bool _loading = true;
  bool _saving = false;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final hours = await _repo.hours();
      setState(() {
        _hours = hours;
        _settings = _agenda.settings.value;
        _loading = false;
      });
    } catch (_) {
      setState(() {
        _hours = List.generate(7, DayHours.closedOn);
        _settings = _agenda.settings.value;
        _loading = false;
      });
    }
  }

  void _edit(int weekday, DayHours Function(DayHours) change) {
    setState(() {
      _hours[weekday] = change(_hours[weekday]);
      _dirty = true;
    });
  }

  Future<void> _pickTime(int weekday, _Field field) async {
    final current = switch (field) {
      _Field.open => _hours[weekday].openTime,
      _Field.close => _hours[weekday].closeTime,
      _Field.breakStart => _hours[weekday].breakStart ?? '12:00',
      _Field.breakEnd => _hours[weekday].breakEnd ?? '13:00',
    };
    final parts = current.split(':');
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: int.tryParse(parts.first) ?? 9,
        minute: int.tryParse(parts.last) ?? 0,
      ),
    );
    if (picked == null) return;
    final value = '${picked.hour.toString().padLeft(2, '0')}:'
        '${picked.minute.toString().padLeft(2, '0')}';
    _edit(
        weekday,
        (d) => switch (field) {
              _Field.open => d.copyWith(openTime: value),
              _Field.close => d.copyWith(closeTime: value),
              _Field.breakStart => d.copyWith(breakStart: value),
              _Field.breakEnd => d.copyWith(breakEnd: value),
            });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      // Seven small writes rather than one batch: the CLI-provisioned table has
      // no transaction, and a partial save of opening hours is recoverable by
      // simply saving again.
      for (final day in _hours) {
        await _repo.saveHours(day);
      }
      await _agenda.saveSettings(_settings);
      await _agenda.reload();
      if (mounted) {
        setState(() => _dirty = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Gespeichert.')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Speichern fehlgeschlagen.')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Öffnungszeiten & Regeln'),
        actions: [
          if (_dirty)
            Padding(
              padding: const EdgeInsets.only(right: S.sm),
              child: TextButton(
                onPressed: _saving ? null : _save,
                child: const Text('Speichern'),
              ),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.only(bottom: S.xxxl),
              children: [
                _SectionTitle(
                  'Öffnungszeiten',
                  subtitle: 'Zeitzone des Salons: ${ShopTime.timezone}',
                ),
                for (final day in _hours) _dayCard(day, t),
                const SizedBox(height: S.lg),
                _SectionTitle(
                  'Buchungsregeln',
                  subtitle: 'Gelten sofort für alle Online-Buchungen.',
                ),
                _numberTile(
                  icon: Icons.timer_outlined,
                  title: 'Puffer zwischen Terminen',
                  value: _settings.bufferMinutes,
                  unit: 'Min',
                  step: 5,
                  max: 60,
                  onChanged: (v) => setState(() {
                    _settings = _settings.copyWith(bufferMinutes: v);
                    _dirty = true;
                  }),
                ),
                _numberTile(
                  icon: Icons.hourglass_bottom,
                  title: 'Vorlaufzeit',
                  subtitle: 'Wie kurzfristig noch gebucht werden darf.',
                  value: _settings.leadTimeMinutes,
                  unit: 'Min',
                  step: 15,
                  max: 480,
                  onChanged: (v) => setState(() {
                    _settings = _settings.copyWith(leadTimeMinutes: v);
                    _dirty = true;
                  }),
                ),
                _numberTile(
                  icon: Icons.event_busy,
                  title: 'Stornofrist',
                  subtitle: 'Bis wann Gäste selbst absagen dürfen.',
                  value: _settings.cancelCutoffHours,
                  unit: 'Std',
                  step: 1,
                  max: 72,
                  onChanged: (v) => setState(() {
                    _settings = _settings.copyWith(cancelCutoffHours: v);
                    _dirty = true;
                  }),
                ),
                _numberTile(
                  icon: Icons.date_range,
                  title: 'Vorausbuchbar',
                  value: _settings.maxAdvanceDays,
                  unit: 'Tage',
                  step: 7,
                  max: 365,
                  min: 1,
                  onChanged: (v) => setState(() {
                    _settings = _settings.copyWith(maxAdvanceDays: v);
                    _dirty = true;
                  }),
                ),
                _numberTile(
                  icon: Icons.person_outline,
                  title: 'Offene Termine pro Nummer',
                  subtitle: 'Bremst Spam-Buchungen.',
                  value: _settings.maxOpenPerPhone,
                  unit: '',
                  step: 1,
                  max: 20,
                  min: 1,
                  onChanged: (v) => setState(() {
                    _settings = _settings.copyWith(maxOpenPerPhone: v);
                    _dirty = true;
                  }),
                ),
                const SizedBox(height: S.xl),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: S.lg),
                  child: AppButton(
                    label: 'Speichern',
                    icon: Icons.save,
                    expand: true,
                    loading: _saving,
                    onPressed: _dirty ? _save : null,
                  ),
                ),
              ],
            ),
    );
  }

  Widget _dayCard(DayHours day, ThemeData t) {
    final b = brandOf(context);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: S.lg, vertical: S.xs),
      decoration: BoxDecoration(
        color: b.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: b.secondary.withValues(alpha: 0.25)),
      ),
      child: Column(
        children: [
          SwitchListTile(
            title: Text(day.name, style: t.textTheme.titleSmall),
            subtitle: Text(day.closed
                ? 'Geschlossen'
                : '${day.openTime} – ${day.closeTime}'
                    '${day.hasBreak ? '  ·  Pause ${day.breakStart}–${day.breakEnd}' : ''}'),
            value: !day.closed,
            onChanged: (open) =>
                _edit(day.weekday, (d) => d.copyWith(closed: !open)),
          ),
          if (!day.closed)
            Padding(
              padding: const EdgeInsets.fromLTRB(S.lg, 0, S.sm, S.sm),
              child: Column(
                children: [
                  Row(
                    children: [
                      _timeButton('Öffnet', day.openTime,
                          () => _pickTime(day.weekday, _Field.open)),
                      const SizedBox(width: S.sm),
                      _timeButton('Schließt', day.closeTime,
                          () => _pickTime(day.weekday, _Field.close)),
                    ],
                  ),
                  const SizedBox(height: S.xs),
                  if (day.hasBreak)
                    Row(
                      children: [
                        _timeButton('Pause ab', day.breakStart!,
                            () => _pickTime(day.weekday, _Field.breakStart)),
                        const SizedBox(width: S.sm),
                        _timeButton('Pause bis', day.breakEnd!,
                            () => _pickTime(day.weekday, _Field.breakEnd)),
                        IconButton(
                          tooltip: 'Pause entfernen',
                          icon: const Icon(Icons.close, size: 18),
                          // copyWith cannot clear a field, so rebuild the day
                          // without one.
                          onPressed: () => setState(() {
                            _hours[day.weekday] = DayHours(
                              weekday: day.weekday,
                              openTime: day.openTime,
                              closeTime: day.closeTime,
                              slotMinutes: day.slotMinutes,
                              closed: day.closed,
                            );
                            _dirty = true;
                          }),
                        ),
                      ],
                    )
                  else
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => _edit(
                          day.weekday,
                          (d) => d.copyWith(
                              breakStart: '12:00', breakEnd: '13:00'),
                        ),
                        icon:
                            const Icon(Icons.free_breakfast_outlined, size: 18),
                        label: const Text('Mittagspause'),
                      ),
                    ),
                  Row(
                    children: [
                      const SizedBox(width: S.xs),
                      Text('Raster', style: t.textTheme.bodySmall),
                      const Spacer(),
                      SegmentedButton<int>(
                        showSelectedIcon: false,
                        style: const ButtonStyle(
                            visualDensity: VisualDensity.compact),
                        segments: const [
                          ButtonSegment(value: 15, label: Text('15')),
                          ButtonSegment(value: 30, label: Text('30')),
                          ButtonSegment(value: 60, label: Text('60')),
                        ],
                        selected: {day.slotMinutes},
                        onSelectionChanged: (s) => _edit(day.weekday,
                            (d) => d.copyWith(slotMinutes: s.first)),
                      ),
                      const SizedBox(width: S.xs),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _timeButton(String label, String value, VoidCallback onTap) =>
      Expanded(
        child: OutlinedButton(
          onPressed: onTap,
          child: Column(
            children: [
              Text(label, style: Theme.of(context).textTheme.labelSmall),
              Text(value, style: Theme.of(context).textTheme.titleSmall),
            ],
          ),
        ),
      );

  Widget _numberTile({
    required IconData icon,
    required String title,
    required int value,
    required String unit,
    required int step,
    required int max,
    required ValueChanged<int> onChanged,
    String? subtitle,
    int min = 0,
  }) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.remove_circle_outline),
            onPressed: value > min
                ? () => onChanged((value - step).clamp(min, max))
                : null,
          ),
          SizedBox(
            width: 62,
            child: Text(
              unit.isEmpty ? '$value' : '$value $unit',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            onPressed: value < max
                ? () => onChanged((value + step).clamp(min, max))
                : null,
          ),
        ],
      ),
    );
  }
}

enum _Field { open, close, breakStart, breakEnd }

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title, {this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(S.lg, S.lg, S.lg, S.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: t.textTheme.titleMedium),
          if (subtitle != null)
            Text(
              subtitle!,
              style: t.textTheme.bodySmall
                  ?.copyWith(color: t.colorScheme.onSurfaceVariant),
            ),
        ],
      ),
    );
  }
}
