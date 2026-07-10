import 'package:emojio/song.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('share link', () {
    test('webShareUrl round-trips through the Dart decoder', () {
      const palette = ['🐶', '🐱', '🎺'];
      final notes = [
        const SongNote('🐶', 0, 3),
        const SongNote('🎺', 4, 7),
        const SongNote('🦄', 8, 1), // not in palette -> carried as raw emoji
      ];
      final url = webShareUrl(bpm: 128, palette: palette, notes: notes);

      expect(url, startsWith('$kWebPlayerBase/play#s='));

      final decoded = sharedSongFromUri(Uri.parse(url));
      expect(decoded, isNotNull);
      expect(decoded!.bpm, 128);
      expect(decoded.palette, palette);
      expect(decoded.notes.length, 3);
      expect(decoded.notes.map((n) => n.emoji).toList(), ['🐶', '🎺', '🦄']);
      expect(decoded.notes[2].gridX, 8);
      expect(decoded.notes[2].gridY, 1);
    });

    // Matches the web app's encoder exactly (index.html: encodeSongObject +
    // getSharableSong), so a link made here opens in the web player.
    test('payload is byte-compatible with the web app format', () {
      const palette = ['🐶'];
      final url = webShareUrl(bpm: 110, palette: palette, notes: [const SongNote('🐶', 0, 0)]);
      final code = url.split('#s=').last;
      final decoded = sharedSongFromCode(code);
      expect(decoded, isNotNull);
      expect(decoded!.notes.single.emoji, '🐶');
    });

    test('non-song and malformed URLs decode to null', () {
      expect(sharedSongFromUri(Uri.parse('$kWebPlayerBase/')), isNull);
      expect(sharedSongFromUri(Uri.parse('$kWebPlayerBase/#s=not-base64!!')), isNull);
      expect(sharedSongFromCode('garbage'), isNull);
    });
  });
}
