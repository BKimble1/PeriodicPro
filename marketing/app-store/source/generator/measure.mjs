/* Real text metrics, straight from the renderer that produces the artwork.

   Headline and supporting copy are laid out by hand, so the only way to be sure
   nothing clips the margin or collides with a decoration is to ask Chromium for
   the actual glyph bounds with the embedded Inter face applied. */

import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { execFileSync } from 'node:child_process';
import { chromePath } from './render.mjs';
import { typeCSS, esc, TYPE } from './system.mjs';

/** items: [{ text, size, weight, track }] -> [{ width, height }] */
export function measure(items) {
  if (!items.length) return [];
  const texts = items.map((it, i) =>
    `<text id="t${i}" x="0" y="400" style="font-size:${it.size}px;font-weight:${it.weight};` +
    `letter-spacing:${it.track}px">${esc(it.text)}</text>`).join('\n');

  const html = `<!doctype html><html><head><meta charset="utf-8">
<style>${typeCSS()}</style></head><body style="margin:0">
<svg xmlns="http://www.w3.org/2000/svg" width="6000" height="800">${texts}</svg>
<pre id="out"></pre>
<script>
document.fonts.ready.then(function () {
  var r = [];
  for (var i = 0; i < ${items.length}; i++) {
    var b = document.getElementById('t' + i).getBBox();
    r.push({ width: b.width, height: b.height });
  }
  document.getElementById('out').textContent = 'MEASURE:' + JSON.stringify(r);
});
</script></body></html>`;

  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'elemora-m-'));
  const p = path.join(dir, 'm.html');
  fs.writeFileSync(p, html);
  const dom = execFileSync(chromePath(), [
    '--headless', '--no-sandbox', '--disable-gpu',
    '--virtual-time-budget=8000', '--dump-dom', 'file://' + p,
  ], { encoding: 'utf8', maxBuffer: 1 << 28, stdio: ['ignore', 'pipe', 'pipe'] });
  fs.rmSync(dir, { recursive: true, force: true });

  const m = dom.match(/MEASURE:(\[.*?\])<\/pre>/s);
  if (!m) throw new Error('text measurement failed (font never became ready)');
  return JSON.parse(m[1]);
}

/** Measure one frame's copy block and report how it sits in its column. */
export function measureCopy(frame, colW) {
  const hs = frame.copy?.headSize ?? TYPE.headSize;
  const ss = frame.copy?.subSize ?? TYPE.subSize;
  const items = [
    ...frame.headline.map((t) => ({
      text: t, size: hs, weight: TYPE.headWeight,
      track: TYPE.headTrack * hs / TYPE.headSize,
    })),
    ...frame.sub.map((t) => ({
      text: t, size: ss, weight: TYPE.subWeight,
      track: TYPE.subTrack * ss / TYPE.subSize,
    })),
  ];
  const w = measure(items);
  const head = w.slice(0, frame.headline.length).map((r) => r.width);
  const sub = w.slice(frame.headline.length).map((r) => r.width);
  return { head, sub, maxHead: Math.max(...head), maxSub: Math.max(...sub), colW };
}
