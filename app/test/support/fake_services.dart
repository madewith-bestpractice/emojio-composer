import 'package:emojio/main.dart';
import 'package:emojio/manifest.dart';
import 'package:emojio/midi/midi_manager.dart';
import 'package:emojio/monetization/trial.dart';
import 'package:emojio/song.dart';
import 'package:emojio/song_library.dart';
import 'package:emojio/voice_engine.dart';
import 'package:flutter_soloud/flutter_soloud.dart';

import 'fake_purchases.dart';

/// A [VoiceEngine] that reads the real manifest but never starts SoLoud: the
/// composer lays out and edits exactly as in the app, silently.
class SilentVoiceEngine extends VoiceEngine {
  @override
  Future<void> init(VoiceManifest m) async {
    manifest = m;
    ready = true;
  }

  @override
  int get activeVoices => 0;

  @override
  SoundHandle? playSynth(
    String synth,
    int targetMidi, {
    double velocity = 1.0,
    double pan = 0,
  }) => null;

  @override
  void release(SoundHandle h) {}

  @override
  Future<void> dispose() async => ready = false;
}

/// Songs in memory instead of the Documents folder.
class MemorySongLibrary extends SongLibrary {
  MemorySongLibrary([Iterable<Song> songs = const []]) {
    for (final s in songs) {
      _songs[s.id] = s;
    }
  }

  final Map<String, Song> _songs = {};

  @override
  Future<List<Song>> list() async =>
      _songs.values.toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  @override
  Future<void> save(Song s) async => _songs[s.id] = s;

  @override
  Future<void> delete(String id) async => _songs.remove(id);
}

/// A trial that is running ([active]) or long over, without the Keychain.
class FixedTrial extends TrialManager {
  FixedTrial({this.running = false});

  final bool running;

  @override
  Future<void> ensureStarted() async {}

  @override
  bool get active => running;

  @override
  int get daysLeft => running ? 3 : 0;
}

/// MIDI with no devices and no CoreMIDI.
class NoMidi extends MidiManager {
  @override
  Future<void> init() async {}
}

/// A store that answers nothing until asked.
class IdlePurchases extends FakePurchaseManager {
  @override
  Future<void> init() async {}
}

/// Everything the composer needs to boot in a widget test.
ComposerServices fakeServices({
  SharedSong? song,
  Iterable<Song> library = const [],
  bool trialRunning = false,
}) => ComposerServices(
  engine: SilentVoiceEngine(),
  library: MemorySongLibrary(library),
  trial: FixedTrial(running: trialRunning),
  purchases: IdlePurchases(),
  midi: NoMidi(),
  song: song,
);
