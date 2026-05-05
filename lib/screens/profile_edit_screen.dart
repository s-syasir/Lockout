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

  bool get _isEditing => widget.profile != null;

  @override
  void initState() {
    super.initState();
    _nameController =
        TextEditingController(text: widget.profile?.name ?? '');
    _selected = Set.from(widget.profile?.blockedPackages ?? []);
    _loadApps();
  }

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
    final profile = Profile(
      id: widget.profile?.id ?? const Uuid().v4(),
      name: name,
      blockedPackages: _selected.toList(),
    );
    await widget.storage.upsertProfile(profile);
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
