import 'dart:convert';
import 'dart:math' as math;

/// A single placed note, stored in a serializable form (no animation state).
class SongNote {
  final String emoji;
  final int gridX;
  final int gridY;
  final double velocity;
  const SongNote(this.emoji, this.gridX, this.gridY, {this.velocity = 1.0});

  Map<String, dynamic> toJson() =>
      {'e': emoji, 'x': gridX, 'y': gridY, if (velocity != 1.0) 'v': velocity};
  factory SongNote.fromJson(Map<String, dynamic> j) => SongNote(
        j['e'] as String,
        (j['x'] as num).toInt(),
        (j['y'] as num).toInt(),
        velocity: (j['v'] as num?)?.toDouble() ?? 1.0,
      );
}

/// A saved composition. Persisted as one JSON file per song in the app's
/// documents directory (see [SongLibrary]).
class Song {
  final String id;
  String name;
  double bpm;
  List<String> palette;
  String? selectedEmoji;
  List<SongNote> notes;
  int updatedAt; // epoch ms

  Song({
    required this.id,
    required this.name,
    required this.bpm,
    required this.palette,
    required this.selectedEmoji,
    required this.notes,
    required this.updatedAt,
  });

  factory Song.fresh({
    required String name,
    required double bpm,
    required List<String> palette,
    String? selectedEmoji,
  }) =>
      Song(
        id: _newId(),
        name: name,
        bpm: bpm,
        palette: List.of(palette),
        selectedEmoji: selectedEmoji,
        notes: [],
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );

  Map<String, dynamic> toJson() => {
        'v': 1,
        'id': id,
        'name': name,
        'bpm': bpm,
        'palette': palette,
        'selectedEmoji': selectedEmoji,
        'notes': notes.map((n) => n.toJson()).toList(),
        'updatedAt': updatedAt,
      };

  factory Song.fromJson(Map<String, dynamic> j) => Song(
        id: j['id'] as String,
        name: (j['name'] as String?) ?? 'Untitled',
        bpm: (j['bpm'] as num?)?.toDouble() ?? 110,
        palette: (j['palette'] as List?)?.cast<String>() ?? const [],
        selectedEmoji: j['selectedEmoji'] as String?,
        notes: (j['notes'] as List? ?? const [])
            .map((n) => SongNote.fromJson(n as Map<String, dynamic>))
            .toList(),
        updatedAt: (j['updatedAt'] as num?)?.toInt() ?? 0,
      );

  String encode() => jsonEncode(toJson());
  static Song decode(String s) => Song.fromJson(jsonDecode(s) as Map<String, dynamic>);

  static String _newId() {
    final t = DateTime.now().microsecondsSinceEpoch;
    final r = math.Random().nextInt(1 << 20);
    return '${t.toRadixString(36)}-${r.toRadixString(36)}';
  }
}

/// Deployed web player. It loads a song straight from a `#s=<code>` URL fragment
/// (see the web app's `tryRestoreSong`), so a single link lets anyone open,
/// play, and remix the song in a browser — the app's "share a song" promise.
const String kWebPlayerBase = 'https://emojio-composer.madewithbestpractice.com';

/// Builds a web-player share link whose `#s=` payload is byte-compatible with
/// the web app's encoder: `base64(utf8(json))` of
/// `{v, bpm, palette, notes:[{p, x, y, e?}]}`, where `p` is the palette index
/// and `e` carries the raw emoji only when it isn't in the palette.
String webShareUrl({
  required double bpm,
  required List<String> palette,
  required List<SongNote> notes,
}) {
  final obj = {
    'v': 1,
    'bpm': bpm,
    'palette': palette,
    'notes': notes.map((n) {
      final p = palette.indexOf(n.emoji);
      return {'p': p, 'x': n.gridX, 'y': n.gridY, if (p < 0) 'e': n.emoji};
    }).toList(),
  };
  final code = base64.encode(utf8.encode(jsonEncode(obj)));
  return '$kWebPlayerBase/#s=$code';
}
