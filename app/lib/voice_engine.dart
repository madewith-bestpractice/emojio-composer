import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_soloud/flutter_soloud.dart';
import 'manifest.dart';

/// Musical scale the staff rows map to. `free` = the baked staff pitches
/// (diatonic white notes); the pentatonics guarantee every note is consonant.
enum ScaleMode { free, majorPentatonic, minorPentatonic }

extension ScaleModeLabel on ScaleMode {
  String get label => switch (this) {
        ScaleMode.free => 'Free',
        ScaleMode.majorPentatonic => 'Major 5',
        ScaleMode.minorPentatonic => 'Minor 5',
      };
}

/// Plays the baked multisamples through flutter_soloud, pitching each note to
/// the exact target with varispeed (`setRelativePlaySpeed`) — the same
/// technique validated in the browser baker's A/B audition.
///
/// Deliberately dry for now: the app's shared reverb/compressor are a v1
/// mix-bus concern (global filter), not needed to prove latency/timing.
class VoiceEngine {
  final SoLoud _soloud = SoLoud.instance;
  late VoiceManifest manifest;

  final Map<String, AudioSource> _sources = {}; // file -> loaded sample
  final Map<String, Float32List> _pcmCache = {}; // file -> decoded mono PCM (for export)
  bool ready = false;
  // SoLoud's default. A smaller buffer (was 1024) underruns on CPU spikes —
  // rebuilds, stamp-in animations, dialogs — and that's the crackle/grinding.
  int bufferSize = 2048;

  ScaleMode scaleMode = ScaleMode.free;
  List<int>? _scaleRows; // row -> MIDI when a scale is active (null = free)

  void setScaleMode(ScaleMode m) {
    scaleMode = m;
    _scaleRows = m == ScaleMode.free ? null : _buildScaleRows(m);
  }

  // Ascending scale pitches (low..high), then reversed so row 0 (top of the
  // staff) is the highest — matching the free staff's high-to-low layout.
  List<int> _buildScaleRows(ScaleMode m) {
    final pcs = m == ScaleMode.majorPentatonic ? const [0, 2, 4, 7, 9] : const [0, 3, 5, 7, 10];
    final start = m == ScaleMode.majorPentatonic ? 48 : 45; // C3 / A2
    final asc = <int>[];
    for (var i = 0; asc.length < manifest.scale.length; i++) {
      asc.add(start + pcs[i % pcs.length] + 12 * (i ~/ pcs.length));
    }
    return asc.reversed.toList();
  }

  /// Base MIDI for a staff row (before the emoji's semitone offset).
  int midiForRow(int gridY) {
    final s = _scaleRows;
    if (s != null && gridY >= 0 && gridY < s.length) return s[gridY];
    return noteToMidi(manifest.scale[gridY]);
  }

  int get sampleCount => _sources.length;
  int get activeVoices => ready ? _soloud.getActiveVoiceCount() : 0;

  Future<void> init(VoiceManifest m) async {
    manifest = m;
    if (!_soloud.isInitialized) {
      await _soloud.init(sampleRate: m.sampleRate, bufferSize: bufferSize);
      // Polyphony headroom above SoLoud's default 16 — dense columns plus the
      // tails of prior steps can stack past 16. Safe now that the buffer is 2048.
      _soloud.setMaxActiveVoiceCount(32);
    }
    _installMasterBus();
    // Preload every zone sample once (dedup by filename).
    for (final v in m.voices.values) {
      for (final z in v.zones) {
        if (!_sources.containsKey(z.file)) {
          _sources[z.file] = await _soloud.loadAsset('$kVoicesDir/${z.file}');
        }
      }
    }
    ready = true;
  }

  /// Decode a bundled voice file to mono PCM (44.1k) for offline export.
  /// Uses soloud's own miniaudio/stb_vorbis decoder: requesting >= the frame
  /// count with average:false yields contiguous, full-fidelity samples.
  Future<Float32List> decodePcm(String file) async {
    final cached = _pcmCache[file];
    if (cached != null) return cached;
    final bytes = (await rootBundle.load('$kVoicesDir/$file')).buffer.asUint8List();
    final src = _sources[file];
    final frames = src != null
        ? (_soloud.getLength(src).inMicroseconds / 1e6 * manifest.sampleRate).ceil() + 64
        : bytes.length;
    final pcm = await _soloud.readSamplesFromMem(bytes, frames, average: false);
    _pcmCache[file] = pcm;
    return pcm;
  }

  /// Master bus: headroom + shared "glue" so dense/stacked columns don't clip.
  /// The baked voices are dry, so this reintroduces the web app's master chain
  /// (compressor + limiter + a touch of shared reverb) on the global output.
  void _installMasterBus() {
    _soloud.setGlobalVolume(0.7); // headroom for summed voices
    final f = _soloud.filters;
    f.limiterFilter.activate(); // brick-wall against clipping
    f.compressorFilter.activate(); // gentle glue
    f.freeverbFilter.activate();
    f.freeverbFilter.wet.value = 0.18; // subtle shared space
    f.freeverbFilter.roomSize.value = 0.55;
  }

  // Hand-pinned stereo positions for characterful emoji (−1 left … +1 right).
  static const Map<String, double> _panOverrides = {
    '🐔': 0.55, '🐓': 0.55, '🐣': 0.5, // chickens to the right
    '💩': -0.55, // poop to the left
  };

  /// Stable stereo position for an emoji: the same emoji always sits in the
  /// same spot in the field. Overrides win; everything else is a stable hash
  /// spread across ±0.6 (never hard-panned, so nothing is lost on one side).
  double panForEmoji(String emoji) {
    final o = _panOverrides[emoji];
    if (o != null) return o;
    var h = 0;
    for (final c in emoji.runes) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    return ((h % 2000) / 1000.0 - 1.0) * 0.6; // -0.6 .. 0.6
  }

  /// Play [synth] at [targetMidi], optionally panned. Returns the handle.
  SoundHandle? playSynth(String synth, int targetMidi, {double velocity = 1.0, double pan = 0}) {
    final v = manifest.voices[synth];
    if (v == null) return null;
    final z = v.nearestZone(targetMidi);
    final src = _sources[z.file];
    if (src == null) return null;

    final rate = math.pow(2, (targetMidi - z.midi) / 12).toDouble();
    // One-shot: the baked sample already contains the full envelope. (Looping
    // sustained voices here made them play FOREVER, since taps/steps have no
    // note-off — that's what made the app impossible to silence.)
    final h = _soloud.play(src, volume: velocity.clamp(0.0, 1.0), paused: true);
    _soloud.setRelativePlaySpeed(h, rate);
    _soloud.setPan(h, pan.clamp(-1.0, 1.0)); // positioned before the first sample is heard
    _soloud.setPause(h, false);
    return h;
  }

  /// Play the voice mapped to [emoji] at staff row [gridY], panned to the
  /// emoji's fixed stereo position.
  SoundHandle? playEmoji(String emoji, int gridY, {double velocity = 1.0}) {
    final ev = manifest.emojiVoices[emoji];
    if (ev == null) return null;
    final targetMidi = midiForRow(gridY) + ev.semi;
    return playSynth(ev.synth, targetMidi, velocity: velocity, pan: panForEmoji(emoji));
  }

  /// Stop a (looping) voice with a short fade so held pads release cleanly.
  void release(SoundHandle h) {
    _soloud.fadeVolume(h, 0, const Duration(milliseconds: 90));
    _soloud.scheduleStop(h, const Duration(milliseconds: 110));
  }

  Future<void> dispose() async {
    if (_soloud.isInitialized) await _soloud.disposeAllSources();
    _sources.clear();
    ready = false;
  }
}
