#!/bin/zsh
# Proves Emojio receives from a virtual MIDI source with no destination, and still from one that
# has both ports. macOS only. Silent: the test touches MidiManager only, never the audio engine,
# and the helper sends MIDI bytes only. Run it inside a heavy-lane slot (it builds the Mac app).
set -u
HERE=${0:A:h}
APP=${HERE:h:h}
TMP=${TMPDIR:-/tmp}
swiftc -O $HERE/source_only.swift -o $TMP/emojio_source_only || exit 1
rc=0
for shape in ${=SHAPES:-in both}; do
  name="Emojio Test Source $shape"
  flags=(); [ $shape = both ] && flags=(--with-destination)
  $TMP/emojio_source_only "$name" $flags > $TMP/emojio_source_only.$shape.log 2>&1 &
  pid=$!
  sleep 1
  (cd $APP && flutter test integration_test/midi_source_only_test.dart -d macos \
      --dart-define=MIDI_TEST_DEVICE="$name" --dart-define=MIDI_TEST_SHAPE=$shape --dart-define=EMOJIO_SILENT=true) || rc=1
  kill $pid 2>/dev/null; wait $pid 2>/dev/null
done
exit $rc
