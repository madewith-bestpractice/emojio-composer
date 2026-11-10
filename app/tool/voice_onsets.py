#!/usr/bin/env python3
"""Record each baked voice sample's leading silence as `startSec` in
assets/voices/manifest.json, so playback and export skip it and every voice
sounds right on its step.

Why: the Tone.js-baked voices (tools/bake-voices.html) carry ~24-34 ms of
pre-roll before the sound starts, while the drum kit
(tools/generate-drum-kit-voices.js) starts at 0. Played as-is, the kit landed
~27 ms ahead of everything else, and every voice sat a little behind the beat.

Run after any re-bake (needs ffmpeg):  python3 tool/voice_onsets.py
"""

import array
import json
import pathlib
import subprocess

VOICES = pathlib.Path(__file__).resolve().parent.parent / "assets" / "voices"
THRESHOLD = 0.001  # -60 dBFS: the first sample that isn't silence
SAFETY_SEC = 0.001  # keep 1 ms before it so no attack is clipped


def onset_sec(path: pathlib.Path, sample_rate: int) -> float:
    raw = subprocess.run(
        ["ffmpeg", "-v", "quiet", "-i", str(path), "-f", "f32le", "-ac", "1",
         "-ar", str(sample_rate), "-"],
        check=True, capture_output=True,
    ).stdout
    pcm = array.array("f")
    pcm.frombytes(raw)
    first = next((i for i, x in enumerate(pcm) if abs(x) > THRESHOLD), 0)
    return max(0.0, first / sample_rate - SAFETY_SEC)


def main() -> None:
    path = VOICES / "manifest.json"
    manifest = json.loads(path.read_text())
    rate = manifest["sampleRate"]
    for name, voice in manifest["voices"].items():
        starts = []
        for zone in voice["zones"]:
            start = round(onset_sec(VOICES / zone["file"], rate), 5)
            if start > 0:
                zone["startSec"] = start
            else:
                zone.pop("startSec", None)
            starts.append(start * 1000)
        print(f"{name:12s} {min(starts):5.1f}-{max(starts):5.1f} ms")
    path.write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n")


if __name__ == "__main__":
    main()
