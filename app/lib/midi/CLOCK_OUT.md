# MIDI clock OUT (master)

Emojio can drive external gear/DAWs as a **MIDI clock master**: it emits 24-PPQN
clock (`0xF8`) plus `Start` (`0xFA`) / `Stop` (`0xFC`) so a synth, drum machine,
or DAW locks its tempo and transport to Emojio's playhead. Toggle it in the
🎹 sheet → **OUTPUT → "Send MIDI clock (master)"**. Mutually exclusive with
**SYNC → "Follow external MIDI clock"** (you can't be master and follower).

## Why the timing holds up

A clock master lives or dies on jitter, so this does **not** emit clock from the
render Ticker or a plain timer. It uses **look-ahead scheduling with hardware
timestamps** (the Web-Audio "two clocks" pattern):

- A coarse ~15 ms `Timer` (`MidiClockOut`, `clock_out.dart`) wakes and, for every
  pulse whose time falls inside a ~100 ms window, calls `sendData(..., timestamp:)`
  with that pulse's **exact future host-time**.
- `flutter_midi_command` puts that value in `MIDIPacket.timeStamp`, so **CoreMIDI
  delivers each pulse at the stamped host time** — sub-millisecond precision that
  is independent of when we made the call. Timer jitter, GC pauses, and channel
  latency don't reach the wire as long as they stay under the look-ahead.
- Host time is `mach_absolute_time()` read via `dart:ffi` (`host_time.dart`) — no
  platform channel, no native project code. Ticks → ns via `mach_timebase_info`.
- Pulse times are `anchor + i·period` (not accumulated), so there is **no drift**.
- Tempo changes **re-anchor at the next unscheduled pulse**, so phase stays
  continuous and nothing already committed to CoreMIDI is disturbed or doubled.
- After a long stall (suspend/GC) it **resyncs** rather than machine-gunning a
  burst of stale, past-timestamped clocks.

## One timeline, no drift vs. audio

Audio steps run off Dart's `Stopwatch` from `_playStartMs`; clock pulses run off
`mach_absolute_time` from an anchor captured at the **same play-press instant**
(`_syncClockOut` in `main.dart`, right after `_playStartMs` is set). Same hardware
clock, same rate → external gear locked to the clock never drifts against the
app's own audio. Swing stays a note-timing feel; the emitted clock grid is
straight (24 PPQN can't carry swing), which is correct.

The looping 16-step pattern emits **continuous** clock across the loop boundary
(the pulse index free-runs; no `Start`/SPP per wrap), so a slave never jumps.
`songPosition()` exists for explicit locates only.

## Caveats

- **USB / CoreMIDI is the precise path.** BLE-MIDI goes through a different
  transport with its own ~ms latency + timestamping; treat BLE clock-out as
  best-effort, not sample-accurate.
- **Background:** `UIBackgroundModes: audio` (Info.plist) keeps the audio session
  and the scheduler alive when backgrounded.

## Verifying on device (do this — don't assume)

The unit tests (`test/clock_out_test.dart`) prove the *scheduling* is exact and
drift-free, but real wire jitter and external lock need hardware:

1. **Loopback jitter.** Route the app's MIDI OUT back to its own IN (a USB host
   loopback, or a virtual endpoint). Turn on "Send MIDI clock" and press Play.
   The 🎹 sheet's activity monitor shows a live **`⏱±N µs`** readout — the
   received clock interval's deviation from its mean, measured from hardware
   packet timestamps. Expect low tens of µs or better over USB.
2. **Real-gear lock + drift.** Set Ableton/Logic (or hardware) to external MIDI
   clock. Confirm it locks, holds a rock-steady BPM with no audible wobble, and
   shows **no drift vs. Emojio's own audio over ≥ 5 minutes**.
3. Confirm `Start`/`Stop` behave, the master ↔ follow-clock toggle is clean, and
   nothing regressed (follower sync, notes-out, MIDI-learn, shuttle).
