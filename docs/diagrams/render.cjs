#!/usr/bin/env node
// Render the README figures.
//
// Usage: NODE_PATH="$(npm root -g)" node docs/diagrams/render.cjs [--png-dir <dir>]
//
// Reads diagrams.html next to this file and writes docs/img/<name>-light.webp and
// docs/img/<name>-dark.webp for every <svg data-name="name">, at twice the drawn size.
// Needs the `playwright` package with Chromium, `cwebp`, and network access for the
// web fonts. --png-dir also keeps the PNG renders, for looking at them.
const { chromium } = require('playwright');
const { execFileSync } = require('node:child_process');
const fs = require('node:fs');
const path = require('node:path');

const args = process.argv.slice(2);
const pngDir = args.includes('--png-dir') ? path.resolve(args[args.indexOf('--png-dir') + 1]) : null;
const src = path.join(__dirname, 'diagrams.html');
const out = path.join(__dirname, '..', 'img');
const fonts = ['600 34px Fraunces', '500 14px "DM Sans"', '500 11px "DM Mono"'];

(async () => {
  fs.mkdirSync(out, { recursive: true });
  if (pngDir) fs.mkdirSync(pngDir, { recursive: true });
  const browser = await chromium.launch();
  const page = await browser.newPage({ deviceScaleFactor: 2, viewport: { width: 1280, height: 900 } });
  await page.goto('file://' + src);
  await page.evaluate(async (list) => { await Promise.all(list.map((f) => document.fonts.load(f))); await document.fonts.ready; }, fonts);
  const missing = await page.evaluate((list) => list.filter((f) => !document.fonts.check(f)), fonts);
  if (missing.length) { console.error('fonts not loaded: ' + missing.join(', ')); process.exit(1); }
  for (const theme of ['light', 'dark']) {
    await page.evaluate((t) => { document.documentElement.dataset.theme = t; }, theme);
    for (const el of await page.$$('svg[data-name]')) {
      const name = await el.getAttribute('data-name');
      const png = path.join(pngDir || out, `${name}-${theme}.png`);
      const webp = path.join(out, `${name}-${theme}.webp`);
      await el.screenshot({ path: png, omitBackground: true });
      execFileSync('cwebp', ['-quiet', '-lossless', '-z', '9', png, '-o', webp]);
      if (!pngDir) fs.unlinkSync(png);
      console.log(`${name}-${theme}.webp ${(fs.statSync(webp).size / 1024).toFixed(0)} KB`);
    }
  }
  await browser.close();
})().catch((e) => { console.error(e); process.exit(1); });
