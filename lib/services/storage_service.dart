import 'package:shared_preferences/shared_preferences.dart';
import '../models/profile.dart';

// Persists profiles and active session to local storage.
// Session state survives reboots — if blocking was active when the phone
// shut down, it resumes automatically on next app start.
class StorageService {
  static const _profilesKey = 'profiles';
  static const _activeProfileIdKey = 'active_profile_id';
  static const _sessionEndTimeKey = 'session_end_time';
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

  // [duration] null means no time limit.
  Future<void> setActiveSession(String profileId, {Duration? duration}) async {
    await _prefs.setString(_activeProfileIdKey, profileId);
    if (duration != null) {
      final endTime = DateTime.now().add(duration);
      await _prefs.setString(_sessionEndTimeKey, endTime.toIso8601String());
    } else {
      await _prefs.remove(_sessionEndTimeKey);
    }
  }

  DateTime? getSessionEndTime() {
    final raw = _prefs.getString(_sessionEndTimeKey);
    if (raw == null) return null;
    return DateTime.tryParse(raw);
  }

  Future<void> clearActiveSession() async {
    await _prefs.remove(_activeProfileIdKey);
    await _prefs.remove(_sessionEndTimeKey);
  }

  bool get hasActiveSession => getActiveProfileId() != null;

  bool get dpcModeEnabled => _prefs.getBool(_dpcModeKey) ?? false;
  Future<void> setDpcMode(bool value) => _prefs.setBool(_dpcModeKey, value);
}
