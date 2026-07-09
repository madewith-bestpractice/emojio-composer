import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'song.dart';

/// Local, on-device song storage: one JSON file per song under
/// `<app documents>/songs/`. No network, no account — the native "save songs
/// locally" capability. (iCloud sync is a later enhancement.)
class SongLibrary {
  Directory? _dir;

  Future<Directory> _songsDir() async {
    if (_dir != null) return _dir!;
    final base = await getApplicationDocumentsDirectory();
    final d = Directory('${base.path}/songs');
    if (!await d.exists()) await d.create(recursive: true);
    return _dir = d;
  }

  /// All saved songs, newest-edited first. Skips any unreadable files.
  Future<List<Song>> list() async {
    final d = await _songsDir();
    final songs = <Song>[];
    await for (final f in d.list()) {
      if (f is File && f.path.endsWith('.json')) {
        try {
          songs.add(Song.decode(await f.readAsString()));
        } catch (_) {
          // corrupt/foreign file — ignore
        }
      }
    }
    songs.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return songs;
  }

  Future<void> save(Song s) async {
    s.updatedAt = DateTime.now().millisecondsSinceEpoch;
    final d = await _songsDir();
    await File('${d.path}/${s.id}.json').writeAsString(s.encode());
  }

  Future<void> delete(String id) async {
    final d = await _songsDir();
    final f = File('${d.path}/$id.json');
    if (await f.exists()) await f.delete();
  }
}
