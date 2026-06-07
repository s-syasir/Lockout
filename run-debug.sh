#!/usr/bin/env bash
set -e
cd "$(dirname "$0")/android"
bash gradlew assembleDebug
adb install -r ../build/app/outputs/flutter-apk/app-debug.apk
