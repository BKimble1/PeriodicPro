/* Deterministic SVG -> PNG rasterisation through headless Chromium.
   No design tool, no image generation: the SVG is the source of truth and the
   raster is produced at an exact pixel size with alpha preserved. */

import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { execFileSync } from 'node:child_process';

const CANDIDATES = [
  process.env.CHROME_PATH,
  '/opt/pw-browsers/chromium-1194/chrome-linux/chrome',
  '/usr/bin/chromium',
  '/usr/bin/chromium-browser',
  '/usr/bin/google-chrome',
].filter(Boolean);

export function chromePath() {
  for (const c of CANDIDATES) if (fs.existsSync(c)) return c;
  const glob = '/opt/pw-browsers';
  if (fs.existsSync(glob)) {
    for (const d of fs.readdirSync(glob)) {
      const p = path.join(glob, d, 'chrome-linux', 'chrome');
      if (fs.existsSync(p)) return p;
    }
  }
  throw new Error('no Chromium found; set CHROME_PATH');
}

/* Headless Chromium paints roughly 88px short of the requested window height,
   so the canvas is rendered into a deliberately oversized window and cropped
   back to the exact App Store size. PAD is far larger than the shortfall. */
const PAD = 260;

/** Rasterise `svg` (a string) to `outPng` at exactly W x H, alpha preserved. */
export function rasterize(svg, outPng, W, H) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'elemora-'));
  const svgPath = path.join(dir, 'frame.svg');
  const htmlPath = path.join(dir, 'frame.html');
  fs.writeFileSync(svgPath, svg);
  fs.writeFileSync(htmlPath,
    '<!doctype html><html><head><meta charset="utf-8"><style>' +
    'html,body{margin:0;padding:0;background:transparent;overflow:hidden}' +
    'img{display:block;width:' + W + 'px;height:' + H + 'px}' +
    '</style></head><body><img src="frame.svg"></body></html>');

  fs.mkdirSync(path.dirname(outPng), { recursive: true });
  execFileSync(chromePath(), [
    '--headless', '--no-sandbox', '--disable-gpu', '--hide-scrollbars',
    '--force-device-scale-factor=1',
    '--disable-lcd-text', '--font-render-hinting=none',
    `--window-size=${W + PAD},${H + PAD}`,
    '--default-background-color=00000000',
    `--screenshot=${outPng}`,
    'file://' + htmlPath,
  ], { stdio: ['ignore', 'ignore', 'pipe'] });

  fs.rmSync(dir, { recursive: true, force: true });
  if (!fs.existsSync(outPng)) throw new Error('render produced nothing: ' + outPng);

  /* Crop the padding away and assert the exact deliverable size. */
  execFileSync('python3', ['-c',
    'import sys\n' +
    'from PIL import Image\n' +
    'f, w, h = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])\n' +
    'im = Image.open(f)\n' +
    'if im.size[0] < w or im.size[1] < h:\n' +
    '    raise SystemExit("render too small: %s vs %dx%d" % (im.size, w, h))\n' +
    'im.crop((0, 0, w, h)).save(f)\n',
    outPng, String(W), String(H)], { stdio: ['ignore', 'ignore', 'pipe'] });
  return outPng;
}
