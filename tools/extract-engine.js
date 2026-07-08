#!/usr/bin/env node
/*
 * Extracts the audio engine VERBATIM from index.html and injects it into
 * _baker.template.html to produce a self-contained bake-voices.html.
 *
 * We slice by unique anchor strings (not line numbers) so it survives edits
 * to index.html as long as those code landmarks stay intact. Fidelity is the
 * whole point of baking, so we never retype the synth definitions.
 *
 * Run:  node tools/extract-engine.js
 */
const fs = require('fs');
const path = require('path');

const root = path.resolve(__dirname, '..');
const html = fs.readFileSync(path.join(root, 'index.html'), 'utf8');
const template = fs.readFileSync(path.join(__dirname, '_baker.template.html'), 'utf8');

// Slice [startAnchor .. endAnchor). `includeEnd` keeps the end anchor text.
function slice(name, startAnchor, endAnchor, includeEnd = false) {
  const s = html.indexOf(startAnchor);
  if (s === -1) throw new Error(`extract "${name}": start anchor not found: ${startAnchor}`);
  const e = html.indexOf(endAnchor, s + startAnchor.length);
  if (e === -1) throw new Error(`extract "${name}": end anchor not found: ${endAnchor}`);
  const end = includeEnd ? e + endAnchor.length : e;
  return html.slice(s, end).trimEnd();
}

const parts = {
  SCALE:        slice('SCALE', 'const SCALE = [', '];', true),
  CATEGORIES:   slice('CATEGORIES', 'const CATEGORIES = {',
                      'const ALL_EMOJIS = Object.values(CATEGORIES).flat();', true),
  getInstrument: slice('getInstrument', 'function getInstrument(type) {', 'async function initAudio()'),
  voicesBlock:  slice('voicesBlock', 'const VOICES = {', 'function playNote(noteObj, time) {'),
  getSoundType: slice('getSoundType', 'function getSoundType(emoji) {', '/**'),
};

const engine = [
  '/* ===== BEGIN engine — auto-extracted verbatim from index.html ===== */',
  parts.SCALE, '',
  parts.CATEGORIES, '',
  parts.getInstrument, '',
  parts.voicesBlock, '',
  parts.getSoundType,
  '/* ===== END engine ===== */',
].join('\n');

const MARKER = '/*__EMOJIO_ENGINE__*/';
if (!template.includes(MARKER)) throw new Error(`template is missing marker ${MARKER}`);
const out = template.replace(MARKER, engine);

const outPath = path.join(__dirname, 'bake-voices.html');
fs.writeFileSync(outPath, out, 'utf8');

// Sanity report
const report = Object.entries(parts).map(([k, v]) => `  ${k.padEnd(13)} ${v.length} chars`).join('\n');
console.log('Extracted:\n' + report);
console.log(`\nWrote ${path.relative(root, outPath)} (${out.length} chars)`);
for (const kw of ['function getInstrument', 'const VOICES', 'function getSoundType', 'const SCALE', 'const ALL_EMOJIS'])
  if (!out.includes(kw)) console.warn(`  WARNING: "${kw}" missing from output`);
