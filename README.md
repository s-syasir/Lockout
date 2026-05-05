# Lockout

Open-source NFC-triggered app blocker for Android. No Play Services required. Works on GrapheneOS, CalyxOS, and microG.

**Tap an NFC tag → your distracting apps are blocked until you tap it again (or a timer runs out).**

---

## Features

| | |
|---|---|
| **NFC tag trigger** | Write a profile to a cheap NTAG213 tag (~$0.50). Tap once to start blocking, tap again to stop. |
| **Timed sessions** | Block for 15 min, 25 min (Pomodoro), 45 min, 1 hr, 2 hrs, or no time limit. |
| **Multiple profiles** | Focus, Bedtime, Work — each with its own app list. |
| **No internet permission** | Ever. No analytics, no telemetry, no crash reporting. Declared in the manifest and intentionally permanent. |
| **No Google Play Services** | Pure AOSP. Works on de-Googled ROMs. |
| **Session persistence** | Blocking survives app restart. |

---

## How it works

```
NFC tag tap (or manual profile tap in app)
    │
    ▼
Android NDEF_DISCOVERED intent → MainActivity
    │  extracts lockout:profile:<uuid> from tag payload
    ▼
Flutter HomeScreen picks up pending tag on resume
    │  looks up profile in local storage
    ▼
BlockingChannel (MethodChannel)
    │  persists package list to native SharedPreferences
    ▼
AccessibilityService (Kotlin)
    │  TYPE_WINDOW_STATE_CHANGED fires on every foreground change
    ▼
Blocked package in foreground?
    └─ yes → ACTION_MAIN / CATEGORY_HOME  (instant redirect, no root needed)
```

Tag payload: `lockout:profile:<uuid>` as an NDEF TextRecord. Fits any NTAG213 tag with room to spare.

---

## Requirements

- Android 8.0+ (API 26)
- NFC hardware *(optional — profiles can be started manually by tapping them in the app)*
- Accessibility Service permission *(one-time, guided on first launch)*

---

## Build

```bash
flutter pub get
flutter run           # debug on connected device
flutter build apk     # release APK (unsigned, debug key)
```

No Play Store signing config needed for local development.

---

## Project structure

```
lib/
  main.dart                       startup, expired-session guard, session resume
  models/
    profile.dart                  Profile model + JSON serialisation
    app_info.dart                 AppInfo (packageName, appName)
  services/
    storage_service.dart          SharedPreferences: profiles + active session
    blocking_service.dart         MethodChannel bridge to native layer
    nfc_service.dart              flutter_nfc_kit read/write wrapper
  screens/
    home_screen.dart              profile list, session banner + countdown, NFC FAB
    profile_edit_screen.dart      create/edit profile, searchable app picker, lazy icons
    onboarding_screen.dart        first-run Accessibility permission walkthrough
    settings_screen.dart          permission status, about, privacy note

android/…/kotlin/com/lockout/app/
  MainActivity.kt                 NFC intent dispatch, FlutterEngine setup
  BlockingChannel.kt              MethodChannel handler, app list, icon fetch, native prefs
  BlockingService.kt              AccessibilityService — the actual blocking core
  LockoutAdminReceiver.kt         DeviceAdminReceiver for Work Profile provisioning
```

---

## Key architecture decisions

**AccessibilityService, not UsageStatsManager**
UsageStatsManager requires polling (battery drain + coarse timing). `TYPE_WINDOW_STATE_CHANGED` fires synchronously — zero polling, sub-100 ms response.

**Send home, not force-stop**
Apps cannot force-stop other apps without root. `ACTION_MAIN / CATEGORY_HOME` is instant, reliable, and non-destructive to the target app's state.

**Profile ID on the tag, not the full profile**
NTAG213 has ~144 bytes. A UUID is 36 bytes. The profile lives in app storage; the tag is a key. You can rename or edit a profile at any time without rewriting the tag.

**Dual SharedPreferences (Flutter + native)**
If an OEM battery saver kills and restarts the `AccessibilityService` without relaunching the Flutter engine, the service restores its block list from native prefs in `onServiceConnected`. Flutter prefs handle the human-visible session state.

---

## Roadmap

- **P2 — Work Profile DPC blocking:** `DevicePolicyManager` freezing as a more reliable alternative for OEM devices with aggressive battery savers (Samsung, Xiaomi).

---

## License

MIT

<!-- 
  👀 you found it.
  this app was originally called BrickedUp.
  some names are better left locked away.
-->
