import 'dart:async';
import 'package:flutter/material.dart';
import '../models/profile.dart';
import '../services/blocking_service.dart';
import '../services/nfc_service.dart';
import '../services/storage_service.dart';
import 'onboarding_screen.dart';
import 'profile_edit_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  final StorageService storage;
  const HomeScreen({super.key, required this.storage});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  bool _isBlocking = false;
  Profile? _activeProfile;
  bool _nfcListening = false;
  String? _tempUnblockProfileId;
  DateTime? _tempUnblockExpiry;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  // Sequenced deliberately: a cold start from a background-killed process is
  // exactly how an NFC tap normally reaches this app, so _syncState() must
  // finish before _checkPendingNfcTag() reads _isBlocking/_activeProfile —
  // otherwise a stop-tap races ahead of state loading and reads as a start.
  Future<void> _init() async {
    await _syncState();
    await _checkOnboarding();
    await _checkPendingNfcTag();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _handleResume();
    }
  }

  Future<void> _handleResume() async {
    await _syncState();
    await _checkPendingNfcTag();
  }

  Future<void> _syncState() async {
    final bool blocking;
    if (widget.storage.dpcModeEnabled) {
      blocking = await BlockingService.dpcIsQuietModeEnabled();
    } else {
      blocking = await BlockingService.isBlocking();
    }
    final profileId = widget.storage.getActiveProfileId();
    final profile = profileId != null ? widget.storage.getProfile(profileId) : null;
    final pending = widget.storage.dpcModeEnabled
        ? null
        : await BlockingService.getPendingTempUnblock();
    if (!mounted) return;
    setState(() {
      _isBlocking = blocking;
      _activeProfile = profile;
      _tempUnblockProfileId = pending?['profileId'] as String?;
      final expiryMs = pending?['expiryMs'] as int?;
      _tempUnblockExpiry =
          expiryMs != null ? DateTime.fromMillisecondsSinceEpoch(expiryMs) : null;
    });
  }

  // Whether "now" falls inside a scheduled profile's own start/end window.
  bool _isNowInSchedule(Profile p) {
    if (!p.scheduleEnabled || p.scheduleStart == null || p.scheduleEnd == null) {
      return false;
    }
    final start = p.scheduleStart!.split(':').map(int.parse).toList();
    final end = p.scheduleEnd!.split(':').map(int.parse).toList();
    final now = TimeOfDay.now();
    final nowMins = now.hour * 60 + now.minute;
    final startMins = start[0] * 60 + start[1];
    final endMins = end[0] * 60 + end[1];
    if (startMins < endMins) {
      return nowMins >= startMins && nowMins < endMins;
    }
    return nowMins >= startMins || nowMins < endMins; // window crosses midnight
  }

  Future<void> _checkOnboarding() async {
    final hasPermission = await BlockingService.hasAccessibilityPermission();
    if (!hasPermission && mounted) {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const OnboardingScreen()),
      );
    }
  }

  Future<void> _checkPendingNfcTag() async {
    final profileId = await BlockingService.getPendingNfcTag();
    if (profileId == null || !mounted) return;
    final profile = widget.storage.getProfile(profileId);
    if (profile == null) {
      _showSnack('Profile not found — it may have been deleted');
      return;
    }
    await _toggle(profile, fromNfc: true);
  }

  Future<void> _tapNfc() async {
    setState(() => _nfcListening = true);
    try {
      final available = await NfcService.isAvailable;
      if (!available) {
        _showSnack('NFC is not available on this device');
        return;
      }
      final profileId = await NfcService.readTag();
      if (!mounted) return;
      if (profileId == null) {
        _showSnack('No Lockout profile on this tag');
        return;
      }
      final profile = widget.storage.getProfile(profileId);
      if (profile == null) {
        _showSnack('Profile not found — it may have been deleted');
        return;
      }
      await _toggle(profile, fromNfc: true);
    } catch (e) {
      if (mounted) _showSnack('NFC error: $e');
    } finally {
      if (mounted) setState(() => _nfcListening = false);
    }
  }

  // Tap = toggle. NFC-initiated taps can stop; UI taps can only start.
  Future<void> _toggle(Profile profile, {bool fromNfc = false}) async {
    if (_isBlocking && _activeProfile?.id == profile.id) {
      if (!fromNfc) {
        _showSnack('Scan your NFC tag to stop blocking');
        return;
      }
      if (widget.storage.dpcModeEnabled) {
        await _stopBlocking();
      } else {
        await _showUnblockOptions(profile);
      }
    } else if (_tempUnblockProfileId == profile.id) {
      // Mid-countdown from an earlier temporary unblock — a re-tap means
      // "I'm done early, lock it back up now."
      if (!fromNfc) {
        _showSnack('Scan your NFC tag to re-lock now');
        return;
      }
      await BlockingService.endTempUnblock(profile.id);
      await _syncState();
    } else {
      if (profile.blockedPackages.isEmpty && !widget.storage.dpcModeEnabled) {
        _showSnack('Add apps to this profile before blocking');
        return;
      }
      final ok = await _startBlocking(profile);
      if (!ok) return;
      await widget.storage.setActiveSession(profile.id);
      await _syncState();
    }
  }

  // Starts blocking via whichever mechanism is active. Returns false on failure.
  Future<bool> _startBlocking(Profile profile) async {
    if (widget.storage.dpcModeEnabled) {
      final ok = await BlockingService.dpcSetQuietMode(true);
      if (!ok && mounted) {
        _showSnack('Could not enable Work Profile blocking — check settings');
      }
      return ok;
    } else {
      final ok = await BlockingService.startBlocking(
        profile.blockedPackages,
        profileName: profile.name,
      );
      if (!ok && mounted) {
        _showSnack('Could not start blocking — check Accessibility permission');
      }
      return ok;
    }
  }

  Future<void> _stopBlocking() async {
    if (widget.storage.dpcModeEnabled) {
      await BlockingService.dpcSetQuietMode(false);
    } else {
      await BlockingService.stopBlocking();
    }
    await widget.storage.clearActiveSession();
    await _syncState();
  }

  // Presents the unblock-duration picker for a scheduled profile: 5/10/15 min
  // while inside its own schedule window (always re-bricks automatically),
  // plus "Unlimited" outside it (a real stop, with a re-brick nag armed).
  Future<void> _showUnblockOptions(Profile profile) async {
    final inSchedule = _isNowInSchedule(profile);
    final choice = await showModalBottomSheet<int>(
      context: context,
      builder: (ctx) => _UnblockOptionsSheet(
        profileName: profile.name,
        showUnlimited: !inSchedule,
      ),
    );
    if (choice == null || !mounted) return;

    if (choice == -1) {
      // Unlimited: a real stop. Nag only if this profile has its own
      // schedule and stopping happened outside that window.
      await BlockingService.stopBlocking(
        profileId: profile.id,
        armReminder: profile.scheduleEnabled && !inSchedule,
      );
      await widget.storage.clearActiveSession();
    } else {
      await BlockingService.startTempUnblock(
        profileId: profile.id,
        profileName: profile.name,
        minutes: choice,
      );
      // Session stays "active" — it'll silently resume on its own.
    }
    await _syncState();
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final profiles = widget.storage.getProfiles();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Lockout'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'New profile',
            onPressed: _newProfile,
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => SettingsScreen(storage: widget.storage),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          _SessionBanner(
            isBlocking: _isBlocking,
            activeProfile: _activeProfile,
            tempUnblockExpiry:
                _tempUnblockProfileId == _activeProfile?.id ? _tempUnblockExpiry : null,
          ),
          Expanded(
            child: profiles.isEmpty
                ? _EmptyState(onAdd: _newProfile)
                : ListView.builder(
                    itemCount: profiles.length,
                    itemBuilder: (_, i) => _ProfileTile(
                      profile: profiles[i],
                      isActive: _activeProfile?.id == profiles[i].id,
                      onTap: () => _toggle(profiles[i]),
                      onEdit: () => _editProfile(profiles[i]),
                      onDelete: () => _deleteProfile(profiles[i]),
                      onWriteTag: () => _writeTag(profiles[i]),
                    ),
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _nfcListening ? null : _tapNfc,
        icon: _nfcListening
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.nfc),
        label: Text(_nfcListening ? 'Waiting for tag…' : 'Tap NFC tag'),
      ),
    );
  }

  Future<void> _newProfile() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProfileEditScreen(storage: widget.storage),
      ),
    );
    await _syncState();
  }

  Future<void> _editProfile(Profile p) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProfileEditScreen(storage: widget.storage, profile: p),
      ),
    );
    // If this was the active profile and we're in AccessibilityService mode,
    // push the updated package list to the native layer immediately.
    // In DPC mode the work profile is frozen wholesale — no per-app update needed.
    if (_isBlocking && _activeProfile?.id == p.id && !widget.storage.dpcModeEnabled) {
      final updated = widget.storage.getProfile(p.id);
      if (updated == null || updated.blockedPackages.isEmpty) {
        await _stopBlocking();
      } else {
        await BlockingService.startBlocking(updated.blockedPackages);
      }
    }
    await _syncState();
  }

  Future<void> _deleteProfile(Profile p) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete profile?'),
        content: Text('Delete "${p.name}"? This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (confirm == true) {
      // Stop native blocking before removing the profile so we don't end up
      // with the service blocking apps and no UI affordance to stop it.
      if (_isBlocking && _activeProfile?.id == p.id) {
        await BlockingService.stopBlocking();
      }
      await widget.storage.deleteProfile(p.id);
      await _syncState();
    }
  }

  Future<void> _writeTag(Profile p) async {
    final available = await NfcService.isAvailable;
    if (!available) {
      _showSnack('NFC not available');
      return;
    }
    if (!mounted) return;

    bool cancelled = false;
    unawaited(showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _NfcWriteDialog(
        onCancel: () {
          cancelled = true;
          NfcService.cancelNfc();
          Navigator.of(ctx).pop();
        },
      ),
    ));

    try {
      await NfcService.writeTag(p.id);
      if (mounted && !cancelled) {
        Navigator.of(context).pop();
        _showSnack('Tag written for "${p.name}"');
      }
    } catch (e) {
      if (mounted && !cancelled) {
        Navigator.of(context).pop();
        _showSnack('Write failed: $e');
      }
    }
  }
}

// ── Unblock duration picker ──────────────────────────────────────────────────

class _UnblockOptionsSheet extends StatelessWidget {
  final String profileName;
  final bool showUnlimited;

  const _UnblockOptionsSheet({required this.profileName, required this.showUnlimited});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Unblock "$profileName"', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              showUnlimited
                  ? 'Pick how long, or stop until you re-brick it yourself.'
                  : 'Still inside your schedule — pick how long, it re-bricks automatically.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            for (final minutes in const [5, 10, 15])
              ListTile(
                leading: const Icon(Icons.timer_outlined),
                title: Text('$minutes minutes'),
                onTap: () => Navigator.pop(context, minutes),
              ),
            if (showUnlimited)
              ListTile(
                leading: const Icon(Icons.lock_open),
                title: const Text('Unlimited'),
                onTap: () => Navigator.pop(context, -1),
              ),
          ],
        ),
      ),
    );
  }
}

// ── NFC write modal ──────────────────────────────────────────────────────────

class _NfcWriteDialog extends StatelessWidget {
  final VoidCallback onCancel;
  const _NfcWriteDialog({required this.onCancel});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Write NFC tag'),
      content: const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 20),
          Text(
            'Hold a writable NFC tag\nto the back of your phone.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: onCancel, child: const Text('Cancel')),
      ],
    );
  }
}

// ── Session banner ───────────────────────────────────────────────────────────

class _SessionBanner extends StatelessWidget {
  final bool isBlocking;
  final Profile? activeProfile;
  final DateTime? tempUnblockExpiry;

  const _SessionBanner({
    required this.isBlocking,
    required this.activeProfile,
    this.tempUnblockExpiry,
  });

  @override
  Widget build(BuildContext context) {
    if (!isBlocking && tempUnblockExpiry == null) return const SizedBox.shrink();
    final name = activeProfile?.name ?? '';

    final String label;
    final IconData icon;
    final Color color;
    if (tempUnblockExpiry != null) {
      final remaining = tempUnblockExpiry!.difference(DateTime.now());
      final mins = remaining.inSeconds > 0 ? (remaining.inSeconds / 60).ceil() : 0;
      label = '${name.isNotEmpty ? name : 'Profile'} unblocked — re-bricks in $mins min';
      icon = Icons.lock_open;
      color = Theme.of(context).colorScheme.secondary;
    } else {
      label = name.isNotEmpty ? name : 'Blocking active';
      icon = Icons.lock;
      color = Theme.of(context).colorScheme.primary;
    }

    return Container(
      color: color,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(icon, color: Colors.white),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Profile tile ─────────────────────────────────────────────────────────────

class _ProfileTile extends StatelessWidget {
  final Profile profile;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onWriteTag;

  const _ProfileTile({
    required this.profile,
    required this.isActive,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
    required this.onWriteTag,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(
        isActive ? Icons.lock : Icons.lock_open,
        color: isActive ? Theme.of(context).colorScheme.primary : null,
      ),
      title: Text(profile.name),
      subtitle: Text(
        profile.blockedPackages.isEmpty
            ? 'No apps added yet'
            : isActive
                ? 'Blocking ${profile.blockedPackages.length} app${profile.blockedPackages.length == 1 ? '' : 's'}'
                : '${profile.blockedPackages.length} app${profile.blockedPackages.length == 1 ? '' : 's'}',
      ),
      onTap: onTap,
      trailing: PopupMenuButton<String>(
        onSelected: (v) {
          if (v == 'edit') onEdit();
          if (v == 'write') onWriteTag();
          if (v == 'delete') onDelete();
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'edit', child: Text('Edit')),
          PopupMenuItem(value: 'write', child: Text('Write to NFC tag')),
          PopupMenuItem(value: 'delete', child: Text('Delete')),
        ],
      ),
    );
  }
}

// ── Empty state ──────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.nfc, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          const Text('No profiles yet', style: TextStyle(fontSize: 18)),
          const SizedBox(height: 8),
          const Text(
            'Create a profile, then write it to an NFC tag.',
            style: TextStyle(color: Colors.grey),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add),
            label: const Text('Create profile'),
          ),
        ],
      ),
    );
  }
}
