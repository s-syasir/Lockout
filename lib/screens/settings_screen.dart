import 'package:flutter/material.dart';
import '../services/backup_service.dart';
import '../services/blocking_service.dart';
import '../services/storage_service.dart';

class SettingsScreen extends StatefulWidget {
  final StorageService storage;
  const SettingsScreen({super.key, required this.storage});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with WidgetsBindingObserver {
  bool? _hasPermission;
  bool? _hasNotifPermission;
  bool? _hasManagedProfile;
  bool _dpcMode = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _dpcMode = widget.storage.dpcModeEnabled;
    _checkPermission();
    _checkDpcState();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkPermission();
      _checkDpcState();
    }
  }

  Future<void> _checkPermission() async {
    final ok = await BlockingService.hasAccessibilityPermission();
    final notif = await BlockingService.hasNotificationListenerPermission();
    if (mounted) {
      setState(() {
        _hasPermission = ok;
        _hasNotifPermission = notif;
      });
    }
  }

  Future<void> _checkDpcState() async {
    final has = await BlockingService.dpcHasManagedProfile();
    if (mounted) setState(() => _hasManagedProfile = has);
  }

  Future<void> _provisionManagedProfile() async {
    final ok = await BlockingService.dpcProvisionManagedProfile();
    if (!mounted) return;
    if (ok) {
      setState(() => _hasManagedProfile = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Work profile set up. Move your distracting apps into it, then enable DPC mode.')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Work profile setup cancelled or not supported on this device.')),
      );
    }
  }

  Future<void> _exportProfiles() async {
    final profiles = widget.storage.getProfiles();
    if (profiles.isEmpty) {
      _snack('No profiles to export');
      return;
    }
    final path = await BackupService.exportProfiles(profiles);
    if (!mounted) return;
    if (path != null) {
      _snack('Backup saved');
    }
    // If path is null the user cancelled — no message needed.
  }

  Future<void> _importProfiles() async {
    final imported = await BackupService.importProfiles();
    if (!mounted) return;
    if (imported == null) {
      _snack('Import cancelled or file is invalid');
      return;
    }
    int added = 0;
    int updated = 0;
    for (final p in imported) {
      final existing = widget.storage.getProfile(p.id);
      await widget.storage.upsertProfile(p);
      if (existing == null) {
        added++;
      } else {
        updated++;
      }
    }
    _snack('Imported $added new, $updated updated');
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _toggleDpcMode(bool value) async {
    await widget.storage.setDpcMode(value);
    if (mounted) setState(() => _dpcMode = value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          _SectionHeader('Permissions'),
          ListTile(
            leading: _permissionIcon(),
            title: const Text('Accessibility Service'),
            subtitle: Text(_permissionLabel()),
            trailing: _hasPermission == false
                ? FilledButton(
                    onPressed: () async {
                      await BlockingService.openAccessibilitySettings();
                    },
                    child: const Text('Enable'),
                  )
                : null,
          ),
          ListTile(
            leading: _notifPermissionIcon(),
            title: const Text('Notification Access'),
            subtitle: Text(_notifPermissionLabel()),
            trailing: _hasNotifPermission == false
                ? FilledButton(
                    onPressed: () async {
                      await BlockingService.openNotificationListenerSettings();
                    },
                    child: const Text('Enable'),
                  )
                : null,
          ),
          const Divider(),
          _SectionHeader('Work Profile blocking (advanced)'),
          ListTile(
            leading: const Icon(Icons.work_outline),
            title: const Text('Work Profile status'),
            subtitle: Text(_managedProfileLabel()),
            trailing: _hasManagedProfile == false
                ? FilledButton(
                    onPressed: _provisionManagedProfile,
                    child: const Text('Set up'),
                  )
                : null,
          ),
          if (_hasManagedProfile == true)
            SwitchListTile(
              secondary: const Icon(Icons.shield_outlined),
              title: const Text('Use Work Profile mode'),
              subtitle: const Text(
                'More reliable on Samsung/Xiaomi. Move distracting apps to the Work Profile first.',
              ),
              value: _dpcMode,
              onChanged: _toggleDpcMode,
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(
              'Work Profile mode freezes the entire work profile instead of using Accessibility Service. '
              'It survives OEM battery savers and requires no background service.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
            ),
          ),
          const Divider(),
          _SectionHeader('Backup & restore'),
          ListTile(
            leading: const Icon(Icons.upload_file),
            title: const Text('Export profiles'),
            subtitle: const Text('Save all profiles to a file you choose'),
            onTap: _exportProfiles,
          ),
          ListTile(
            leading: const Icon(Icons.download),
            title: const Text('Import profiles'),
            subtitle: const Text('Load profiles from a backup file — merges with existing'),
            onTap: _importProfiles,
          ),
          const Divider(),
          _SectionHeader('About'),
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('Version'),
            trailing: Text('1.0.0', style: TextStyle(color: Colors.grey)),
          ),
          const ListTile(
            leading: Icon(Icons.lock_outline),
            title: Text('Privacy'),
            subtitle: Text(
              'No internet permission. No analytics. No data ever leaves your device.',
            ),
          ),
          const ListTile(
            leading: Icon(Icons.code),
            title: Text('Source code'),
            subtitle: Text('github.com/s-syasir/lockout'),
          ),
        ],
      ),
    );
  }

  Widget _permissionIcon() {
    if (_hasPermission == null) {
      return const SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    return Icon(
      _hasPermission! ? Icons.check_circle : Icons.warning_amber_rounded,
      color: _hasPermission!
          ? Colors.green
          : Theme.of(context).colorScheme.error,
    );
  }

  String _permissionLabel() {
    if (_hasPermission == null) return 'Checking…';
    return _hasPermission! ? 'Enabled' : 'Not enabled — tap to fix';
  }

  Widget _notifPermissionIcon() {
    if (_hasNotifPermission == null) {
      return const SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    return Icon(
      _hasNotifPermission! ? Icons.check_circle : Icons.warning_amber_rounded,
      color: _hasNotifPermission!
          ? Colors.green
          : Theme.of(context).colorScheme.error,
    );
  }

  String _notifPermissionLabel() {
    if (_hasNotifPermission == null) return 'Checking…';
    return _hasNotifPermission!
        ? 'Enabled — notifications from blocked apps will be suppressed'
        : 'Not enabled — blocked apps can still send notifications';
  }

  String _managedProfileLabel() {
    if (_hasManagedProfile == null) return 'Checking…';
    return _hasManagedProfile!
        ? 'Work profile active'
        : 'No work profile — tap Set up to create one';
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}
