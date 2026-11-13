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

const _palette = ['🐸', '🦄', '🐶', '🐔', '🥁', '👏'];

/// The hero song: a sunny one-bar hook in C major. The melody climbs C-E-G,
/// peaks, steps back down, and the chicken's B leads it round into the next
/// loop. A four-on-the-floor kick sits on the bottom line and claps land on
/// beats 2 and 4 (percussion goes on any row, like any emoji).
SharedSong demoSong() => SharedSong(
  bpm: 120,
  palette: _palette,
  notes: [
    for (final (e, x, y) in const [
      // Melody (row: 0 = G5, 2 = E5, 4 = C5, 7 = G4).
      ('🐸', 0, 4), // C5
      ('🐸', 2, 2), // E5
      ('🦄', 4, 0), // G5
      ('🦄', 6, 2), // E5
      ('🐶', 7, 1), // F5
      ('🐶', 8, 0), // G5
      ('🐸', 10, 2), // E5
      ('🦄', 12, 3), // D5
      ('🐶', 13, 7), // G4
      ('🐔', 14, 5), // B4, back to C
      // Kick on every beat plus a skip, claps on 2 and 4.
      ('🥁', 0, 9),
      ('🥁', 4, 9),
      ('🥁', 8, 9),
      ('🥁', 10, 9),
      ('🥁', 12, 9),
      ('👏', 4, 6),
      ('👏', 12, 6),
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
    ('Happy Hop', demoSong()),
    (
      'Drum Party',
      song(
        ['🥁', '👏', '💥', '🪇'],
        [for (var x = 0; x < 16; x++) (x % 4, x, 9 - (x % 4) * 2)],
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
