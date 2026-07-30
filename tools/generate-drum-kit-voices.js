#!/usr/bin/env node
/*
 * Deterministically generates the small Drum Kit sample set used by the
 * Flutter app, then updates app/assets/voices/manifest.json.
 */
const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');

const ROOT = path.resolve(__dirname, '..');
const VOICES_DIR = path.join(ROOT, 'app', 'assets', 'voices');
const MANIFEST_PATH = path.join(VOICES_DIR, 'manifest.json');
const SR = 44100;
const MIDIS = Array.from({ length: 21 }, (_, i) => 33 + i * 3);

const KIT = {
  kick: { volumeDb: -1, durSec: 0.55 },
  snare: { volumeDb: -13, durSec: 0.32 },
  hat: { volumeDb: -17, durSec: 0.18 },
  clap: { volumeDb: -14, durSec: 0.35 },
  tom: { volumeDb: -2, durSec: 0.55 },
  crash: { volumeDb: -18, durSec: 0.85 },
};

const EMOJI_VOICES = {
  '🥁': 'kick',
  '💥': 'snare',
  '🪇': 'hat',
  '👏': 'clap',
  '🪘': 'tom',
  '🛎️': 'crash',
};

function midiToHz(midi) {
  return 440 * Math.pow(2, (midi - 69) / 12);
}

function midiToNoteName(midi) {
  const names = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
  return names[midi % 12] + (Math.floor(midi / 12) - 1);
}

function seedFor(name, midi) {
  let h = 2166136261;
  for (const ch of `${name}:${midi}`) {
    h ^= ch.charCodeAt(0);
    h = Math.imul(h, 16777619);
  }
  return h >>> 0;
}

function prng(seed) {
  let s = seed >>> 0;
  return () => {
    s = (Math.imul(1664525, s) + 1013904223) >>> 0;
    return (s / 0xffffffff) * 2 - 1;
  };
}

function encodeWav(f32) {
  const dataSize = f32.length * 2;
  const out = Buffer.alloc(44 + dataSize);
  out.write('RIFF', 0);
  out.writeUInt32LE(36 + dataSize, 4);
  out.write('WAVE', 8);
  out.write('fmt ', 12);
  out.writeUInt32LE(16, 16);
  out.writeUInt16LE(1, 20);
  out.writeUInt16LE(1, 22);
  out.writeUInt32LE(SR, 24);
  out.writeUInt32LE(SR * 2, 28);
  out.writeUInt16LE(2, 32);
  out.writeUInt16LE(16, 34);
  out.write('data', 36);
  out.writeUInt32LE(dataSize, 40);
  for (let i = 0; i < f32.length; i++) {
    const s = Math.max(-1, Math.min(1, f32[i]));
    out.writeInt16LE(Math.round(s * 32767), 44 + i * 2);
  }
  return out;
}

function normalize(buf, gain = 0.92) {
  let peak = 0;
  for (const s of buf) peak = Math.max(peak, Math.abs(s));
  if (peak < 1e-6) return buf;
  const scale = gain / peak;
  for (let i = 0; i < buf.length; i++) buf[i] *= scale;
  return buf;
}

function synthesize(name, midi) {
  const cfg = KIT[name];
  const frames = Math.ceil(cfg.durSec * SR);
  const out = new Float32Array(frames);
  const rnd = prng(seedFor(name, midi));
  const base = midiToHz(midi);
  let phase = 0;
  let prevNoise = 0;

  for (let i = 0; i < frames; i++) {
    const t = i / SR;
    let s = 0;

    if (name === 'kick') {
      const f = 42 * Math.pow(2, (midi - 36) / 36) + 115 * Math.exp(-t * 34);
      phase += (2 * Math.PI * f) / SR;
      const body = Math.sin(phase) * Math.exp(-t * 9.5);
      const click = rnd() * Math.exp(-t * 130) * 0.28;
      s = body + click;
    } else if (name === 'tom') {
      const f = 88 * Math.pow(2, (midi - 45) / 32) + 85 * Math.exp(-t * 12);
      phase += (2 * Math.PI * f) / SR;
      s = Math.sin(phase) * Math.exp(-t * 7.2);
    } else if (name === 'snare') {
      const n = rnd();
      const crack = (n - prevNoise * 0.35) * Math.exp(-t * 18);
      prevNoise = n;
      const tone = Math.sin(2 * Math.PI * (155 * Math.pow(2, (midi - 48) / 48)) * t) * Math.exp(-t * 16);
      s = crack * 0.85 + tone * 0.25;
    } else if (name === 'hat') {
      const n = rnd();
      const hp = n - prevNoise;
      prevNoise = n;
      const metal =
        Math.sin(2 * Math.PI * (base * 5.1) * t) * 0.16 +
        Math.sin(2 * Math.PI * (base * 6.7) * t) * 0.12;
      s = (hp * 0.75 + metal) * Math.exp(-t * 48);
    } else if (name === 'clap') {
      const bursts = [0, 0.018, 0.037];
      let env = 0;
      for (const b of bursts) {
        if (t >= b) env += Math.exp(-(t - b) * 95);
      }
      const tail = t > 0.045 ? Math.exp(-(t - 0.045) * 14) * 0.28 : 0;
      const n = rnd();
      const hp = n - prevNoise * 0.55;
      prevNoise = n;
      s = hp * (env + tail);
    } else if (name === 'crash') {
      const n = rnd();
      const hp = n - prevNoise * 0.72;
      prevNoise = n;
      const shimmer =
        Math.sin(2 * Math.PI * (base * 4.8) * t) * 0.09 +
        Math.sin(2 * Math.PI * (base * 6.2) * t) * 0.08 +
        Math.sin(2 * Math.PI * (base * 7.9) * t) * 0.06;
      s = (hp * 0.72 + shimmer) * Math.exp(-t * 4.6);
    }

    out[i] = s;
  }
  return normalize(out);
}

function encodeOgg(name, midi, wavPath, oggPath) {
  const result = spawnSync('oggenc', ['-Q', '-q', '6', '-o', oggPath, wavPath], {
    stdio: 'inherit',
  });
  if (result.status !== 0) {
    throw new Error(`oggenc failed for ${name} ${midi}`);
  }
}

function main() {
  const manifest = JSON.parse(fs.readFileSync(MANIFEST_PATH, 'utf8'));
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'emojio-kit-'));

  for (const [name, cfg] of Object.entries(KIT)) {
    const zones = [];
    for (const midi of MIDIS) {
      const file = `${name}_${String(midi).padStart(3, '0')}.ogg`;
      const wav = path.join(tmp, file.replace(/\.ogg$/, '.wav'));
      const ogg = path.join(VOICES_DIR, file);
      fs.writeFileSync(wav, encodeWav(synthesize(name, midi)));
      encodeOgg(name, midi, wav, ogg);
      zones.push({
        midi,
        note: midiToNoteName(midi),
        file,
        durSec: +cfg.durSec.toFixed(3),
      });
    }
    manifest.voices[name] = { type: 'oneshot', volumeDb: cfg.volumeDb, zones };
  }

  for (const [emoji, synth] of Object.entries(EMOJI_VOICES)) {
    manifest.emojiVoices[emoji] = { synth, semi: 0, dur: '16n' };
  }

  fs.writeFileSync(MANIFEST_PATH, JSON.stringify(manifest, null, 2) + '\n');
  fs.rmSync(tmp, { recursive: true, force: true });
  console.log(`Generated ${Object.keys(KIT).length} Drum Kit voices (${MIDIS.length} zones each).`);
}

main();
