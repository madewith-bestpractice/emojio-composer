import 'dart:math';

import 'package:emojio/midi/clock_out.dart';
import 'package:emojio/midi/host_time.dart';
import 'package:flutter_test/flutter_test.dart';

/// 1 tick == 1 ns, so timestamps read as nanoseconds; `t` is advanced by tests.
class FakeClock implements HostClock {
  int t = 0;
  @override
  int now() => t;
  @override
  double nanosToTicks(double nanos) => nanos;
  @override
  double ticksToNanos(int ticks) => ticks.toDouble();
}

const double _period120 = 2.5e9 / 120; // ns between 24-PPQN pulses at 120 BPM

void main() {
  late FakeClock clock;
  late List<(int status, int ts)> events;
  late MidiClockOut co;

  setUp(() {
    clock = FakeClock();
    events = [];
    co = MidiClockOut(
      clock: clock,
      send: (bytes, ts) => events.add((bytes[0], ts)),
      autoWake: false, // drive manually via pump()
    );
  });

  List<int> clockStamps() => [for (final e in events) if (e.$1 == kMidiClock) e.$2];

  test('start emits Start at the downbeat, then a look-ahead of clocks', () {
    clock.t = 1000;
    co.start(120);

    expect(events.first, (kMidiStart, 1000));
    final pulses = clockStamps();
    // pulses at 1000 + i*period while < 1000 + 100ms window => i = 0..4
    expect(pulses.length, 5);
    for (var i = 0; i < pulses.length; i++) {
      expect(pulses[i], (1000 + i * _period120).round());
    }
    co.stop();
  });

  test('no drift over a simulated 5 minutes; exact 24-PPQN cadence', () {
    clock.t = 0;
    co.start(120);
    const stepNs = 15 * 1000000; // 15 ms wake
    const totalNs = 300 * 1000000000; // 5 minutes
    for (var t = 0; t <= totalNs; t += stepNs) {
      clock.t = t;
      co.pump();
    }
    final ts = clockStamps();

    // 120 BPM = 48 clocks/sec => >= 14,400 over 5 min (plus the trailing window).
    expect(ts.length, greaterThanOrEqualTo(14400));

    // Every pulse sits exactly on anchor + i*period — no accumulated drift.
    for (var i = 0; i < ts.length; i++) {
      expect(ts[i], (i * _period120).round());
    }
    // Inter-pulse interval never deviates more than rounding (<1 ns).
    var maxDev = 0.0;
    for (var i = 1; i < ts.length; i++) {
      maxDev = max(maxDev, (ts[i] - ts[i - 1] - _period120).abs());
    }
    expect(maxDev, lessThan(1.0));
    co.stop();
  });

  test('tempo change stays phase-continuous (no gap, overlap, or duplicate)', () {
    clock.t = 0;
    co.start(120);
    clock.t = 30 * 1000000;
    co.pump();
    co.setBpm(140);
    for (var t = 45 * 1000000; t <= 400 * 1000000; t += 15 * 1000000) {
      clock.t = t;
      co.pump();
    }
    final ts = clockStamps();

    // Strictly increasing => no duplicated or backward pulses across the change.
    for (var i = 1; i < ts.length; i++) {
      expect(ts[i], greaterThan(ts[i - 1]));
    }
    // Tail cadence has locked to the new tempo.
    final newPeriod = 2.5e9 / 140;
    expect((ts.last - ts[ts.length - 2] - newPeriod).abs(), lessThan(2));
    co.stop();
  });

  test('resyncs after starvation instead of bursting stale clocks', () {
    clock.t = 0;
    co.start(120); // schedules the first ~5 pulses
    final before = clockStamps().length;

    clock.t = 5 * 1000000000; // 5 s jump (as if suspended)
    co.pump();
    final burst = clockStamps().length - before;

    // A naive scheduler would emit ~240 backlogged pulses; we resync to ~now.
    expect(burst, lessThan(20));
    // And the pulses we did send are near the new "now", not from t=0.
    expect(clockStamps().last, greaterThan(4900 * 1000000));
    co.stop();
  });

  test('stop emits Stop and halts', () {
    clock.t = 0;
    co.start(120);
    co.stop();
    expect(events.last.$1, kMidiStop);
    expect(co.isRunning, isFalse);
    final n = events.length;
    clock.t = 50 * 1000000;
    co.pump(); // no-op once stopped
    expect(events.length, n);
  });
}
