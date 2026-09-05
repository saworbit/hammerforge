// HammerForge — PNG exports. Everything derives from dist/svg.
const { Resvg } = require('@resvg/resvg-js');
const fs = require('fs'), path = require('path');
const SRC = 'svg', OUT = 'png';
fs.mkdirSync(OUT, { recursive: true });
const INK = '#14171C', PAPER = '#F2F4F7';
const read = f => fs.readFileSync(path.join(SRC, f), 'utf8');
const ink = (s, c) => s.replace(/currentColor/g, c);
const out = [];
const png = (svg, w, name) => {
  fs.writeFileSync(path.join(OUT, name),
    new Resvg(svg, { fitTo: { mode: 'width', value: w } }).render().asPng());
  out.push(name);
};
const SIZES = [16, 20, 24, 32, 48, 64, 128, 256, 512, 1024];
const mono = read('hammerforge-mark.svg');
for (const s of SIZES) {
  png(ink(mono, INK), s, `mark-ink-${s}.png`);
  png(ink(mono, PAPER), s, `mark-paper-${s}.png`);
  png(read('hammerforge-mark-light.svg'), s, `mark-light-${s}.png`);
  png(read('hammerforge-mark-dark.svg'), s, `mark-dark-${s}.png`);
  png(read('hammerforge-mark-red.svg'), s, `mark-red-${s}.png`);
  png(read('hammerforge-mark-compact-red.svg'), s, `mark-compact-red-${s}.png`);
  png(ink(read('hammerforge-mark-compact.svg'), INK), s, `mark-compact-ink-${s}.png`);
}
for (const s of [16, 32, 48]) png(read('favicon.svg'), s, `favicon-${s}.png`);
for (const s of [16, 32, 64, 128]) png(read('icon.svg'), s, `icon-${s}.png`);
for (const s of [256, 512, 1024]) png(read('hammerforge-icon-tile.svg'), s, `icon-tile-${s}.png`);
for (const f of ['hammerforge-lockup-light', 'hammerforge-lockup-dark',
                 'hammerforge-lockup-two-tone', 'hammerforge-lockup-dark-two-tone'])
  png(read(f + '.svg'), 2000, f.replace('hammerforge-', '') + '-2000.png');
png(ink(read('hammerforge-lockup.svg'), INK), 2000, 'lockup-ink-2000.png');
png(ink(read('hammerforge-lockup.svg'), PAPER), 2000, 'lockup-paper-2000.png');
png(ink(read('hammerforge-lockup-stacked.svg'), INK), 1200, 'lockup-stacked-ink-1200.png');
png(ink(read('hammerforge-wordmark.svg'), INK), 2000, 'wordmark-ink-2000.png');
png(read('hammerforge-wordmark-two-tone.svg'), 2000, 'wordmark-two-tone-2000.png');
for (const f of ['readme-banner', 'readme-banner-light', 'social-preview'])
  png(read(f + '.svg'), 1280, f + '.png');
console.log(`${out.length} PNGs written to ${OUT}/`);
