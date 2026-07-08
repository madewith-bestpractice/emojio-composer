# Emojio (Flutter / iPad) — Phase-0 harness

Native port of the Emojio Paint Composer web app (`../index.html`). This is the
**Phase-0 audio harness**: enough of the app to prove the native audio path on a
real device — baked Tone.js samples played through `flutter_soloud` with a
16-step sequencer — before building out the full app.

## What works here
- Loads baked voice multisamples + `manifest.json` from `assets/voices/`.
- `flutter_soloud` plays each note by picking the nearest pitch zone and
  varispeed-shifting to the exact pitch (`setRelativePlaySpeed`).
- Tap the staff to place/remove emoji notes (audible preview on placement).
- 16-step transport (Play/Stop), tempo 60–180 BPM, live playhead.
- Diagnostics bar: engine status, sample count, buffer size, active voices, step.

Bundled sample set = the **spike** voices only (`drum, bell, angel, dog, fire`).
Drop a full bake into `assets/voices/` to replace it (see below).

## Run
Requires **CMake** — `flutter_soloud` compiles a native C++ engine:
```
brew install cmake        # one-time
cd app
flutter run -d macos      # desktop, to hear it quickly
# or on a connected iPad:
flutter run -d <ipad-id>
```

## Refreshing / expanding the voice set
1. Open `../tools/bake-voices.html`, click **Bake ALL voices**, download the zip.
2. Unzip its contents into `app/assets/voices/` (must include `manifest.json`).
3. `flutter run` again.

## Known Phase-0 simplifications (v1 TODO)
- **Dry playback** — the app's shared reverb/compressor aren't applied yet
  (a global mix-bus filter in `flutter_soloud`).
- **Emoji glyphs** use the system emoji font via `TextPainter`; v1 will bundle
  Twemoji (SVG) to match the web app exactly.
- **Sustain loops** use the manifest's placeholder loop fractions; held-note
  loop points need hand-tuning.
- Bundled assets are uncompressed WAV (fine for the spike); v1 should ship
  compressed (OGG/AAC) and decode on load.
- Measure real audio latency on-device at `bufferSize` 512/1024/2048.

## Layout
- `lib/manifest.dart` — parses `manifest.json`; note-name→MIDI helper.
- `lib/voice_engine.dart` — `flutter_soloud` wrapper (load, pitch, play, release).
- `lib/staff_painter.dart` — `CustomPainter` port of the web canvas renderer + hit-testing.
- `lib/main.dart` — the harness UI + transport.
