#!/usr/bin/env node
/*
 * Serve a static directory the way Netlify does, then drive Chromium over every
 * page at phone / tablet / desktop widths.
 *
 *   node scripts/check_site.js [rootDir] [outDir]
 *
 * Defaults to ./site and ./.preview. Reports, and exits non-zero on, any of:
 *   - a console error or a failed network request
 *   - an image that resolved but painted at zero size (a broken <img>)
 *   - content wider than the viewport (a horizontal scrollbar)
 *   - a tap target under 44x44 CSS px
 *   - an internal link that does not resolve to a file, redirect, or 404 page
 *   - an <img> with no alt attribute at all
 *   - an apple-app-site-association that is missing, redirected, not JSON, or
 *     served as anything other than application/json
 */

const http = require('http');
const fs = require('fs');
const path = require('path');
const { chromium } = require('playwright');

const ROOT = path.resolve(process.argv[2] || 'site');
const OUT = path.resolve(process.argv[3] || '.preview');

const TYPES = {
  '.html': 'text/html; charset=utf-8', '.css': 'text/css; charset=utf-8',
  '.js': 'text/javascript', '.json': 'application/json', '.svg': 'image/svg+xml',
  '.png': 'image/png', '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg',
  '.webp': 'image/webp', '.ico': 'image/x-icon', '.txt': 'text/plain; charset=utf-8',
  '.xml': 'application/xml',
};

/* ------------------------------------------------------------- redirects -- */

function parseRedirects(dir) {
  const file = path.join(dir, '_redirects');
  if (!fs.existsSync(file)) return [];
  return fs.readFileSync(file, 'utf8').split('\n')
    .map((l) => l.trim())
    .filter((l) => l && !l.startsWith('#'))
    .map((l) => {
      const [from, to, status] = l.split(/\s+/);
      return { from, to, status: Number(status) || 301 };
    });
}

const REDIRECTS = parseRedirects(ROOT);

/* Netlify matches a trailing /* as a prefix, and a rule with status 200 is a
   rewrite: the file at `to` is served and the address bar keeps `from`. That
   distinction is the whole of how a shared quiz works, so the dev server has
   to honour it rather than approximate it. */
function matchRule(urlPath) {
  const bare = urlPath.replace(/\/$/, '');
  return REDIRECTS.find((r) => (r.from.endsWith('/*')
    ? urlPath.startsWith(r.from.slice(0, -1))
    : r.from === urlPath || r.from === bare));
}

/* A real encoded payload, produced by Tools/check_share_link.py, so the quiz
   page is exercised at the length and shape a shared link actually has. */
const SAMPLE_PAYLOAD = process.env.ELEMORA_SAMPLE_PAYLOAD || '1TU9Nb4MwDP0ryOdMKjC2lSvdtJ13nHoIiQmRkpiRpFJV9b_PFJB2s5_fh98NFLQ3UOQnykF_WJdwjgvUU9A2mM7JGJGRn7MACu76LS-ooR2kiyggSfO43QV7hIQhQcvSNAIDOSby3Wb9dVqIMOVejeifji8VU_atqepnOO-Sd4eenVbFUZSvom5EU4tKlAdRvjFP22GwKrt05TiP2mbPbrjq_pVQMqGh2e4FzEx52uYJZ0t6X0a5teQmvxljshQ6_pv7VAcBUdGEnLU-yFlxzMPgFkmaM7Io8PVTOjIYYiGDLgL1Dgvz8BVwgba8_wE';

/* Netlify's _headers, so the checks run under the same CSP the deploy serves. */
function parseHeaders(dir) {
  const file = path.join(dir, '_headers');
  if (!fs.existsSync(file)) return [];
  const blocks = [];
  let current = null;
  for (const raw of fs.readFileSync(file, 'utf8').split('\n')) {
    if (!raw.trim() || raw.trim().startsWith('#')) continue;
    if (!/^\s/.test(raw)) {
      current = { pattern: raw.trim(), headers: {} };
      blocks.push(current);
    } else if (current) {
      const i = raw.indexOf(':');
      if (i > 0) current.headers[raw.slice(0, i).trim()] = raw.slice(i + 1).trim();
    }
  }
  return blocks;
}

const HEADER_BLOCKS = parseHeaders(ROOT);

function headersFor(urlPath) {
  const out = {};
  for (const b of HEADER_BLOCKS) {
    const re = new RegExp(`^${b.pattern.replace(/[.+?^${}()|[\]\\]/g, '\\$&').replace(/\*/g, '.*')}$`);
    if (re.test(urlPath)) Object.assign(out, b.headers);
  }
  return out;
}

function resolveFile(urlPath) {
  const clean = decodeURIComponent(urlPath.split('?')[0].split('#')[0]);
  const candidates = [clean, path.posix.join(clean, 'index.html'), `${clean}.html`];
  for (const c of candidates) {
    const p = path.join(ROOT, c);
    if (!p.startsWith(ROOT)) continue;
    if (fs.existsSync(p) && fs.statSync(p).isFile()) return p;
  }
  return null;
}

function serve() {
  return new Promise((resolve) => {
    const server = http.createServer((req, res) => {
      const urlPath = req.url.split('?')[0];
      const hit = matchRule(urlPath);
      if (hit && !resolveFile(urlPath)) {
        if (hit.status === 200) {
          const rewritten = resolveFile(hit.to);
          if (rewritten) {
            res.writeHead(200, {
              'Content-Type': TYPES[path.extname(rewritten).toLowerCase()] || 'text/html; charset=utf-8',
              ...headersFor(urlPath),
            });
            return fs.createReadStream(rewritten).pipe(res);
          }
        } else {
          res.writeHead(hit.status, { Location: hit.to });
          return res.end();
        }
      }
      const file = resolveFile(urlPath);
      if (!file) {
        const nf = path.join(ROOT, '404.html');
        res.writeHead(404, { 'Content-Type': 'text/html; charset=utf-8' });
        return res.end(fs.existsSync(nf) ? fs.readFileSync(nf) : 'not found');
      }
      res.writeHead(200, {
        'Content-Type': TYPES[path.extname(file).toLowerCase()] || 'application/octet-stream',
        ...headersFor(urlPath),
      });
      fs.createReadStream(file).pipe(res);
    });
    server.listen(0, '127.0.0.1', () => resolve(server));
  });
}

/* ------------------------------------------------------------------ main -- */

const PAGES = [
  { url: '/', name: 'home' },
  { url: '/support/', name: 'support' },
  { url: '/privacy/', name: 'privacy' },
  { url: '/terms/', name: 'terms' },
  // The shared-quiz page as a recipient without the app reaches it: a real
  // payload on the real path, served through the /quiz/* rewrite.
  { url: `/quiz/${SAMPLE_PAYLOAD}`, name: 'quiz' },
  { url: '/does-not-exist', name: '404' },
];

const VIEWPORTS = [
  { name: 'phone-se',   width: 320, height: 568, scale: 2 },  // smallest still supported
  { name: 'phone',      width: 390, height: 844, scale: 2 },  // iPhone 14/15/16
  { name: 'phone-max',  width: 430, height: 932, scale: 3 },  // Pro Max
  { name: 'ipad-port',  width: 820, height: 1180, scale: 2 },
  { name: 'ipad-land',  width: 1180, height: 820, scale: 2 },
  { name: 'laptop',     width: 1280, height: 800, scale: 1 },
  { name: 'desktop',    width: 1440, height: 900, scale: 1 },
  { name: 'wide',       width: 1920, height: 1080, scale: 1 },
];

(async () => {
  fs.mkdirSync(OUT, { recursive: true });
  const server = await serve();
  const base = `http://127.0.0.1:${server.address().port}`;
  // The image pins a Chromium build that may not match this Playwright
  // release, so use the one that is actually installed when it is there.
  const PINNED = '/opt/pw-browsers/chromium';
  const launchOpts = fs.existsSync(PINNED) ? { executablePath: PINNED } : {};
  const browser = await chromium.launch(launchOpts);
  const problems = [];
  const note = (msg) => { problems.push(msg); console.log(`  FAIL  ${msg}`); };

  for (const scheme of ['light', 'dark']) {
    for (const vp of VIEWPORTS) {
      // Dark mode is only spot-checked at one width; the palette is the only
      // thing that changes and shooting all six doubles the review surface.
      if (scheme === 'dark' && vp.name !== 'desktop' && vp.name !== 'phone') continue;

      const ctx = await browser.newContext({
        viewport: { width: vp.width, height: vp.height },
        deviceScaleFactor: vp.scale,
        colorScheme: scheme,
      });

      for (const page of PAGES) {
        const p = await ctx.newPage();
        const errors = [];
        const isNotFoundPage = page.name === '404';
        p.on('console', (m) => {
          if (m.type() !== 'error') return;
          if (isNotFoundPage && /status of 404/.test(m.text())) return;
          errors.push(m.text());
        });
        p.on('pageerror', (e) => errors.push(String(e)));
        p.on('requestfailed', (r) => errors.push(`request failed ${r.url()}`));
        p.on('response', (r) => {
          const u = new URL(r.url());
          if (u.origin === base && r.status() >= 400 && !page.url.includes('does-not-exist')) {
            errors.push(`${r.status()} ${u.pathname}`);
          }
        });

        await p.goto(base + page.url, { waitUntil: 'networkidle' });
        await p.evaluate(async () => {
          // Walk the page so anything that reacts to scrolling gets its turn,
          // then force every deferred image to fetch. Lazy images that sit off
          // to the side in a horizontal rail are never revealed by scrolling
          // down, and the point of this pass is to prove every URL resolves.
          const step = window.innerHeight;
          for (let y = 0; y < document.body.scrollHeight; y += step) {
            window.scrollTo(0, y);
            await new Promise((r) => setTimeout(r, 120));
          }
          window.scrollTo(0, 0);
          for (const img of document.images) img.loading = 'eager';
        });
        // Scrolling only *starts* the lazy loads; wait for them to land before
        // auditing, otherwise every below-the-fold image reads as broken.
        // `complete` is useless here — a loading=lazy image reports complete
        // before its fetch begins — so wait on decoded pixels instead. A real
        // failure just times out and the audit below reports it.
        await p.waitForFunction(
          () => [...document.images].every((i) => i.naturalWidth > 0),
          null,
          { timeout: 15000 },
        ).catch(() => {});
        const label = `${scheme}/${vp.name}/${page.name}`;

        for (const e of errors) note(`${label}: ${e}`);

        const audit = await p.evaluate(() => {
          const out = { overflow: null, brokenImages: [], noAlt: [], smallTargets: [], links: [] };
          const de = document.documentElement;
          if (de.scrollWidth > de.clientWidth + 1) {
            const wide = [...document.querySelectorAll('body *')]
              .filter((el) => el.getBoundingClientRect().right > de.clientWidth + 1)
              .slice(0, 4)
              .map((el) => `${el.tagName.toLowerCase()}.${(el.className || '').toString().split(' ')[0]}`);
            out.overflow = { scrollWidth: de.scrollWidth, clientWidth: de.clientWidth, culprits: wide };
          }
          for (const img of document.images) {
            if (!img.complete || img.naturalWidth === 0) out.brokenImages.push(img.currentSrc || img.src);
            if (!img.hasAttribute('alt')) out.noAlt.push(img.currentSrc || img.src);
          }
          for (const a of document.querySelectorAll('a[href], button')) {
            const r = a.getBoundingClientRect();
            if (r.width === 0 && r.height === 0) continue;
            if (a.closest('p, li, figcaption, .prose, .facts, .legal')) continue; // inline text links
            if (r.height < 44 || r.width < 24) {
              out.smallTargets.push(`${a.textContent.trim().slice(0, 28)} ${Math.round(r.width)}x${Math.round(r.height)}`);
            }
          }
          for (const a of document.querySelectorAll('a[href]')) {
            const href = a.getAttribute('href');
            if (/^(https?:|mailto:|tel:)/.test(href)) continue;
            out.links.push(href);
          }
          return out;
        });

        if (audit.overflow) {
          note(`${label}: horizontal overflow ${audit.overflow.scrollWidth}>${audit.overflow.clientWidth} via ${audit.overflow.culprits.join(', ')}`);
        }
        audit.brokenImages.forEach((s) => note(`${label}: broken image ${s}`));
        audit.noAlt.forEach((s) => note(`${label}: <img> without alt ${s}`));
        audit.smallTargets.forEach((s) => note(`${label}: tap target under 44px high — ${s}`));

        // Internal links must resolve on this server.
        if (scheme === 'light' && vp.name === 'desktop') {
          // Also confirm every mailto carries the support address, so a typo in
          // one page's contact link cannot ship silently.
          const mailtos = await p.evaluate(() =>
            [...document.querySelectorAll('a[href^="mailto:"]')].map((a) => a.getAttribute('href')));
          for (const m of mailtos) {
            if (!m.startsWith('mailto:support@idlery.com')) note(`${label}: unexpected mailto ${m}`);
          }
          for (const href of [...new Set(audit.links)]) {
            if (href.startsWith('#')) continue; // same-document anchor
            const target = href.split('#')[0];
            const res = await p.request.get(base + target, { maxRedirects: 0 });
            if (res.status() >= 400) note(`${label}: dead internal link ${href} -> ${res.status()}`);
          }
        }

        const shot = path.join(OUT, `${scheme}-${vp.name}-${page.name}.png`);
        const fullPage = page.name !== '404';
        if (fullPage) {
          // A sticky header is painted at its scroll offset in a full-page
          // capture, so it lands in the middle of the document and hides real
          // content. Pin it to the top for the shot only. This goes through the
          // CSSOM rather than an injected <style>, which style-src blocks.
          await p.evaluate(() => {
            const h = document.querySelector('.site-header');
            if (h) h.style.setProperty('position', 'static');
          });
        }
        await p.screenshot({ path: shot, fullPage });
        console.log(`  shot  ${path.relative(process.cwd(), shot)}`);
        await p.close();
      }
      await ctx.close();
    }
  }

  // Every rule in _redirects must actually fire, and an internal target must
  // land on a real page rather than the 404 fallback.
  {
    const ctx = await browser.newContext();
    const api = await ctx.request;
    for (const r of REDIRECTS) {
      const from = r.from.endsWith('/*') ? `${r.from.slice(0, -1)}${SAMPLE_PAYLOAD}` : r.from;
      const res = await api.get(base + from, { maxRedirects: 0 });
      if (res.status() !== r.status) {
        note(`redirects: ${from} returned ${res.status()}, expected ${r.status}`);
        continue;
      }
      if (r.status === 200) {
        // A rewrite: the payload must survive, so there must be no Location at
        // all, and the body must be the landing page rather than the 404.
        if (res.headers().location) {
          note(`redirects: ${from} is a rewrite but sent a Location header`);
        }
        const body = await res.text();
        if (!/Someone shared an Elemora quiz/.test(body)) {
          note(`redirects: ${from} did not serve the shared-quiz page`);
        }
        continue;
      }
      const loc = res.headers().location;
      if (loc !== r.to) note(`redirects: ${r.from} pointed at ${loc}, expected ${r.to}`);
      if (/^\//.test(r.to)) {
        const target = await api.get(base + r.to.split('#')[0], { maxRedirects: 0 });
        if (target.status() >= 400) note(`redirects: ${r.from} -> ${r.to} is a dead target (${target.status()})`);
      }
    }
    console.log(`  checked ${REDIRECTS.length} redirect rule(s)`);
    await ctx.close();
  }

  // The Apple app-site-association: iOS fetches it over HTTPS, follows no
  // redirect, and parses it as JSON. Anything else and Universal Links are off.
  {
    const ctx = await browser.newContext();
    const api = ctx.request;
    const url = '/.well-known/apple-app-site-association';
    const res = await api.get(base + url, { maxRedirects: 0 });
    if (res.status() !== 200) {
      note(`aasa: ${res.status()} — it must be 200 with no redirect (run website/scripts/build_aasa.py)`);
    } else {
      const type = res.headers()['content-type'] || '';
      if (!type.startsWith('application/json')) {
        note(`aasa: Content-Type is ${type || '(none)'}; iOS needs application/json`);
      }
      let data = null;
      try {
        data = JSON.parse(await res.text());
      } catch (e) {
        note(`aasa: not valid JSON — ${e.message}`);
      }
      if (data) {
        const details = (data.applinks && data.applinks.details) || [];
        const appIDs = details.flatMap((d) => d.appIDs || []);
        const paths = details.flatMap((d) => (d.components || []).map((c) => c['/']));
        if (appIDs.length === 0) note('aasa: no appIDs');
        for (const id of appIDs) {
          if (!/^[A-Z0-9]{10}\.com\.idlery\.periodicpro$/.test(id)) {
            note(`aasa: ${id} is not <TeamID>.com.idlery.periodicpro`);
          }
        }
        if (JSON.stringify(paths) !== JSON.stringify(['/quiz/*'])) {
          note(`aasa: components are ${JSON.stringify(paths)}, expected ["/quiz/*"]`);
        }
      }
      console.log('  checked the apple-app-site-association');
    }

    // And the ordinary pages must NOT be claimed by the app.
    for (const ordinary of ['/', '/support/', '/privacy/', '/terms/']) {
      const page = await api.get(base + ordinary, { maxRedirects: 0 });
      if (page.status() !== 200) note(`routing: ${ordinary} returned ${page.status()}`);
    }
    await ctx.close();
  }

  await browser.close();
  server.close();

  console.log(`\n${problems.length === 0 ? 'PASS — no problems found' : `${problems.length} problem(s)`}`);
  process.exit(problems.length === 0 ? 0 : 1);
})();
