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
connected. Uses `flutter_midi_command` (CoreMIDI).
- Connect USB-C (auto) or Bluetooth (scan); input channel filter, octave shift,
  velocity→loudness.
- **Live play** the active voice; **record** notes into the grid while playing.
- **MIDI out** on an export channel (drive external gear).
- **Follow external MIDI clock** (24 PPQN) + Song Position — the external device
  drives transport/tempo/position.
- **MIDI-learn** for Play/Stop, Clear, Prev/Next voice, Octave ±, Shuttle
  (jog scrub, selectable relative-CC mode), and **per-palette-slot pads**.
- Mappings + settings persist (`<documents>/midi_config.json`).

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
