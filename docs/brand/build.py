# -*- coding: utf-8 -*-
"""
HammerForge identity — single source of truth.

The mark is the boolean: a box brush, and the subtract brush that shaped it.
The cutter overhangs the corner so you read two objects rather than one shape
with a window, and a 3-unit kerf keeps them apart even in one colour.

Red is not decoration — HammerForge's own viewport outlines subtract brushes in
red. The wordmark is drawn from rectangles and diagonals, not set in a typeface,
so the whole set is original geometry and clean to ship under MIT.

Shape model: a *shape* is a list of rings. One ring is a plain solid; two rings
are an outer and its counter, drawn even-odd. Every shape gets its own <path>,
so overlapping parts of a glyph union instead of cancelling.
"""
import math, os

D = "svg"
os.makedirs(D, exist_ok=True)

INK   = "#14171C"   # the solid — cooled stock
PAPER = "#F2F4F7"   # its inverse, for dark grounds
RED   = "#E03131"   # the subtract brush. 4.51:1 on white, 3.54:1 on Godot dark
SLATE = "#79818F"   # annotation and rules

# ── the mark ───────────────────────────────────────────────────────────
# The solid stays the dominant mass (~2.4x the cutter's area): it is the thing
# you made, the cutter is what shaped it.
#
# Two weights, because the kerf is the first thing to die. At 16px the master's
# 3u kerf rasterises to 0.46px and the two solids fuse — the boolean vanishes
# exactly where the mark is used most. The compact weight pulls the overhang in
# and thickens kerf and ring so both clear a pixel.
def geometry(sx1, sy0, cx0, cy0, cx1, cy1, ring, kerf):
    solid = [(0, sy0), (cx0 - kerf, sy0), (cx0 - kerf, cy1 + kerf),
             (sx1, cy1 + kerf), (sx1, 100), (0, 100)]
    cut_o = [(cx0, cy0), (cx1, cy0), (cx1, cy1), (cx0, cy1)]
    cut_i = [(cx0 + ring, cy0 + ring), (cx1 - ring, cy0 + ring),
             (cx1 - ring, cy1 - ring), (cx0 + ring, cy1 - ring)]
    return solid, cut_o, cut_i


MASTER  = dict(sx1=78, sy0=20, cx0=48, cy0=-4, cx1=100, cy1=48, ring=14, kerf=3)
COMPACT = dict(sx1=74, sy0=16, cx0=44, cy0=4,  cx1=94,  cy1=54, ring=16, kerf=7)

SOLID, CUT_O, CUT_I = geometry(**MASTER)
C_SOLID, C_CUT_O, C_CUT_I = geometry(**COMPACT)


def rect(x0, y0, x1, y1):
    return [(x0, y0), (x1, y0), (x1, y1), (x0, y1)]


def dstr(r):
    return (f"M{r[0][0]:.3f} {r[0][1]:.3f}"
            + "".join(f"L{x:.3f} {y:.3f}" for x, y in r[1:]) + "Z")


def bbox(groups):
    pts = [p for _, shapes in groups for sh in shapes for r in sh for p in r]
    xs, ys = [p[0] for p in pts], [p[1] for p in pts]
    return min(xs), min(ys), max(xs), max(ys)


def place(groups, s, ox, oy, seam=0.35):
    body = ""
    for fill, shapes in groups:
        for sh in shapes:
            d = "".join(dstr([(x * s + ox, y * s + oy) for x, y in r]) for r in sh)
            body += (f'<path d="{d}" fill="{fill}" fill-rule="evenodd" '
                     f'stroke="{fill}" stroke-width="{seam}" '
                     f'stroke-linejoin="round"/>')
    return body


def fit(groups, vw, vh, pad):
    x0, y0, x1, y1 = bbox(groups)
    s = min((vw - 2 * pad) / (x1 - x0), (vh - 2 * pad) / (y1 - y0))
    return place(groups, s, (vw - (x1 - x0) * s) / 2 - x0 * s,
                 (vh - (y1 - y0) * s) / 2 - y0 * s), s


def svg(vw, vh, body, bg=None):
    b = f'<rect width="{vw}" height="{vh}" fill="{bg}"/>' if bg else ""
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {vw} {vh}" '
            f'width="{vw}" height="{vh}">{b}{body}</svg>')


def write(name, s):
    open(f"{D}/{name}", "w", encoding="utf-8").write(s)
    return name


def mark(mass, cutter, compact=False):
    s, o, i = (C_SOLID, C_CUT_O, C_CUT_I) if compact else (SOLID, CUT_O, CUT_I)
    return [(mass, [[s]]), (cutter, [[o, i]])]


MONO, LIGHT = mark("currentColor", "currentColor"), mark(INK, RED)
DARK, ALLRED = mark(PAPER, RED), mark(RED, RED)
C_MONO, C_ALLRED = mark("currentColor", "currentColor", True), mark(RED, RED, True)

for n, g in [("hammerforge-mark.svg", MONO),
             ("hammerforge-mark-light.svg", LIGHT),
             ("hammerforge-mark-dark.svg", DARK),
             ("hammerforge-mark-red.svg", ALLRED),
             ("hammerforge-mark-compact.svg", C_MONO),
             ("hammerforge-mark-compact-red.svg", C_ALLRED)]:
    write(n, svg(100, 100, fit(g, 100, 100, 7)[0]))

write("favicon.svg", svg(64, 64, fit(C_ALLRED, 64, 64, 3)[0]))
write("icon.svg", svg(128, 128, fit(C_ALLRED, 128, 128, 7)[0]))
# The two icons Godot actually shows derive from the same source, so neither can
# drift from the brand set: the project icon (project.godot -> config/icon), and
# the addon icon plugin.gd hands to add_custom_type() for LevelRoot and
# DraftEntity, which the Scene tree draws at ~16px.
open("../../icon.svg", "w", encoding="utf-8").write(
    svg(128, 128, fit(C_ALLRED, 128, 128, 7)[0]))
open("../../addons/hammerforge/icon.svg", "w", encoding="utf-8").write(
    svg(64, 64, fit(C_ALLRED, 64, 64, 4)[0]))

write("hammerforge-icon-tile.svg",
      svg(512, 512, '<rect width="512" height="512" rx="114" fill="#14171C"/>'
          + fit(DARK, 512, 512, 108)[0]))

# ── the wordmark ───────────────────────────────────────────────────────
CAP, WW, TRACK = 11.0, 2.3, 1.35
S = lambda *rings: list(rings)          # one shape from its rings


def g_H(w=9.4):
    return [[rect(0, 0, WW, CAP)], [rect(w - WW, 0, w, CAP)],
            [rect(WW, (CAP - WW) / 2, w - WW, (CAP + WW) / 2)]], w


def g_A(w=9.8):
    lx, cy = 3.0, 7.0
    wh = WW / math.cos(math.atan(lx / CAP))
    xl = lambda y: lx + wh - lx * (y / CAP)
    xr = lambda y: w - lx - wh + lx * (y / CAP)
    return [[[(0, CAP), (wh, CAP), (lx + wh, 0), (lx, 0)]],
            [[(w, CAP), (w - wh, CAP), (w - lx - wh, 0), (w - lx, 0)]],
            [rect(lx, 0, w - lx, WW)],
            [[(xl(cy), cy), (xr(cy), cy), (xr(cy + WW), cy + WW),
              (xl(cy + WW), cy + WW)]]], w


def g_M(w=12.0):
    vy = 6.9
    wh = WW / math.cos(math.atan((w / 2 - WW) / vy))
    return [[rect(0, 0, WW, CAP)], [rect(w - WW, 0, w, CAP)],
            [[(WW, 0), (WW + wh, 0), (w / 2 + wh / 2, vy), (w / 2 - wh / 2, vy)]],
            [[(w - WW, 0), (w - WW - wh, 0), (w / 2 - wh / 2, vy),
              (w / 2 + wh / 2, vy)]]], w


def g_E(w=8.2):
    return [[rect(0, 0, WW, CAP)], [rect(0, 0, w, WW)],
            [rect(0, (CAP - WW) / 2, w - 1.1, (CAP + WW) / 2)],
            [rect(0, CAP - WW, w, CAP)]], w


def g_F(w=8.0):
    return [[rect(0, 0, WW, CAP)], [rect(0, 0, w, WW)],
            [rect(0, (CAP - WW) / 2, w - 1.1, (CAP + WW) / 2)]], w


def g_R(w=9.4):
    br, bh = w - 0.4, 7.0
    lx = WW + (br - WW) * 0.42
    wh = WW / math.cos(math.atan((w - lx - WW) / (CAP - bh + WW)))
    return [[rect(0, 0, WW, CAP)], [rect(WW, 0, br, WW)],
            [rect(br - WW, 0, br, bh)], [rect(WW, bh - WW, br, bh)],
            [[(lx, bh - WW), (lx + wh, bh - WW), (w, CAP), (w - wh, CAP)]]], w


def g_O(w=9.8):
    return [S(rect(0, 0, w, CAP), rect(WW, WW, w - WW, CAP - WW))], w


def g_G(w=10.0):
    ax, m0, m1 = w - WW, CAP / 2 - WW / 2, CAP / 2 + WW / 2
    sx = w * 0.44
    return [S([(0, 0), (w, 0), (w, WW), (ax, WW), (ax, m0), (w, m0), (w, CAP),
               (0, CAP)],
              [(WW, WW), (ax, WW), (ax, m0), (sx, m0), (sx, m1), (ax, m1),
               (ax, CAP - WW), (WW, CAP - WW)])], w


GLYPH = {"H": g_H, "A": g_A, "M": g_M, "E": g_E,
         "R": g_R, "F": g_F, "O": g_O, "G": g_G}
TXT = "HAMMERFORGE"


def word(colours, dx=0.0):
    out, x = [], dx
    for i, ch in enumerate(TXT):
        shapes, w = GLYPH[ch]()
        out.append((colours.get(i, INK),
                    [[[(px + x, py) for px, py in r] for r in sh]
                     for sh in shapes]))
        x += w + TRACK
    return out, x - TRACK - dx


MONO_W = {i: "currentColor" for i in range(len(TXT))}
TWO = {i: RED for i in range(6, 11)}
PAPER_W = {i: PAPER for i in range(len(TXT))}
DARK_W = {i: (PAPER if i < 6 else RED) for i in range(len(TXT))}

wm_mono, WMW = word(MONO_W)
write("hammerforge-wordmark.svg", svg(1000, 130, fit(wm_mono, 1000, 130, 10)[0]))
write("hammerforge-wordmark-two-tone.svg",
      svg(1000, 130, fit(word(TWO)[0], 1000, 130, 10)[0]))

# ── lockups ───────────────────────────────────────────────────────────
MARK_H = 104.0                        # the mark's own height, in its own units


def scale_group(groups, s, dx=0.0, dy=0.0):
    return [(f, [[[(x * s + dx, y * s + dy) for x, y in r] for r in sh]
                 for sh in shapes]) for f, shapes in groups]


def lockup(mk, colours, ratio=1.92):
    s = (CAP * ratio) / MARK_H
    sc = scale_group(mk, s)
    ys = [p[1] for _, shs in sc for sh in shs for r in sh for p in r]
    sc = scale_group(mk, s, dy=(CAP - (max(ys) - min(ys))) / 2 - min(ys))
    lead = max(p[0] for _, shs in sc for sh in shs for r in sh for p in r) \
        + TRACK * 2.6
    return sc + word(colours, lead)[0]


for n, mk, col in [("hammerforge-lockup.svg", MONO, MONO_W),
                   ("hammerforge-lockup-light.svg", LIGHT, {}),
                   ("hammerforge-lockup-dark.svg", DARK, PAPER_W),
                   ("hammerforge-lockup-two-tone.svg", LIGHT, TWO),
                   ("hammerforge-lockup-dark-two-tone.svg", DARK, DARK_W)]:
    write(n, svg(1200, 200, fit(lockup(mk, col), 1200, 200, 14)[0]))

sc = 3.2
stacked = scale_group(MONO, sc, dx=(WMW - 100 * sc) / 2) + \
    scale_group(wm_mono, 1.0, dy=MARK_H * sc + 14)
write("hammerforge-lockup-stacked.svg", svg(900, 520, fit(stacked, 900, 520, 22)[0]))

# ── banner + social ───────────────────────────────────────────────────
FONT = "ui-monospace,SFMono-Regular,Menlo,Consolas,monospace"


def grid(w, h, step, colour):
    ln = "".join(f'<path d="M{x} 0V{h}"/>' for x in range(step, w, step))
    ln += "".join(f'<path d="M0 {y}H{w}"/>' for y in range(step, h, step))
    return f'<g stroke="{colour}" stroke-width="1" opacity="0.05">{ln}</g>'


def banner(w, h, bg, mk, col, tag, tagc, sub=None, frac=0.72, gc=None):
    lk = lockup(mk, col)
    x0, y0, x1, y1 = bbox(lk)
    s = (w * frac) / (x1 - x0)
    lh, ts = (y1 - y0) * s, s * 1.55
    ss, l1, l2 = s * 1.14, s * 2.3, s * 1.9
    block = lh + l1 + ts + ((l2 + ss) if sub else 0)
    top = (h - block) / 2
    tx = (w - (x1 - x0) * s) / 2
    ty = top + lh + l1 + ts * 0.8
    body = (grid(w, h, 40, gc) if gc else "")
    body += place(lk, s, tx - x0 * s, top - y0 * s)
    body += (f'<text x="{tx:.1f}" y="{ty:.1f}" fill="{tagc}" font-family="{FONT}" '
             f'font-size="{ts:.1f}" letter-spacing="{ts*0.2:.2f}">{tag}</text>')
    if sub:
        body += (f'<text x="{tx:.1f}" y="{ty + l2 + ss:.1f}" fill="{tagc}" '
                 f'opacity=".62" font-family="{FONT}" font-size="{ss:.1f}" '
                 f'letter-spacing="{ss*0.34:.2f}">{sub}</text>')
    return svg(w, h, body, bg)


TAG = "BRUSH-BASED LEVEL EDITOR FOR GODOT 4.7+"
SUB = "DRAW · CARVE · PAINT · BAKE"

write("readme-banner.svg", banner(1280, 300, INK, DARK, DARK_W, TAG, PAPER, gc=PAPER))
write("readme-banner-light.svg",
      banner(1280, 300, "#FFFFFF", LIGHT, TWO, TAG, INK, gc=INK))
write("social-preview.svg",
      banner(1280, 640, INK, DARK, DARK_W, TAG, PAPER, sub=SUB, frac=0.76, gc=PAPER))

print(f"{len(os.listdir(D))} SVGs written to {D}/")
