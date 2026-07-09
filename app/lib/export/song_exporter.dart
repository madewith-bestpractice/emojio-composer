import 'dart:math' as math;
import 'dart:typed_data';
import '../staff_painter.dart' show Note;
import '../voice_engine.dart';

/// A rendered stereo mix, interleaved L,R,L,R… in -1..1.
class RenderedAudio {
  final Float32List stereo;
  final int sampleRate;
  final int frames; // per channel
  const RenderedAudio(this.stereo, this.sampleRate, this.frames);
  double get durationSec => frames / sampleRate;
}

class _Evt {
  final Float32List pcm;
  final double rate; // varispeed ratio
  final int onsetFrame;
  final double pan; // -1..1
  final double gain; // velocity
  _Evt(this.pcm, this.rate, this.onsetFrame, this.pan, this.gain);
}

/// Offline (faster-than-realtime) render of the sequence to stereo PCM, mirroring
/// live playback: nearest-zone + varispeed pitch, per-emoji pan, velocity, swing.
class SongExporter {
  final VoiceEngine engine;
  SongExporter(this.engine);

  Future<RenderedAudio> renderAudio({
    required List<Note> notes,
    required double bpm,
    required double swing,
    required int cols,
    int loops = 4,
    int sampleRate = 44100,
  }) async {
    final m = engine.manifest;
    final stepMs = 60000 / bpm / 4;
    double onsetMs(int k) => (k + (k.isOdd ? swing : 0.0)) * stepMs;

    final events = <_Evt>[];
    var maxEnd = 0;
    for (var loop = 0; loop < loops; loop++) {
      for (final n in notes) {
        final ev = m.emojiVoices[n.emoji];
        if (ev == null) continue;
        final voice = m.voices[ev.synth];
        if (voice == null) continue;
        final targetMidi = engine.midiForRow(n.gridY) + ev.semi;
        final zone = voice.nearestZone(targetMidi);
        final pcm = await engine.decodePcm(zone.file);
        final rate = math.pow(2, (targetMidi - zone.midi) / 12).toDouble();
        final onsetFrame = (onsetMs(loop * cols + n.gridX) / 1000 * sampleRate).round();
        maxEnd = math.max(maxEnd, onsetFrame + (pcm.length / rate).floor());
        events.add(_Evt(pcm, rate, onsetFrame, engine.panForEmoji(n.emoji), n.velocity.clamp(0.0, 1.0)));
      }
    }

    final barEnd = (onsetMs(cols * loops) / 1000 * sampleRate).round();
    final frames = math.max(barEnd, maxEnd) + sampleRate ~/ 4; // small tail for decay
    final mix = Float32List(frames * 2);

    for (final e in events) {
      // Equal-power pan (constant loudness across the field).
      final theta = (e.pan.clamp(-1.0, 1.0) + 1) * (math.pi / 4);
      final lg = math.cos(theta) * e.gain * 0.7; // 0.7 headroom vs summing
      final rg = math.sin(theta) * e.gain * 0.7;
      final count = (e.pcm.length / e.rate).floor();
      for (var j = 0; j < count; j++) {
        final srcPos = j * e.rate;
        final i0 = srcPos.floor();
        if (i0 + 1 >= e.pcm.length) break;
        final frac = srcPos - i0;
        final s = e.pcm[i0] * (1 - frac) + e.pcm[i0 + 1] * frac; // linear interp
        final of = e.onsetFrame + j;
        if (of >= frames) break;
        mix[of * 2] += s * lg;
        mix[of * 2 + 1] += s * rg;
      }
    }

    // Peak-safe: clip anything the headroom didn't catch.
    for (var i = 0; i < mix.length; i++) {
      if (mix[i] > 1) {
        mix[i] = 1;
      } else if (mix[i] < -1) {
        mix[i] = -1;
      }
    }
    return RenderedAudio(mix, sampleRate, frames);
  }
}
