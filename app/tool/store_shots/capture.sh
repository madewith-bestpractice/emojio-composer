#!/bin/zsh
# Captures the raw store screenshots from the iOS simulator, using the
# debug-only store-demo hook (lib/store_demo.dart) to set up each screen.
# build.py then frames them.
#
#   tool/store_shots/capture.sh <simulator-udid> <iphone|ipad> [modes...]
#
# Build first (that takes a heavy-lane slot; this script doesn't):
#   flutter build ios --simulator --debug
# Raw output: $STORE_SHOTS_WORK/raw/<name>/<mode>.png
# (default /Volumes/GetawayCar/tmp/emojio-shots).
UDID=$1; NAME=$2; shift 2
MODES=($@)
(( ${#MODES} )) || MODES=(compose play picker library export midi)
APP="$(dirname "$0")/../../build/ios/iphonesimulator/Runner.app"
OUT="${STORE_SHOTS_WORK:-/Volumes/GetawayCar/tmp/emojio-shots}/raw/$NAME"
BID=com.madewithbestpractice.emojio
xcrun simctl boot $UDID 2>/dev/null
xcrun simctl status_bar $UDID override --time 9:41 --dataNetwork wifi \
  --wifiMode active --wifiBars 3 --cellularMode active --cellularBars 4 \
  --batteryState charged --batteryLevel 100
xcrun simctl terminate $UDID $BID 2>/dev/null
# A fresh install, so the library holds only the demo songs.
xcrun simctl uninstall $UDID $BID 2>/dev/null
xcrun simctl install $UDID "$APP"
mkdir -p "$OUT"
for m in $MODES; do
  xcrun simctl terminate $UDID $BID 2>/dev/null; sleep 2
  # iOS doesn't pass the launch environment through to Dart, so the app also
  # reads the mode from Documents/emojio_demo (lib/store_demo.dart).
  DOCS="$(xcrun simctl get_app_container $UDID $BID data)/Documents"
  mkdir -p "$DOCS" && print -n $m > "$DOCS/emojio_demo"
  SIMCTL_CHILD_EMOJIO_DEMO=$m xcrun simctl launch $UDID $BID >/dev/null
  sleep 45   # a debug build boots slowly
  # The simulator service can't write to an external volume: shoot to a temp
  # file, then move it into place.
  TMP=$(mktemp -t emojio-shot).png
  if xcrun simctl io $UDID screenshot "$TMP" >/dev/null 2>&1; then
    mv "$TMP" "$OUT/$m.png" && echo "$NAME/$m"
  else
    echo "$NAME/$m: screenshot failed" >&2
  fi
done
xcrun simctl terminate $UDID $BID 2>/dev/null
