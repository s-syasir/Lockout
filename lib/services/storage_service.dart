import 'package:shared_preferences/shared_preferences.dart';
import '../models/profile.dart';

// Persists profiles and active session to local storage.
// Session state survives reboots — if blocking was active when the phone
// shut down, it resumes automatically on next app start.
class StorageService {
  static const _profilesKey = 'profiles';
  static const _activeProfileIdKey = 'active_profile_id';
  static const _dpcModeKey = 'dpc_mode';

  final SharedPreferences _prefs;

  StorageService._(this._prefs);

  static Future<StorageService> init() async {
    final prefs = await SharedPreferences.getInstance();
    return StorageService._(prefs);
  }

  List<Profile> getProfiles() {
    final raw = _prefs.getString(_profilesKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      return Profile.listFromJson(raw);
    } catch (_) {
      return [];
    }
  }

  Future<void> saveProfiles(List<Profile> profiles) async {
    await _prefs.setString(_profilesKey, Profile.listToJson(profiles));
  }

  Profile? getProfile(String id) {
    return getProfiles().where((p) => p.id == id).firstOrNull;
  }

  Future<void> upsertProfile(Profile profile) async {
    final profiles = getProfiles();
    final idx = profiles.indexWhere((p) => p.id == profile.id);
    if (idx >= 0) {
      profiles[idx] = profile;
    } else {
      profiles.add(profile);
    }
    await saveProfiles(profiles);
  }

  Future<void> deleteProfile(String id) async {
    final profiles = getProfiles()..removeWhere((p) => p.id == id);
    await saveProfiles(profiles);
    if (getActiveProfileId() == id) await clearActiveSession();
  }

  String? getActiveProfileId() => _prefs.getString(_activeProfileIdKey);

  Future<void> setActiveSession(String profileId) async {
    await _prefs.setString(_activeProfileIdKey, profileId);
  }

  Future<void> clearActiveSession() async {
    await _prefs.remove(_activeProfileIdKey);
  }

  bool get hasActiveSession => getActiveProfileId() != null;

  bool get dpcModeEnabled => _prefs.getBool(_dpcModeKey) ?? false;
  Future<void> setDpcMode(bool value) => _prefs.setBool(_dpcModeKey, value);
}
