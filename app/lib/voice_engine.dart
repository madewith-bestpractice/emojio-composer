import 'dart:math' as math;
import 'package:flutter_soloud/flutter_soloud.dart';
import 'manifest.dart';

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
  bool ready = false;
  int bufferSize = 1024; // lower than the 2048 default, for tighter latency

  int get sampleCount => _sources.length;
  int get activeVoices => ready ? _soloud.getActiveVoiceCount() : 0;

  Future<void> init(VoiceManifest m) async {
    manifest = m;
    if (!_soloud.isInitialized) {
      await _soloud.init(sampleRate: m.sampleRate, bufferSize: bufferSize);
    }
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

  /// Play [synth] at [targetMidi]. Returns the handle (null if unplayable).
  SoundHandle? playSynth(String synth, int targetMidi, {double velocity = 1.0}) {
    final v = manifest.voices[synth];
    if (v == null) return null;
    final z = v.nearestZone(targetMidi);
    final src = _sources[z.file];
    if (src == null) return null;

    final rate = math.pow(2, (targetMidi - z.midi) / 12).toDouble();
    final loop = v.isSustain && v.loop != null;
    final startAt = loop
        ? Duration(microseconds: (v.loop!.startFrac * z.durSec * 1e6).round())
        : Duration.zero;

    // Play paused so the pitch is set before the first sample is heard.
    final h = _soloud.play(src,
        volume: velocity.clamp(0.0, 1.0), paused: true, looping: loop, loopingStartAt: startAt);
    _soloud.setRelativePlaySpeed(h, rate);
    _soloud.setPause(h, false);
    return h;
  }

  /// Play the voice mapped to [emoji] at staff row [gridY].
  SoundHandle? playEmoji(String emoji, int gridY, {double velocity = 1.0}) {
    final ev = manifest.emojiVoices[emoji];
    if (ev == null) return null;
    final targetMidi = noteToMidi(manifest.scale[gridY]) + ev.semi;
    return playSynth(ev.synth, targetMidi, velocity: velocity);
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
