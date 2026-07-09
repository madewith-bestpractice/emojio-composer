import 'dart:convert';
import 'dart:math' as math;

/// A single placed note, stored in a serializable form (no animation state).
class SongNote {
  final String emoji;
  final int gridX;
  final int gridY;
  const SongNote(this.emoji, this.gridX, this.gridY);

  Map<String, dynamic> toJson() => {'e': emoji, 'x': gridX, 'y': gridY};
  factory SongNote.fromJson(Map<String, dynamic> j) =>
      SongNote(j['e'] as String, (j['x'] as num).toInt(), (j['y'] as num).toInt());
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
