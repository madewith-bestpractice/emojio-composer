import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;

/// Parsed form of `assets/voices/manifest.json`, produced by
/// `tools/bake-voices.html`. Describes every baked synth voice as a set of
/// pitch zones (multisamples) plus the per-emoji synth/semitone mapping.

const String kVoicesDir = 'assets/voices';

class Zone {
  final int midi;
  final String note;
  final String file;
  final double durSec;
  const Zone(this.midi, this.note, this.file, this.durSec);

  factory Zone.fromJson(Map<String, dynamic> j) =>
      Zone(j['midi'] as int, j['note'] as String, j['file'] as String,
          (j['durSec'] as num).toDouble());
}

class Loop {
  final double startFrac;
  final double endFrac;
  const Loop(this.startFrac, this.endFrac);

  factory Loop.fromJson(Map<String, dynamic> j) =>
      Loop((j['startFrac'] as num).toDouble(), (j['endFrac'] as num).toDouble());
}

class Voice {
  final String type; // 'oneshot' | 'sustain'
  final double volumeDb;
  final Loop? loop;
  final List<Zone> zones;
  const Voice(this.type, this.volumeDb, this.loop, this.zones);

  bool get isSustain => type == 'sustain';

  factory Voice.fromJson(Map<String, dynamic> j) => Voice(
        j['type'] as String,
        (j['volumeDb'] as num?)?.toDouble() ?? 0,
        j['loop'] == null ? null : Loop.fromJson(j['loop'] as Map<String, dynamic>),
        (j['zones'] as List).map((z) => Zone.fromJson(z as Map<String, dynamic>)).toList(),
      );

  /// Zone whose base pitch is closest to [midi] — the one to varispeed from.
  Zone nearestZone(int midi) => zones.reduce(
      (a, b) => (b.midi - midi).abs() < (a.midi - midi).abs() ? b : a);
}

class EmojiVoice {
  final String synth;
  final int semi;
  final String dur;
  const EmojiVoice(this.synth, this.semi, this.dur);

  factory EmojiVoice.fromJson(Map<String, dynamic> j) => EmojiVoice(
      j['synth'] as String, (j['semi'] as num?)?.toInt() ?? 0, '${j['dur']}');
}

class VoiceManifest {
  final int sampleRate;
  final List<String> scale; // 15 note names, high -> low (matches the app's SCALE)
  final Map<String, Voice> voices;
  final Map<String, EmojiVoice> emojiVoices;

  const VoiceManifest(this.sampleRate, this.scale, this.voices, this.emojiVoices);

  /// Emojis whose voice is actually bundled (present in [voices]) — so every
  /// palette entry is guaranteed to make sound.
  List<String> playableEmojis() => emojiVoices.entries
      .where((e) => voices.containsKey(e.value.synth))
      .map((e) => e.key)
      .toList();

  static Future<VoiceManifest> load() async {
    final raw = await rootBundle.loadString('$kVoicesDir/manifest.json');
    final j = jsonDecode(raw) as Map<String, dynamic>;
    return VoiceManifest(
      (j['sampleRate'] as num).toInt(),
      (j['scale'] as List).cast<String>(),
      (j['voices'] as Map<String, dynamic>)
          .map((k, v) => MapEntry(k, Voice.fromJson(v as Map<String, dynamic>))),
      (j['emojiVoices'] as Map<String, dynamic>)
          .map((k, v) => MapEntry(k, EmojiVoice.fromJson(v as Map<String, dynamic>))),
    );
  }
}

/// Note name (e.g. "G#4", "Bb3") -> MIDI number. A4 = 69, C4 = 60.
int noteToMidi(String n) {
  const base = {'C': 0, 'D': 2, 'E': 4, 'F': 5, 'G': 7, 'A': 9, 'B': 11};
  final m = RegExp(r'^([A-G])([#b]?)(-?\d+)$').firstMatch(n);
  if (m == null) return 60;
  var semi = base[m.group(1)]!;
  if (m.group(2) == '#') semi++;
  if (m.group(2) == 'b') semi--;
  return semi + (int.parse(m.group(3)!) + 1) * 12;
}
