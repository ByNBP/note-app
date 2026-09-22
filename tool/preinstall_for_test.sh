#!/usr/bin/env bash
# MIUI/HyperOS ardisik `adb install` cagrilarini kisitlayip
# INSTALL_FAILED_USER_RESTRICTED donduruyor. Bu betik APK'yi shell uzerinden
# kurar (bu yol kisitlamaya takilmiyor) ve Flutter'in "zaten guncel kurulu"
# isaretini birakir, boylece `flutter test -d <cihaz>` kurulum adimini atlar.
#
#   tool/preinstall_for_test.sh <cihaz-id>
set -euo pipefail

DEVICE="${1:?kullanim: preinstall_for_test.sh <cihaz-id>}"
PKG="com.example.ortaknotlar"
APK="build/app/outputs/flutter-apk/app-debug.apk"
ADB="${ANDROID_HOME:-$HOME/Android/Sdk}/platform-tools/adb"

[ -f "$APK" ] || { echo "APK yok: $APK (once flutter build/test calistir)"; exit 1; }
[ -f "$APK.sha1" ] || { echo "sha1 yok: $APK.sha1"; exit 1; }

echo "APK kopyalaniyor…"
"$ADB" -s "$DEVICE" push "$APK" /data/local/tmp/$PKG.apk >/dev/null

echo "Kuruluyor (pm install)…"
"$ADB" -s "$DEVICE" shell pm install -r -t /data/local/tmp/$PKG.apk
"$ADB" -s "$DEVICE" shell rm -f /data/local/tmp/$PKG.apk

echo "Flutter'in kurulum isareti yaziliyor…"
"$ADB" -s "$DEVICE" push "$APK.sha1" /data/local/tmp/sky.$PKG.sha1 >/dev/null

echo "Hazir: $(cat "$APK.sha1")"
