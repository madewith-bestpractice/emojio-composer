#!/usr/bin/env node
/*
 * Compresses a baked voice set (WAV + manifest.json from bake-voices.html) to
 * OGG Vorbis for shipping in the Flutter app, and rewrites the manifest to
 * point at the .ogg files. flutter_soloud decodes OGG Vorbis via stb_vorbis.
 *
 * Vorbis (NOT Opus) is required — stb_vorbis only handles Vorbis.
 *
 * Requires oggenc from vorbis-tools (brew install vorbis-tools) — libvorbis,
 * higher quality than ffmpeg's experimental native Vorbis encoder.
 *
 * Usage:
 *   node tools/compress-voices.js <inDir> <outDir> [quality=6]
 *   # inDir must contain manifest.json + the *.wav it references.
 *   # quality is oggenc -q (0..10); ~5-7 is a good size/quality balance here.
 */
const { execFileSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const [, , inDir, outDir, qArg] = process.argv;
if (!inDir || !outDir) {
  console.error('usage: node tools/compress-voices.js <inDir> <outDir> [quality=6]');
  process.exit(1);
}
const q = qArg || '6';

// Confirm oggenc is present, else bail with a clear message.
try {
  execFileSync('oggenc', ['--version'], { stdio: 'ignore' });
} catch (e) {
  console.error('oggenc not found — run: brew install vorbis-tools');
  process.exit(1);
}

fs.mkdirSync(outDir, { recursive: true });
const manifest = JSON.parse(fs.readFileSync(path.join(inDir, 'manifest.json'), 'utf8'));

let inBytes = 0, outBytes = 0, n = 0;
for (const voice of Object.values(manifest.voices)) {
  for (const z of voice.zones) {
    const inFile = path.join(inDir, z.file);
    const oggName = z.file.replace(/\.wav$/i, '.ogg');
    const outFile = path.join(outDir, oggName);
    // Baked samples are already mono, so no --downmix needed.
    execFileSync('oggenc', ['--quiet', '-q', q, '-o', outFile, inFile]);
    inBytes += fs.statSync(inFile).size;
    outBytes += fs.statSync(outFile).size;
    z.file = oggName;             // rewrite manifest to reference the .ogg
    n++;
  }
}

fs.writeFileSync(path.join(outDir, 'manifest.json'), JSON.stringify(manifest, null, 2));

const mb = (b) => (b / 1048576).toFixed(2);
console.log(`Compressed ${n} samples across ${Object.keys(manifest.voices).length} voices`);
console.log(`  ${mb(inBytes)} MB WAV -> ${mb(outBytes)} MB OGG  (q${q}, ${(100 * (1 - outBytes / inBytes)).toFixed(0)}% smaller)`);
console.log(`  wrote ${outDir}/manifest.json`);
