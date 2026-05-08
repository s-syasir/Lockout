#!/usr/bin/env bash
set -e
cd "$(dirname "$0")"
flutter build apk --release
adb uninstall com.lockout.app 2>/dev/null || true
adb install build/app/outputs/flutter-apk/app-release.apk
