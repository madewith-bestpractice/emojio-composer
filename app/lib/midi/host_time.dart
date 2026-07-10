import 'dart:ffi';
import 'package:ffi/ffi.dart';

/// A monotonic host clock, abstracted so the clock-out scheduler can be driven
/// by a fake clock in tests.
abstract class HostClock {
  /// "Now" in the clock's native ticks.
  int now();

  /// Convert nanoseconds to native ticks (and back).
  double nanosToTicks(double nanos);
  double ticksToNanos(int ticks);
}

// --- Mach host time (the same base CoreMIDI packet timestamps use) ---
// `MIDIPacket.timeStamp` is in `mach_absolute_time()` units, so a future value
// makes CoreMIDI (via flutter_midi_command's timestamped send) deliver at that
// exact host time — sub-ms precision independent of when we called send().
// Ticks are NOT nanoseconds on Apple Silicon; convert with mach_timebase_info:
//   nanos = ticks * numer / denom.

final class _MachTimebaseInfo extends Struct {
  @Uint32()
  external int numer;
  @Uint32()
  external int denom;
}

typedef _MachAbsC = Uint64 Function();
typedef _MachAbsD = int Function();
typedef _TimebaseC = Int32 Function(Pointer<_MachTimebaseInfo>);
typedef _TimebaseD = int Function(Pointer<_MachTimebaseInfo>);

/// Reads `mach_absolute_time()` / `mach_timebase_info()` from libSystem via FFI
/// — no platform channel, no native project changes. iOS + macOS.
class MachHostClock implements HostClock {
  final int numer;
  final int denom;
  final _MachAbsD _abs;

  MachHostClock._(this._abs, this.numer, this.denom);

  factory MachHostClock() {
    final lib = DynamicLibrary.process();
    final abs = lib.lookupFunction<_MachAbsC, _MachAbsD>('mach_absolute_time');
    final tb = lib.lookupFunction<_TimebaseC, _TimebaseD>('mach_timebase_info');
    final info = calloc<_MachTimebaseInfo>();
    try {
      tb(info);
      final n = info.ref.numer == 0 ? 1 : info.ref.numer;
      final d = info.ref.denom == 0 ? 1 : info.ref.denom;
      return MachHostClock._(abs, n, d);
    } finally {
      calloc.free(info);
    }
  }

  @override
  int now() => _abs();

  @override
  double nanosToTicks(double nanos) => nanos * denom / numer;

  @override
  double ticksToNanos(int ticks) => ticks * numer / denom;
}
