import 'package:flutter/services.dart';
import '../models/app_info.dart';

// MethodChannel bridge to native blocking layer.
//
// Android: AccessibilityService detects foreground app changes and redirects
//          blocked apps to the home screen. No polling, no GMS.
// iOS:     FamilyControls / ManagedSettings (Screen Time API) — requires
//          one-time authorization on first use.
class BlockingService {
  static const _channel = MethodChannel('com.lockout/blocking');

  // Start blocking for the given package names.
  static Future<bool> startBlocking(List<String> packages) async {
    try {
      final result = await _channel.invokeMethod<bool>(
        'startBlocking',
        {'packages': packages},
      );
      return result ?? false;
    } on PlatformException catch (e) {
      if (e.code == 'PERMISSION_DENIED') return false;
      rethrow;
    }
  }

  // Stop all blocking.
  static Future<void> stopBlocking() async {
    await _channel.invokeMethod<void>('stopBlocking');
  }

  // Whether the native blocking service is running.
  static Future<bool> isBlocking() async {
    final result = await _channel.invokeMethod<bool>('isBlocking');
    return result ?? false;
  }

  // Whether the Accessibility Service permission is granted (Android only).
  static Future<bool> hasAccessibilityPermission() async {
    final result =
        await _channel.invokeMethod<bool>('hasAccessibilityPermission');
    return result ?? false;
  }

  // Opens system Accessibility Settings so the user can enable the service.
  static Future<void> openAccessibilitySettings() async {
    await _channel.invokeMethod<void>('openAccessibilitySettings');
  }

  // Returns the profile ID from an NFC tag that launched the app via
  // Android's NDEF_DISCOVERED dispatch, then clears it. Returns null if
  // no pending tag exists (normal foreground launch).
  static Future<String?> getPendingNfcTag() async {
    final result = await _channel.invokeMethod<String?>('getPendingNfcTag');
    return result;
  }

  // ── DPC / Work Profile ───────────────────────────────────────────────────
  // All methods require Android 9+ and the app to be the managed-profile owner.
  // Call dpcProvisionManagedProfile first to set that up.

  // Whether the app is already the profile owner of a managed work profile.
  static Future<bool> dpcHasManagedProfile() async {
    final result = await _channel.invokeMethod<bool>('dpcHasManagedProfile');
    return result ?? false;
  }

  // Whether the work profile is currently in quiet mode (= blocking active).
  static Future<bool> dpcIsQuietModeEnabled() async {
    final result = await _channel.invokeMethod<bool>('dpcIsQuietModeEnabled');
    return result ?? false;
  }

  // Enable or disable quiet mode on the work profile.
  // Returns false if quiet mode is not supported (< Android 9) or no profile exists.
  static Future<bool> dpcSetQuietMode(bool enabled) async {
    try {
      final result = await _channel.invokeMethod<bool>(
        'dpcSetQuietMode',
        {'enabled': enabled},
      );
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }

  // Start the Android managed-profile provisioning flow.
  // Returns true if provisioning succeeded (or was already done).
  // Returns false if the user cancelled or the device doesn't support it.
  static Future<bool> dpcProvisionManagedProfile() async {
    try {
      final result =
          await _channel.invokeMethod<bool>('dpcProvisionManagedProfile');
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }

  // ── Installed apps ────────────────────────────────────────────────────────

  // Returns list of installed user apps (excludes system apps).
  // Cached after first call — app list changes rarely.
  static List<AppInfo>? _cachedApps;

  static Future<List<AppInfo>> getInstalledApps({bool refresh = false}) async {
    if (_cachedApps != null && !refresh) return _cachedApps!;
    final raw = await _channel.invokeListMethod<Map>('getInstalledApps');
    if (raw == null) return [];
    _cachedApps = raw
        .map((m) => AppInfo(
              packageName: m['packageName'] as String,
              appName: m['appName'] as String,
            ))
        .toList()
      ..sort((a, b) => a.appName.compareTo(b.appName));
    return _cachedApps!;
  }

  // Returns 64×64 PNG icon bytes for an installed app, or null if unavailable.
  // Results are cached in memory for the lifetime of the app process.
  static final Map<String, Uint8List?> _iconCache = {};

  static Future<Uint8List?> getAppIcon(String packageName) async {
    if (_iconCache.containsKey(packageName)) return _iconCache[packageName];
    try {
      final bytes = await _channel.invokeMethod<Uint8List>(
        'getAppIcon',
        {'packageName': packageName},
      );
      _iconCache[packageName] = bytes;
      return bytes;
    } catch (_) {
      _iconCache[packageName] = null;
      return null;
    }
  }
}
