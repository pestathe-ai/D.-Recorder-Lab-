#!/usr/bin/env bash
# Genera le cartelle di piattaforma (non salvate nel repository) e le adatta.
set -euo pipefail
cd "$(dirname "$0")/.."

flutter create --project-name d_recorder_lab --org dev.drecorderlab --platforms=android,ios .
rm -f test/widget_test.dart

GRADLE=android/app/build.gradle.kts
[ -f "$GRADLE" ] || GRADLE=android/app/build.gradle
sed -i -E 's/minSdk *= *flutter\.minSdkVersion/minSdk = 24/; s/minSdkVersion +flutter\.minSdkVersion/minSdkVersion 24/' "$GRADLE"
grep -n "minSdk" "$GRADLE" || true

# Codice nativo: registratore in primo piano e servizio di elaborazione.
KT=android/app/src/main/kotlin/dev/drecorderlab/d_recorder_lab
mkdir -p "$KT"
cp tool/android/*.kt "$KT/"

MANIFEST=android/app/src/main/AndroidManifest.xml
sed -i 's/android:label="d_recorder_lab"/android:label="D. Recorder Lab"/' "$MANIFEST"
PERMS=""
for p in RECORD_AUDIO INTERNET WAKE_LOCK POST_NOTIFICATIONS FOREGROUND_SERVICE FOREGROUND_SERVICE_MICROPHONE FOREGROUND_SERVICE_DATA_SYNC; do
  PERMS="$PERMS<uses-permission android:name=\"android.permission.$p\"/>\n    "
done
sed -i "s#<application#$PERMS<application#" "$MANIFEST"
SERVICES='<service android:name=".RecorderService" android:exported="false" android:foregroundServiceType="microphone"/>\n        <service android:name=".ProcessingService" android:exported="false" android:foregroundServiceType="dataSync"/>\n    '
sed -i "s#</application>#$SERVICES</application>#" "$MANIFEST"
grep -n "uses-permission\|android:label\|<service" "$MANIFEST" || true

if [[ "$(uname)" == "Darwin" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName D. Recorder Lab" ios/Runner/Info.plist || true
  /usr/libexec/PlistBuddy -c "Add :NSMicrophoneUsageDescription string Serve per registrare le riunioni." ios/Runner/Info.plist || true
  [ -f ios/Podfile ] && sed -i '' "s/^# platform :ios.*/platform :ios, '13.0'/" ios/Podfile || true
fi

flutter pub get
dart run flutter_launcher_icons
