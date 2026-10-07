import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'song.dart';

/// The store-screenshot setup this launch runs, or null (always null in a
/// release build, so a shipped app can't be put in this mode): `compose`,
/// `play`, `picker`, `library`, `export`, `midi` or `paywall`. Set by
/// [loadStoreDemo].
String? storeDemo;

/// Reads the setup from the EMOJIO_DEMO environment variable or, since iOS
/// doesn't hand the simulator's launch environment to Dart, from an
/// `emojio_demo` file in the app's Documents folder (what
/// tool/store_shots/capture.sh writes before each launch).
Future<void> loadStoreDemo() async {
  if (kReleaseMode) return;
  storeDemo = Platform.environment['EMOJIO_DEMO'];
  if (storeDemo != null) return;
  try {
    final f = File(
      '${(await getApplicationDocumentsDirectory()).path}/emojio_demo',
    );
    if (await f.exists()) storeDemo = (await f.readAsString()).trim();
  } catch (_) {}
}

const _palette = ['🐸', '🎹', '🐶', '🎺', '🥁', '👏'];

/// The hero song: a melody arcing over the staff, drums and claps below it.
SharedSong demoSong() => SharedSong(
  bpm: 112,
  palette: _palette,
  notes: [
    for (final (e, x, y) in const [
      ('🎹', 0, 7),
      ('🐸', 1, 5),
      ('🎹', 2, 4),
      ('🐶', 3, 2),
      ('🎺', 4, 3),
      ('🐸', 6, 4),
      ('🎹', 7, 6),
      ('🐶', 8, 7),
      ('🎺', 9, 5),
      ('🐸', 10, 3),
      ('🎹', 11, 1),
      ('🐶', 12, 0),
      ('🎺', 14, 2),
      ('🐸', 15, 4),
      ('🥁', 0, 14),
      ('🥁', 4, 14),
      ('🥁', 8, 14),
      ('🥁', 12, 14),
      ('🥁', 10, 13),
      ('👏', 4, 11),
      ('👏', 12, 11),
    ])
      SongNote(e, x, y),
  ],
);

/// A small library for the Songs screen.
List<(String, SharedSong)> demoLibrary() {
  SharedSong song(List<String> palette, List<(int, int, int)> notes) =>
      SharedSong(
        bpm: 110,
        palette: palette,
        notes: [for (final (p, x, y) in notes) SongNote(palette[p], x, y)],
      );
  return [
    ('Frog Jam', demoSong()),
    (
      'Drum Party',
      song(
        ['🥁', '👏', '💥', '🪇'],
        [for (var x = 0; x < 16; x++) (x % 4, x, 14 - (x % 4) * 2)],
      ),
    ),
    (
      'Sunny Loop',
      song(
        ['🐶', '🐱', '🐷', '🎸'],
        [for (var x = 0; x < 16; x += 2) (x ~/ 2 % 4, x, 3 + (x ~/ 2 % 5))],
      ),
    ),
    (
      'Bedtime Bells',
      song(
        ['🔔', '🎻', '😴', '🦉'],
        [for (var x = 0; x < 16; x += 3) (x % 4, x, 9 - x ~/ 3)],
      ),
    ),
  ];
}
