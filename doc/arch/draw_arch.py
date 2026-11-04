# -*- coding: utf-8 -*-
"""
HDMI_DDR3_OV5640_test overall block diagram (Pillow, 2x supersampled).
All coordinates below are 1x "design pixels"; drawing happens at S=2.
"""
import math
import os
from PIL import Image, ImageDraw, ImageFont

S = 2
W, H = 1900, 1250

CJK = r"C:\Windows\Fonts\msyh.ttc"
CJKB = r"C:\Windows\Fonts\msyhbd.ttc"
MONO = r"C:\Windows\Fonts\consola.ttf"

TEXT = "#16243A"
SUB = "#4A5B70"
LABEL = "#233246"
ARROW = "#2B394A"
CLK = "#7C6BA0"

F_MOD, E_MOD = "#EAF2FD", "#2F6FB5"
F_NEW, E_NEW = "#E5F6EA", "#2E8B57"
F_MEM, E_MEM = "#FFF3E0", "#C9832B"
F_DDR, E_DDR = "#FDE9E6", "#C0563D"
F_EXT, E_EXT = "#F0F1F3", "#5B6470"
F_GRP = "#F9FCFF"
E_GRP = "#94B4D6"

FILLS = {"mod": (F_MOD, E_MOD), "new": (F_NEW, E_NEW), "mem": (F_MEM, E_MEM),
         "ddr": (F_DDR, E_DDR), "ext": (F_EXT, E_EXT)}


def fnt(path, size):
    return ImageFont.truetype(path, max(6, int(round(size * S))))


class Canvas:
    def __init__(self):
        self.img = Image.new("RGB", (W * S, H * S), "white")
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

    def text_block(self, cx, cy, lines, sizes, colors, bolds):
        """vertically centred stack of single lines"""
        hs = [s * 1.28 for s in sizes]
        total = sum(hs)
        y = cy - total / 2
        for ln, sz, col, bd, h in zip(lines, sizes, colors, bolds, hs):
            self.text(cx, y + h / 2, ln, size=sz, color=col, bold=bd)
            y += h

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
    y = (y0 + y1) / 2 - total / 2 + (5 if tag and not sub else 0)
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


def main():
    c = Canvas()
    d = c.d

    # ---------------- title ----------------
    c.text(28, 24, "HDMI_DDR3_OV5640_test　整体框图", size=22.5, bold=True,
           anchor="lm", color="#10243B")
    c.text(28, 55, "方案 B′（1800 tile · 四帧环形缓存 · 显示帧同步）　＋　成员二接入的高阶模块 rotate_map / gamma_top",
           size=11.2, color="#41536A", anchor="lm")

    # ---------------- legend ----------------
    lx0, ly0, lx1, ly1 = 1236, 14, 1874, 82
    c.rect(lx0, ly0, lx1, ly1, "#FCFDFF", "#C9D6E4", r=6, width=1.1)
    c.text(lx0 + 8, ly0 + 12, "图例", size=9.6, bold=True, color="#33465C", anchor="lm")
    x = lx0 + 44
    for fill, edge, name in [(F_MOD, E_MOD, "现有模块"), (F_NEW, E_NEW, "★ 新增"),
                             (F_MEM, E_MEM, "片上 BRAM"), (F_DDR, E_DDR, "DDR 通路"),
                             (F_EXT, E_EXT, "片外器件")]:
        c.rect(x, ly0 + 7, x + 12, ly0 + 17, fill, edge, r=2.5, width=1.1)
        c.text(x + 16, ly0 + 12, name, size=9.0, color="#33465C", anchor="lm")
        x += 22 + c.measure(name, 9.0)
    c.text(lx0 + 8, ly0 + 31, "实线＝数据流　　虚线＝控制/握手　　模块右下角小字＝所属时钟域",
           size=8.8, color="#33465C", anchor="lm")
    c.text(lx0 + 8, ly0 + 45, "DDR 流量：写 55 + 读 ≈276 ≈ 0.33 GB/s（峰值 3.2 GB/s）；显示侧读 BRAM 不走 DDR",
           size=8.8, color="#33465C", anchor="lm")
    c.text(lx0 + 8, ly0 + 59, "调试：heart_beat_led（core_clk 心跳）、hdmi_int_led（tile 填充活动）",
           size=8.8, color="#33465C", anchor="lm")

    # ---------------- FPGA frame ----------------
    FX0, FY0, FX1, FY1 = 172, 96, 1552, 1064
    d.rounded_rectangle([FX0 * S, FY0 * S, FX1 * S, FY1 * S], radius=10 * S,
                        outline="#6C93B6", width=max(1, int(1.6 * S)))
    c.text(FX0 + 14, FY0 + 16, "FPGA　PGL50H-FBG484", size=11.2, bold=True,
           color="#2E5F86", anchor="lm")

    # ---------------- top strip ----------------
    module(c, 190, 122, 344, 198, "PLL", "50 M → pix / cfg / 25 M", tag="sys_clk")
    module(c, 384, 122, 566, 198, "ms72xx_ctl", "HDMI TX 初始化（I2C）", tag="cfg_clk")
    module(c, 606, 122, 770, 198, "power_on_delay", "上电时序 / 复位", tag="sys_clk")
    module(c, 810, 122, 1000, 198, "reg_config ×2", "OV5640 寄存器配置", tag="clk_25M")
    c.arrow([(344, 160), (384, 160)], dash=(6, 4))
    c.label(364, 148, "cfg_clk", size=8.4)

    # ---------------- sensors ----------------
    module(c, 28, 300, 152, 392, "CMOS1", "OV5640 #1", kind="ext")
    module(c, 28, 500, 152, 592, "CMOS2", "OV5640 #2", kind="ext")
    module(c, 196, 300, 330, 378, "cmos_8_16bit", "8 bit → 16 bit 拼接", tag="cmos1_pclk")
    module(c, 196, 396, 330, 454, "reg_config", "I2C 初始化", tag="clk_25M", tsize=11.2)
    module(c, 196, 500, 330, 578, "cmos_8_16bit", "8 bit → 16 bit 拼接", tag="cmos2_pclk")
    module(c, 196, 596, 330, 654, "reg_config", "I2C 初始化", tag="clk_25M", tsize=11.2)
    c.arrow([(152, 330), (196, 330)])
    c.label(172, 318, "8bit 并口", size=8.4)
    c.arrow([(152, 530), (196, 530)])
    c.label(172, 518, "8bit 并口", size=8.4)
    c.arrow([(152, 374), (174, 374), (174, 425), (196, 425)], both=True)
    c.label(168, 400, "I2C", size=8.2, anchor="rm")
    c.arrow([(152, 574), (174, 574), (174, 625), (196, 625)], both=True)
    c.label(168, 600, "I2C", size=8.2, anchor="rm")

    module(c, 366, 330, 480, 570, "视频源选择", "`define CMOS_1\nRGB565\n1280×720", tag="cmos_pclk")
    c.arrow([(330, 340), (366, 345)])
    c.arrow([(330, 540), (366, 540)])

    # ---------------- fram_buf group ----------------
    group(c, 508, 254, 826, 724, "fram_buf_fisheye　·　DDR 帧缓存与读写仲裁", "四帧环形")
    module(c, 528, 286, 806, 396, "wr_buf",
           "相机写：16→32→256 bit\n行突发 80 beat · 帧距 16 MB\n（frame_idx[1:0] 四帧环形）", kind="mem")
    module(c, 528, 414, 806, 556, "wr_rd_ctrl_top", None, tsize=11.8)
    module(c, 540, 452, 630, 508, "wr_cmd_trans", "命令 → 16 beat", tsize=9.2, ssize=8.0)
    module(c, 638, 452, 718, 508, "wr_ctrl", "AW / W 通道", tsize=9.2, ssize=8.0)
    module(c, 726, 452, 794, 508, "rd_ctrl", "AR / R 通道", tsize=9.2, ssize=8.0)
    c.text(667, 528, "命令拆分 / 读写仲裁（AXI4 256-bit 突发）", size=8.6, color=SUB)
    c.text(612, 596, "地址：{帧号[1:0], 行×640 字}", size=8.4, color=SUB)
    c.text(612, 614, "读口：(x,y) → 64×32 窗口", size=8.4, color=SUB)
    c.text(612, 636, "写 55 MB/s · 读 ≈276 MB/s", size=8.4, color="#8A6A2E")
    c.arrow([(667, 396), (667, 414)])

    c.arrow([(480, 450), (494, 450), (494, 340), (528, 340)])
    c.label(497, 412, "RGB565", size=8.4, anchor="lm")

    # ---------------- fisheye group ----------------
    group(c, 852, 254, 1330, 724, "u_fisheye　·　fisheye_video_top（畸变校正引擎）", "disp_vs 整帧同步")
    module(c, 870, 286, 996, 350, "u_scan", "tile_scan_gen\n40×45 = 1800 tile", tsize=10.8, ssize=8.6)
    module(c, 1024, 286, 1178, 350, "u_rotate ★", "rotate_map\n旋转 / 镜像 / 缩放构图", kind="new",
           tsize=10.8, ssize=8.4)
    module(c, 870, 382, 1034, 474, "u_win", "win_engine_wide + bbox_rom\n8×BRAM 乒乓 · 64×32 窗口",
           kind="mem", tsize=10.8, ssize=8.4)
    module(c, 870, 490, 1034, 580, "u_tr", "tile_reader_wide\n5 beat/行 · 32 深异步 FIFO",
           tsize=10.8, ssize=8.4)

    group(c, 1054, 376, 1318, 700, "u_core　·　fisheye_core")
    module(c, 1066, 404, 1306, 478, "u_corr",
           "corr_top：coord_lut → win_req\n→ bilinear565（L = 15）", tsize=10.8, ssize=8.4)
    module(c, 1066, 494, 1306, 556, "u_gamma ★", "gamma_top：Gamma / 色彩校正", kind="new",
           tsize=10.8, ssize=8.6)
    module(c, 1066, 572, 1306, 688, "u_band",
           "band_wr：2 桶 × 16 行 × 1280 像素\n双指针乒乓 · rd_done 释放", kind="mem",
           tsize=10.8, ssize=8.4)

    c.arrow([(996, 318), (1024, 318)])
    c.arrow([(1122, 350), (1122, 404)])
    c.label(1132, 366, "输出 u,v", size=8.2, anchor="lm")
    c.arrow([(1034, 428), (1066, 428)])
    c.arrow([(950, 490), (950, 474)])
    c.label(957, 482, "fill 8px 组", size=8.0, anchor="lm")
    c.arrow([(870, 535), (806, 535)])
    c.label(846, 512, "读窗口", size=8.2, anchor="mb")
    c.arrow([(1186, 478), (1186, 494)])
    c.arrow([(1186, 556), (1186, 572)])
    c.text(953, 660, "一轮 = 1800 tile（40×45）\n按 32×16 输出分块扫描\n\ntile 间预取下一 64×32 窗口\nband 未读完则反压停扫",
           size=8.4, color=SUB)

    # ---------------- right column ----------------
    module(c, 1360, 306, 1506, 378, "sync_vg", "720p30　1650×750", tag="pix_clk")
    module(c, 1360, 404, 1524, 502, "u_fisheye_band", "fisheye_band_reader\n16 行 band 同步读出",
           tsize=10.4, ssize=8.2)
    module(c, 1360, 532, 1524, 604, "HDMI 输出寄存器", "RGB565 → 8:8:8", tsize=10.4, ssize=8.4)
    c.arrow([(1306, 630), (1338, 630), (1338, 470), (1360, 470)])
    c.arrow([(1433, 378), (1433, 404)])
    c.label(1440, 391, "vs/hs/de", size=8.2, anchor="lm")
    c.arrow([(1442, 502), (1442, 532)])
    c.label(1450, 517, "16 bit", size=8.2, anchor="lm")
    c.arrow([(1360, 318), (1332, 318)], dash=(6, 4))

    # ---------------- DDR ----------------
    module(c, 520, 780, 840, 900, "DDR3_50H（DDR3 IP + PHY）", "AXI4 从机 · 32 bit DQ · 800 MT/s",
           kind="ddr", tsize=11.2)
    c.arrow([(760, 556), (760, 780)])
    c.label(760, 755, "AXI4：AW / W / R　256-bit ×16 beat 突发", size=8.8)

    module(c, 560, 1096, 900, 1176, "DDR3 颗粒（片外）", "MT41K256M16 ×2 · 1 GB · 32 bit", kind="ext",
           tsize=11.2)
    c.arrow([(610, 900), (610, 1096)], dash=(6, 4), both=True)
    c.arrow([(800, 900), (800, 1096)], both=True)
    c.label(812, 1000, "mem_ck / mem_a / mem_ba\nmem_dq[31:0] / mem_dqs / mem_dm", size=8.2, anchor="lm")

    # ---------------- clock / constraint panel ----------------
    bx0, by0, bx1, by1 = 196, 780, 470, 1058
    c.rect(bx0, by0, bx1, by1, "#FCFDFF", "#C3D2E2", r=6, width=1.1)
    c.text(bx0 + 13, by0 + 18, "时钟域", size=10.4, bold=True, color="#33465C", anchor="lm")
    y = by0 + 42
    for a, b in [("cmos_pclk / vin", "相机像素时钟（CMOS1 / CMOS2）"),
                 ("pix_clk  37.125 MHz", "720p30 时序 + 校正引擎"),
                 ("core_clk  ≈100 MHz", "DDR3 DFI，全部 AXI 事务"),
                 ("cfg_clk 10 / 25 MHz", "HDMI TX 初始化、CMOS 配置")]:
        c.text(bx0 + 13, y, a, size=8.6, color="#2F4A66", anchor="lm")
        c.text(bx0 + 13, y + 14, b, size=8.2, color=SUB, anchor="lm")
        y += 36
    c.text(bx0 + 13, by1 - 78, "关键约束", size=10.4, bold=True, color="#33465C", anchor="lm")
    for i, s in enumerate(["· 一轮 1800 tile，在 disp_vs 处对齐起点",
                           "· band 未读完则反压 tile 扫描（band_ready）",
                           "· 跨时钟：tile 读用异步 FIFO、命令用 toggle"]):
        c.text(bx0 + 13, by1 - 56 + i * 15, s, size=8.2, color=SUB, anchor="lm")

    # ---------------- external HDMI ----------------
    module(c, 1580, 250, 1780, 700, "HDMI_OUT", "MS7210　　720p30\nRGB888 + vs / hs / de", kind="ext",
           tsize=13)
    c.arrow([(1524, 568), (1580, 568)])
    c.label(1552, 556, "TMDS", size=8.4)
    c.arrow([(475, 198), (475, 226), (1546, 226), (1546, 270), (1580, 270)], dash=(7, 5))
    c.label(1000, 215, "I2C（HDMI TX 配置）", size=8.8)

    img = c.img.resize((W, H), Image.LANCZOS)
    out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "arch_overview.png")
    img.save(out, "PNG")
    img.resize((W * 2, H * 2), Image.LANCZOS).save(
        os.path.join(os.path.dirname(os.path.abspath(__file__)), "arch_overview@2x.png"), "PNG")
    print("saved", out, img.size)


if __name__ == "__main__":
    main()
