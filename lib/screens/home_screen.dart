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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _syncState();
    _checkOnboarding();
    _checkPendingNfcTag();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _syncState();
      _checkPendingNfcTag();
    }
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
    if (!mounted) return;
    setState(() {
      _isBlocking = blocking;
      _activeProfile = profile;
    });
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
      await _stopBlocking();
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
      final ok = await BlockingService.startBlocking(profile.blockedPackages);
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

  const _SessionBanner({
    required this.isBlocking,
    required this.activeProfile,
  });

  @override
  Widget build(BuildContext context) {
    if (!isBlocking) return const SizedBox.shrink();
    final name = activeProfile?.name ?? '';
    final label = name.isNotEmpty ? name : 'Blocking active';
    return Container(
      color: Theme.of(context).colorScheme.primary,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          const Icon(Icons.lock, color: Colors.white),
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
