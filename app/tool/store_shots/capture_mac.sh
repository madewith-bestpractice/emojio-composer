#!/bin/zsh
# Captures the raw Mac store screenshots: runs the debug macOS build once per
# screen with EMOJIO_DEMO set (macOS hands the environment to Dart) and grabs
# its window. Skips `library`: on a Mac the demo would add its songs to your
# own Emojio library.
#
#   flutter build macos --debug        # first (takes a heavy-lane slot)
#   tool/store_shots/capture_mac.sh [modes...]
#
# Needs Screen Recording permission for the terminal running it.
cd "$(dirname "$0")"
MODES=($@)
(( ${#MODES} )) || MODES=(compose play picker export midi)
BIN=../../build/macos/Build/Products/Debug/emojio.app/Contents/MacOS/emojio
OUT="${STORE_SHOTS_WORK:-/Volumes/GetawayCar/tmp/emojio-shots}/raw/mac"
WINID=$(mktemp -t winid)
swiftc -O winid.swift -o $WINID 2>/dev/null || exit 1
mkdir -p "$OUT"
for m in $MODES; do
  pkill -f "Debug/emojio.app" 2>/dev/null; sleep 2
  (EMOJIO_DEMO=$m "$BIN" >/dev/null 2>&1 &)
  sleep 40
  W=$($WINID emojio | cut -d' ' -f1)
  if [[ -n $W ]] && screencapture -x -o -l $W "$OUT/$m.png"; then echo "mac/$m"
  else echo "mac/$m: capture failed" >&2; fi
done
pkill -f "Debug/emojio.app" 2>/dev/null
rm -f $WINID
