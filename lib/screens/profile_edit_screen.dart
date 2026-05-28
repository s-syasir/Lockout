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

class _ProfileEditScreenState extends State<ProfileEditScreen> {
  late final TextEditingController _nameController;
  late Set<String> _selected;
  List<AppInfo> _apps = [];
  bool _loading = true;
  String _search = '';

  bool _scheduleEnabled = false;
  TimeOfDay _scheduleStart = const TimeOfDay(hour: 7, minute: 45);
  TimeOfDay _scheduleEnd = const TimeOfDay(hour: 17, minute: 0);

  bool get _isEditing => widget.profile != null;

  @override
  void initState() {
    super.initState();
    _nameController =
        TextEditingController(text: widget.profile?.name ?? '');
    _selected = Set.from(widget.profile?.blockedPackages ?? []);

    final p = widget.profile;
    if (p != null) {
      _scheduleEnabled = p.scheduleEnabled;
      if (p.scheduleStart != null) _scheduleStart = _parseTime(p.scheduleStart!);
      if (p.scheduleEnd != null) _scheduleEnd = _parseTime(p.scheduleEnd!);
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

    final profileId = widget.profile?.id ?? const Uuid().v4();
    final profile = Profile(
      id: profileId,
      name: name,
      blockedPackages: _selected.toList(),
      scheduleEnabled: _scheduleEnabled,
      scheduleStart: _scheduleEnabled ? _formatTime(_scheduleStart) : null,
      scheduleEnd: _scheduleEnabled ? _formatTime(_scheduleEnd) : null,
    );
    await widget.storage.upsertProfile(profile);

    if (_scheduleEnabled) {
      await BlockingService.setSchedule(
        profileId: profileId,
        startHH: _scheduleStart.hour,
        startMM: _scheduleStart.minute,
        endHH: _scheduleEnd.hour,
        endMM: _scheduleEnd.minute,
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
            start: _scheduleStart,
            end: _scheduleEnd,
            onEnabledChanged: (v) => setState(() => _scheduleEnabled = v),
            onStartChanged: (t) => setState(() => _scheduleStart = t),
            onEndChanged: (t) => setState(() => _scheduleEnd = t),
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

class _ScheduleSection extends StatelessWidget {
  final bool enabled;
  final TimeOfDay start;
  final TimeOfDay end;
  final ValueChanged<bool> onEnabledChanged;
  final ValueChanged<TimeOfDay> onStartChanged;
  final ValueChanged<TimeOfDay> onEndChanged;

  const _ScheduleSection({
    required this.enabled,
    required this.start,
    required this.end,
    required this.onEnabledChanged,
    required this.onStartChanged,
    required this.onEndChanged,
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
          subtitle: const Text('Blocking starts and stops at set times daily'),
          secondary: const Icon(Icons.schedule),
        ),
        if (enabled) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Text(
              'Only an NFC tag can stop blocking during the scheduled window.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Theme.of(context).colorScheme.primary),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: ListTile(
                  leading: const Icon(Icons.lock_clock),
                  title: const Text('Start'),
                  subtitle: Text(_fmt(start)),
                  onTap: () => _pickTime(context, start, onStartChanged),
                ),
              ),
              Expanded(
                child: ListTile(
                  leading: const Icon(Icons.lock_open),
                  title: const Text('End'),
                  subtitle: Text(_fmt(end)),
                  onTap: () => _pickTime(context, end, onEndChanged),
                ),
              ),
            ],
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
