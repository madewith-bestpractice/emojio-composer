import 'dart:async';
import 'host_time.dart';

// MIDI System Real-Time / Common status bytes we emit as clock master.
const int kMidiClock = 0xF8; // 24 PPQN
const int kMidiStart = 0xFA;
const int kMidiContinue = 0xFB;
const int kMidiStop = 0xFC;
const int kMidiSongPosition = 0xF2;

/// Emits 24-PPQN MIDI clock + transport as a **master**.
///
/// Timing is the whole point, so this uses look-ahead scheduling with hardware
/// timestamps (the Web-Audio "two clocks" pattern): a coarse [wake] timer fires,
/// and for every pulse whose time falls inside the [lookaheadTicks] window we
/// call [send] with that pulse's exact future host-time. Jitter is bounded by
/// CoreMIDI's timestamped delivery, **not** by the wake timer — so timer jitter,
/// GC pauses, and channel latency don't reach the wire as long as they stay
/// under the look-ahead.
///
/// The clock is derived purely from the host clock, anchored at [start]; the
/// caller anchors audio playback at the same instant, so — same hardware clock,
/// same rate — external gear locked to this clock never drifts against the app's
/// own audio.
class MidiClockOut {
  final HostClock clock;

  /// Send a System Real-Time/Common message stamped at [timestampTicks].
  final void Function(List<int> bytes, int timestampTicks) send;

  /// Coarse wake interval. Precision comes from the per-pulse timestamp, so this
  /// only needs to be comfortably shorter than the look-ahead window.
  final Duration wake;

  /// How far ahead each pulse is stamped. Must exceed [wake] + worst-case
  /// scheduling/channel latency so no pulse is ever emitted late.
  final double lookaheadTicks;

  /// When false, [start] does not spin up the internal timer — tests drive it
  /// by advancing a fake clock and calling [pump].
  final bool autoWake;

  Timer? _timer;
  bool _running = false;
  double _periodTicks = 0; // host ticks between 24-PPQN pulses
  double _anchorTicks = 0; // host tick of pulse index 0
  int _next = 0; // next pulse index to schedule

  MidiClockOut({
    required this.clock,
    required this.send,
    this.wake = const Duration(milliseconds: 15),
    double lookaheadNanos = 100e6, // 100 ms
    this.autoWake = true,
  }) : lookaheadTicks = clock.nanosToTicks(lookaheadNanos);

  bool get isRunning => _running;

  // 24 PPQN => pulse period = 60e9 / (bpm * 24) ns = 2.5e9 / bpm ns.
  double _periodForBpm(double bpm) => clock.nanosToTicks(2.5e9 / bpm);
  double _pulseAt(int i) => _anchorTicks + i * _periodTicks;

  /// Begin as master from the downbeat: **Start**, then clocks at [bpm].
  void start(double bpm) {
    if (_running) return;
    final anchor = clock.now();
    _anchorTicks = anchor.toDouble();
    _periodTicks = _periodForBpm(bpm);
    _next = 0;
    _running = true;
    send(const [kMidiStart], anchor); // FA at the downbeat (pulse 0)
    _schedule(clock.now());
    if (autoWake) _timer = Timer.periodic(wake, (_) => _schedule(clock.now()));
  }

  /// Stop as master: **Stop** now, cease clocks.
  void stop() {
    if (!_running) return;
    _timer?.cancel();
    _timer = null;
    _running = false;
    send(const [kMidiStop], clock.now());
  }

  /// Smoothly change tempo mid-play. Re-anchors at the next *unscheduled* pulse
  /// so pulses already stamped (inside the look-ahead) aren't disturbed and none
  /// are double-sent; the new period applies from that boundary on. Phase stays
  /// continuous — no jump, no dropped/duplicated clock across the change.
  void setBpm(double bpm) {
    if (!_running) return;
    _anchorTicks = _pulseAt(_next); // boundary = first pulse not yet sent
    _next = 0;
    _periodTicks = _periodForBpm(bpm);
  }

  /// Emit a Song Position Pointer (position in MIDI beats = 16th notes). Only for
  /// explicit locates — the looping pattern emits *continuous* clock (no SPP per
  /// wrap), which is what keeps a slave from jumping at the loop boundary.
  void songPosition(int sixteenths) {
    final b = sixteenths & 0x3FFF;
    send([kMidiSongPosition, b & 0x7F, (b >> 7) & 0x7F], clock.now());
  }

  /// Run the scheduler once against [nowTicks]. Public so tests can pump it
  /// deterministically; the internal timer calls it with `clock.now()`.
  void pump() => _schedule(clock.now());

  void _schedule(int nowTicks) {
    if (!_running) return;
    // If we fell far behind (app suspended / long GC), resync rather than
    // machine-gun a burst of stale, past-timestamped clocks.
    final minTick = nowTicks - lookaheadTicks;
    if (_pulseAt(_next) < minTick) {
      _next = ((minTick - _anchorTicks) / _periodTicks).ceil();
    }
    final horizon = nowTicks + lookaheadTicks;
    while (_pulseAt(_next) < horizon) {
      send(const [kMidiClock], _pulseAt(_next).round());
      _next++;
    }
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
    _running = false;
  }
}
