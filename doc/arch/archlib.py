# -*- coding: utf-8 -*-
"""Shared drawing library for the block diagrams (Pillow, 2x supersampled)."""
import math
import os
from PIL import Image, ImageDraw, ImageFont

S = 2

CJK = r"C:\Windows\Fonts\msyh.ttc"
CJKB = r"C:\Windows\Fonts\msyhbd.ttc"
MONO = r"C:\Windows\Fonts\consola.ttf"

TEXT = "#16243A"
SUB = "#4A5B70"
LABEL = "#233246"
ARROW = "#2B394A"
CLK = "#7C6BA0"

F_MOD, E_MOD = "#EAF2FD", "#2F6FB5"
F_NEW, E_NEW = "#E5F6EA", "#2E8B57"     # 成员二新增
F_CFG, E_CFG = "#F3ECFB", "#7A56B0"     # 成员一新增（上位机）
F_MEM, E_MEM = "#FFF3E0", "#C9832B"
F_DDR, E_DDR = "#FDE9E6", "#C0563D"
F_EXT, E_EXT = "#F0F1F3", "#5B6470"
F_GRP = "#F9FCFF"
E_GRP = "#94B4D6"

FILLS = {"mod": (F_MOD, E_MOD), "new": (F_NEW, E_NEW), "cfg": (F_CFG, E_CFG),
         "mem": (F_MEM, E_MEM), "ddr": (F_DDR, E_DDR), "ext": (F_EXT, E_EXT)}


def fnt(path, size):
    return ImageFont.truetype(path, max(6, int(round(size * S))))


class Canvas:
    def __init__(self, w, h):
        self.W, self.H = w, h
        self.img = Image.new("RGB", (w * S, h * S), "white")
        self.d = ImageDraw.Draw(self.img)

    # ---------- low level ----------
    def rect(self, x0, y0, x1, y1, fill, edge, r=6, width=1.5):
        self.d.rounded_rectangle([x0 * S, y0 * S, x1 * S, y1 * S], radius=r * S,
                                 fill=fill, outline=edge, width=max(1, int(width * S)))

    def line(self, pts, color=ARROW, width=1.3, dash=None):
        if dash:
            for a, b in zip(pts, pts[1:]):
                self.dashed(a[0], a[1], b[0], b[1], color, dash[0], dash[1], width)
        else:
            self.d.line([(x * S, y * S) for x, y in pts], fill=color,
                        width=max(1, int(width * S)), joint="curve")

    def dashed(self, x0, y0, x1, y1, color, dash=7, gap=5, width=1.2):
        L = math.hypot(x1 - x0, y1 - y0)
        if L == 0:
            return
        ux, uy = (x1 - x0) / L, (y1 - y0) / L
        t = 0.0
        while t < L:
            t2 = min(t + dash, L)
            self.d.line([(x0 + ux * t) * S, (y0 + uy * t) * S,
                         (x0 + ux * t2) * S, (y0 + uy * t2) * S],
                        fill=color, width=max(1, int(width * S)))
            t = t2 + gap

    def dashed_rect(self, x0, y0, x1, y1, color, dash=8, gap=5, width=1.3):
        for a, b in (((x0, y0), (x1, y0)), ((x1, y0), (x1, y1)),
                     ((x1, y1), (x0, y1)), ((x0, y1), (x0, y0))):
            self.dashed(a[0], a[1], b[0], b[1], color, dash, gap, width)

    def head(self, pts, color=ARROW):
        (x0, y0), (x1, y1) = pts[-2], pts[-1]
        ang = math.atan2(y1 - y0, x1 - x0)
        L, Wd = 7.5, 3.6
        p1 = (x1 - L * math.cos(ang) + Wd * math.sin(ang),
              y1 - L * math.sin(ang) - Wd * math.cos(ang))
        p2 = (x1 - L * math.cos(ang) - Wd * math.sin(ang),
              y1 - L * math.sin(ang) + Wd * math.cos(ang))
        self.d.polygon([(x1 * S, y1 * S), (p1[0] * S, p1[1] * S), (p2[0] * S, p2[1] * S)],
                       fill=color)

    # ---------- text ----------
    def measure(self, s, size, bold=False, mono=False):
        fp = fnt(MONO if mono else (CJKB if bold else CJK), size)
        return fp.getlength(s)

    def wrap(self, s, size, maxw, bold=False):
        fp = fnt(CJKB if bold else CJK, size)
        out = []
        for seg in s.split("\n"):
            if not seg:
                out.append("")
                continue
            cur = ""
            for ch in seg:
                if fp.getlength(cur + ch) <= maxw * S or not cur:
                    cur += ch
                else:
                    out.append(cur)
                    cur = ch
            out.append(cur)
        return out

    def text(self, x, y, s, size=11, color=TEXT, bold=False, anchor="mm",
             spacing=2.4, mono=False):
        fp = fnt(MONO if mono else (CJKB if bold else CJK), size)
        self.d.multiline_text((x * S, y * S), s, font=fp, fill=color, anchor=anchor,
                              align="center", spacing=spacing * S)

    def label(self, x, y, s, size=9.2, anchor="mm", color=LABEL):
        fp = fnt(CJK, size)
        bbox = self.d.multiline_textbbox((x * S, y * S), s, font=fp, anchor=anchor,
                                         align="center", spacing=2.2 * S)
        pad = 2.2
        self.d.rounded_rectangle([bbox[0] - pad * S, bbox[1] - pad * S,
                                  bbox[2] + pad * S, bbox[3] + pad * S],
                                 radius=2 * S, fill="white")
        self.d.multiline_text((x * S, y * S), s, font=fp, fill=color, anchor=anchor,
                              align="center", spacing=2.2 * S)

    def arrow(self, pts, color=ARROW, width=1.3, dash=None, head=True, both=False):
        self.line(pts, color, width, dash)
        if head:
            self.head(pts, color)
        if both:
            self.head(pts[::-1], color)

    def save(self, path, scale2=True):
        self.img.resize((self.W, self.H), Image.LANCZOS).save(path, "PNG")
        if scale2:
            base, ext = os.path.splitext(path)
            self.img.resize((self.W * 2, self.H * 2), Image.LANCZOS).save(
                base + "@2x" + ext, "PNG")
        print("saved", path, (self.W, self.H))


def module(c, x0, y0, x1, y1, title, sub=None, kind="mod", tag=None,
           tsize=12.2, ssize=9.0, r=6):
    fill, edge = FILLS[kind]
    c.rect(x0, y0, x1, y1, fill, edge, r=r)
    maxw = (x1 - x0) - 14
    tl = c.wrap(title, tsize, maxw, bold=True)
    sl = c.wrap(sub, ssize, maxw) if sub else []
    lines, sizes, colors, bolds = [], [], [], []
    for t in tl:
        lines.append(t); sizes.append(tsize); colors.append(TEXT); bolds.append(True)
    for t in sl:
        lines.append(t); sizes.append(ssize); colors.append(SUB); bolds.append(False)
    hs = [s * 1.3 for s in sizes]
    total = sum(hs) + (2.0 if sl else 0)
    y = (y0 + y1) / 2 - total / 2
    for ln, sz, col, bd, h in zip(lines, sizes, colors, bolds, hs):
        c.text((x0 + x1) / 2, y + h / 2, ln, size=sz, color=col, bold=bd)
        y += h
    if tag:
        c.text(x1 - 7, y1 - 9.5, tag, size=8.2, color=CLK, anchor="rm")


def group(c, x0, y0, x1, y1, title, sub=None):
    c.d.rectangle([x0 * S, y0 * S, x1 * S, y1 * S], fill=F_GRP)
    c.dashed_rect(x0, y0, x1, y1, E_GRP, 8, 5, 1.3)
    c.text(x0 + 11, y0 + 14, title, size=11.2, bold=True, color="#2B5C8A", anchor="lm")
    if sub:
        c.text(x1 - 11, y0 + 14, sub, size=8.8, color="#5C7A99", anchor="rm")
