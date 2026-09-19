import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/app_info.dart';
import '../models/profile.dart';
import '../services/blocking_service.dart';
import '../services/storage_service.dart';

class ProfileEditScreen extends StatefulWidget {
  final StorageService storage;
  final Profile? profile;

  const ProfileEditScreen({super.key, required this.storage, this.profile});

  @override
  State<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

// One editable day row's state: whether that weekday is scheduled, and its
// start/end times (kept even when off, so re-enabling a day restores them).
class _DayRow {
  bool enabled;
  TimeOfDay start;
  TimeOfDay end;
  _DayRow({required this.enabled, required this.start, required this.end});
}

class _ProfileEditScreenState extends State<ProfileEditScreen> {
  late final TextEditingController _nameController;
  late Set<String> _selected;
  List<AppInfo> _apps = [];
  bool _loading = true;
  String _search = '';

  bool _scheduleEnabled = false;
  // Index 0 = Monday .. 6 = Sunday (day field is index+1).
  late List<_DayRow> _days;

  bool get _isEditing => widget.profile != null;

  @override
  void initState() {
    super.initState();
    _nameController =
        TextEditingController(text: widget.profile?.name ?? '');
    _selected = Set.from(widget.profile?.blockedPackages ?? []);

    _days = List.generate(
      7,
      (i) => _DayRow(
        enabled: false,
        start: const TimeOfDay(hour: 7, minute: 45),
        end: const TimeOfDay(hour: 17, minute: 0),
      ),
    );

    final p = widget.profile;
    if (p != null) {
      _scheduleEnabled = p.scheduleEnabled;
      for (final entry in p.schedule) {
        _days[entry.day - 1] = _DayRow(
          enabled: true,
          start: _parseTime(entry.start),
          end: _parseTime(entry.end),
        );
      }
    }

    _loadApps();
  }

  TimeOfDay _parseTime(String hhmm) {
    final parts = hhmm.split(':');
    return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
  }

  String _formatTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _loadApps() async {
    final apps = await BlockingService.getInstalledApps();
    if (!mounted) return;
    setState(() {
      _apps = apps;
      _loading = false;
    });
  }

  List<AppInfo> get _filtered {
    if (_search.isEmpty) return _apps;
    final q = _search.toLowerCase();
    return _apps
        .where((a) =>
            a.appName.toLowerCase().contains(q) ||
            a.packageName.toLowerCase().contains(q))
        .toList();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Give this profile a name')),
      );
      return;
    }

    final activeDays = _days.asMap().entries.where((e) => e.value.enabled).toList();
    if (_scheduleEnabled && activeDays.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Turn on at least one day, or disable the schedule')),
      );
      return;
    }

    if (_scheduleEnabled) {
      final canExact = await BlockingService.canScheduleExactAlarms();
      if (!canExact && mounted) {
        final grant = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Allow exact alarms'),
            content: const Text(
              'Scheduled blocking needs the "Alarms & reminders" '
              'permission to fire at the exact time you set. '
              'Tap Allow to open Settings.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Allow'),
              ),
            ],
          ),
        );
        if (grant == true) {
          await BlockingService.openExactAlarmSettings();
        }
        // Let the user save anyway — alarms may still work (inexact fallback).
      }
    }

    final schedule = _scheduleEnabled
        ? activeDays
            .map((e) => DaySchedule(
                  day: e.key + 1,
                  start: _formatTime(e.value.start),
                  end: _formatTime(e.value.end),
                ))
            .toList()
        : <DaySchedule>[];

    final profileId = widget.profile?.id ?? const Uuid().v4();
    final profile = Profile(
      id: profileId,
      name: name,
      blockedPackages: _selected.toList(),
      scheduleEnabled: _scheduleEnabled,
      schedule: schedule,
    );
    await widget.storage.upsertProfile(profile);

    if (_scheduleEnabled) {
      await BlockingService.setSchedule(
        profileId: profileId,
        days: schedule
            .map((d) => {
                  'day': d.day,
                  'startHH': int.parse(d.start.split(':')[0]),
                  'startMM': int.parse(d.start.split(':')[1]),
                  'endHH': int.parse(d.end.split(':')[0]),
                  'endMM': int.parse(d.end.split(':')[1]),
                })
            .toList(),
      );
    } else {
      await BlockingService.cancelSchedule(profileId);
    }

    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit profile' : 'New profile'),
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text('Save'),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Profile name',
                hintText: 'e.g. Focus, Bedtime, Work',
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.words,
            ),
          ),
          _ScheduleSection(
            enabled: _scheduleEnabled,
            days: _days,
            onEnabledChanged: (v) => setState(() => _scheduleEnabled = v),
            onDayToggled: (i, v) => setState(() => _days[i].enabled = v),
            onDayStartChanged: (i, t) => setState(() => _days[i].start = t),
            onDayEndChanged: (i, t) => setState(() => _days[i].end = t),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                labelText: 'Search apps',
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() => _search = v),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              '${_selected.length} apps selected',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _filtered.isEmpty
                    ? const Center(child: Text('No apps found'))
                    : ListView.builder(
                        itemCount: _filtered.length,
                        itemBuilder: (_, i) {
                          final app = _filtered[i];
                          return CheckboxListTile(
                            controlAffinity: ListTileControlAffinity.trailing,
                            secondary: _AppIcon(packageName: app.packageName),
                            title: Text(app.appName),
                            subtitle: Text(
                              app.packageName,
                              style: const TextStyle(fontSize: 11),
                            ),
                            value: _selected.contains(app.packageName),
                            onChanged: (v) => setState(() {
                              if (v == true) {
                                _selected.add(app.packageName);
                              } else {
                                _selected.remove(app.packageName);
                              }
                            }),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

// ── Schedule section ─────────────────────────────────────────────────────────

const _dayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

class _ScheduleSection extends StatelessWidget {
  final bool enabled;
  final List<_DayRow> days;
  final ValueChanged<bool> onEnabledChanged;
  final void Function(int index, bool value) onDayToggled;
  final void Function(int index, TimeOfDay value) onDayStartChanged;
  final void Function(int index, TimeOfDay value) onDayEndChanged;

  const _ScheduleSection({
    required this.enabled,
    required this.days,
    required this.onEnabledChanged,
    required this.onDayToggled,
    required this.onDayStartChanged,
    required this.onDayEndChanged,
  });

  String _fmt(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _pickTime(
    BuildContext context,
    TimeOfDay current,
    ValueChanged<TimeOfDay> onChanged,
  ) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: current,
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked != null) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          value: enabled,
          onChanged: onEnabledChanged,
          title: const Text('Auto-start on schedule'),
          subtitle: const Text('Blocking starts and stops at set times, per day'),
          secondary: const Icon(Icons.schedule),
        ),
        if (enabled) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Text(
              'Only an NFC tag can stop blocking during a scheduled window.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Theme.of(context).colorScheme.primary),
            ),
          ),
          for (var i = 0; i < 7; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
              child: Row(
                children: [
                  SizedBox(
                    width: 40,
                    child: Text(_dayLabels[i], style: Theme.of(context).textTheme.bodyMedium),
                  ),
                  Switch(
                    value: days[i].enabled,
                    onChanged: (v) => onDayToggled(i, v),
                  ),
                  const SizedBox(width: 8),
                  if (days[i].enabled) ...[
                    Expanded(
                      child: TextButton(
                        onPressed: () => _pickTime(
                          context,
                          days[i].start,
                          (t) => onDayStartChanged(i, t),
                        ),
                        child: Text(_fmt(days[i].start)),
                      ),
                    ),
                    const Text('–'),
                    Expanded(
                      child: TextButton(
                        onPressed: () => _pickTime(
                          context,
                          days[i].end,
                          (t) => onDayEndChanged(i, t),
                        ),
                        child: Text(_fmt(days[i].end)),
                      ),
                    ),
                  ] else
                    Expanded(
                      child: Text(
                        'Not scheduled',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: Theme.of(context).colorScheme.outline),
                      ),
                    ),
                ],
              ),
            ),
          const Divider(),
        ],
      ],
    );
  }
}

// Lazily loads and caches an app's launcher icon.
// Shows nothing while loading, falls back to a generic icon on failure.
class _AppIcon extends StatefulWidget {
  final String packageName;
  const _AppIcon({required this.packageName});

  @override
  State<_AppIcon> createState() => _AppIconState();
}

class _AppIconState extends State<_AppIcon> {
  Uint8List? _bytes;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    BlockingService.getAppIcon(widget.packageName).then((bytes) {
      if (mounted) setState(() { _bytes = bytes; _loaded = true; });
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox(width: 40, height: 40);
    if (_bytes == null) return const Icon(Icons.android, size: 40);
    return Image.memory(_bytes!, width: 40, height: 40, gaplessPlayback: true);
  }
}
