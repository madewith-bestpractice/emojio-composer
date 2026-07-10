# Emojio (Flutter / iPad)

Native iPad port of the Emojio Paint Composer web app (`../index.html`) — a
16-step emoji sequencer where each emoji is a synth voice. Audio is the app's
original Tone.js voices, baked to samples and played natively via
`flutter_soloud`.

> Status: builds and passes `flutter analyze` + `flutter build macos`. Runtime
> behavior (audio, MIDI, IAP) is confirmed on a `flutter run` — see below.

## Features
- **Full voice set** — all 51 Tone.js voices baked to OGG (`assets/voices/`),
  played by nearest-zone + varispeed pitch. Every emoji makes sound.
- **Sequencer** — 16 steps, tempo 60–180, tap-to-toggle + drag-to-paint, live
  playhead, toy aesthetic (Press Start 2P, chunky borders/shadows).
- **Emoji picker** — full categorized picker; palette add/select (cap 10).
- **Local song library** — save/name/duplicate/delete songs on-device
  (`<documents>/songs/*.json`), with mini staff previews. No account.
- **MIDI (iPad, USB-first)** — see below.
- **Monetization** — 3-day Keychain trial → single non-consumable "unlock
  forever" IAP (StoreKit 2). Paywall + trial banner.

## MIDI
Opens via the `🎹 MIDI` header button, which appears only when a controller is
connected. Uses `flutter_midi_command` (CoreMIDI). All of it lives in
`lib/midi/` (`midi_manager.dart` = engine, `midi_panel.dart` = the settings sheet).

**Devices.** Recognizes and labels **USB** (serial), **Bluetooth** (BLE),
**Network** (RTP-MIDI), and **Virtual** ports. USB is auto-discovered; a **Scan
Bluetooth** button starts BLE scanning. Multiple devices can be connected at
once; the list auto-refreshes when the MIDI setup changes.

**Input.**
- **Channel filter** — Omni or lock to 1–16.
- **Octave shift** — ±3 transpose on incoming notes.
- **Live play** — hear the active voice's synth as you play (panned to match the
  selected emoji).
- **Use velocity** — note velocity → loudness (else fixed).
- **Record-arm** — while the transport runs, played notes are step-recorded into
  the grid, snapped to the nearest scale row (respecting each voice's semitone
  offset).

**Output.** **Send notes out** on a selectable export channel (1–16). Each placed
note transmits note-on/off during playback (pitch = row's MIDI note + the voice's
semitone offset). Notes only — it does **not** transmit clock/transport (it's a
clock follower, not a master).

**External clock sync.** **Follow external MIDI clock** hands the transport to the
external device:
- **24 PPQN** clock (`F8`) drives the step sequencer (6 pulses = one 16th step)
  and shows a smoothed detected-BPM readout.
- **Start** (`FA`) / **Continue** (`FB`) / **Stop** (`FC`) transport.
- **Song Position Pointer** (`F2`, 14-bit) jumps to the right 16th-note step.

The byte-stream parser tolerates interleaved real-time bytes and skips SysEx,
MTC quarter-frame, song-select, program-change, aftertouch, and pitch-bend.

**MIDI-learn.** Bind a note **or** CC (on a specific channel) to each control:
- **Actions** — Play/Stop, Clear, Prev/Next voice, Octave ±, and **Shuttle**
  (relative-CC jog scrub; encoding selectable: 2's-comp / signed-bit / offset).
  Ship pre-mapped to assignable CCs kept off the note range (CC114–119, jog=CC60);
  all relearnable.
- **Palette pads** — map drum pads/keys to palette slots 1–N. It learns the
  *slot*, so whatever emoji sits there is what plays.

**Also:** a live activity monitor (last message + velocity meter), and everything
(settings, action mappings, palette bindings) persists to
`<documents>/midi_config.json`. Incoming-message dispatch priority:
learn-capture → shuttle → mapped action → palette pad → musical note.

## Run
Requires **CMake** (flutter_soloud builds a native C++ engine):
```
brew install cmake            # one-time
cd app
flutter run -d macos          # hear it on desktop
flutter run -d <ipad-id>      # on iPad; plug in a USB-MIDI controller to test MIDI
```

## Setup still needed for release
- Create the non-consumable IAP `com.madewithbestpractice.emojio.unlock_forever`
  in App Store Connect (paywall shows a note until it exists).
- On-device verification: audio + OGG decode, MIDI with a USB controller,
  latency at `bufferSize` 512/1024/2048 (`lib/voice_engine.dart`).
- App icon / launch screen; Twemoji glyph parity (harness uses system emoji).

## Refreshing / re-baking voices
1. Open `../tools/bake-voices.html` in a **foreground** browser tab (background
   tabs throttle Web Audio rendering to a crawl).
2. Click **Bake ALL voices** (~2 min) → downloads `emojio-samples-all.zip`.
3. `../tools/bundle-full-voices.sh` — compresses to OGG and swaps into
   `assets/voices/`.

## Layout
- `lib/manifest.dart` — parses the baked-voice manifest; note→MIDI helper.
- `lib/voice_engine.dart` — flutter_soloud wrapper (load, pitch, play, release).
- `lib/staff_painter.dart` — CustomPainter staff renderer + hit-testing.
- `lib/song.dart`, `lib/song_library.dart` — local song storage.
- `lib/picker.dart`, `lib/categories.dart`, `lib/theme.dart` — palette/picker + toy theme.
- `lib/midi/` — MIDI manager + panel.
- `lib/monetization/` — trial, purchases, paywall.
- `lib/main.dart` — app shell + transport + wiring.

## Known simplifications (tech debt)
- Rebuilds via an always-on 60fps Ticker (fine for now; gate to playing/animating later).
- Dry audio (the shared reverb/compressor aren't re-applied as a global mix bus yet).
- Sustain-loop points are manifest placeholders; hand-tune for held notes.
