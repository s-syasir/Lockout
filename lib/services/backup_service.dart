import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import '../models/profile.dart';

// Handles JSON backup and restore of profiles.
// Export: user picks a save location via system file chooser (SAF).
// Import: user picks a .json file; profiles are merged by ID into existing storage.
class BackupService {
  static const _version = 1;

  // Serialize profiles to UTF-8 JSON bytes.
  static Uint8List encode(List<Profile> profiles) {
    final payload = jsonEncode({
      'v': _version,
      'profiles': profiles.map((p) => p.toJson()).toList(),
    });
    return Uint8List.fromList(utf8.encode(payload));
  }

  // Deserialize profiles from JSON bytes. Returns null on parse error.
  static List<Profile>? decode(Uint8List bytes) {
    try {
      final map = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      final list = map['profiles'] as List;
      return list
          .map((e) => Profile.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return null;
    }
  }

  // Opens the system file chooser and writes the backup.
  // Returns the saved path on success, null if the user cancelled.
  static Future<String?> exportProfiles(List<Profile> profiles) async {
    final bytes = encode(profiles);
    final timestamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .substring(0, 16);
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Save Lockout backup',
      fileName: 'lockout-backup-$timestamp.json',
      bytes: bytes,
    );
    return path;
  }

  // Opens the system file chooser to pick a backup file.
  // Returns the parsed profiles on success, null if cancelled or invalid.
  static Future<List<Profile>?> importProfiles() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Open Lockout backup',
      type: FileType.any,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;
    final bytes = result.files.first.bytes;
    if (bytes == null) return null;
    return decode(bytes);
  }
}
