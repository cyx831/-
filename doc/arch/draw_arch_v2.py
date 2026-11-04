# -*- coding: utf-8 -*-
"""v2.0 - 简化版整体框图：加入成员一的上位机配置通路（→ rotate_map）。"""
import os
from archlib import (Canvas, module, group, S, F_MOD, E_MOD, F_NEW, E_NEW,
                     F_CFG, E_CFG, F_MEM, E_MEM, F_DDR, E_DDR, F_EXT, E_EXT, SUB)

HERE = os.path.dirname(os.path.abspath(__file__))


def legend(c, x0, y0):
    rows = [[(F_MOD, E_MOD, "现有模块"), (F_CFG, E_CFG, "◆ 成员一"), (F_NEW, E_NEW, "★ 成员二")],
            [(F_MEM, E_MEM, "片上 BRAM"), (F_DDR, E_DDR, "DDR 通路"), (F_EXT, E_EXT, "片外器件")]]
    c.rect(x0, y0, x0 + 418, y0 + 64, "#FCFDFF", "#C9D6E4", r=6, width=1.1)
    y = y0 + 13
    for row in rows:
        x = x0 + 10
        for fill, edge, name in row:
            c.rect(x, y - 5, x + 12, y + 5, fill, edge, r=2.5, width=1.1)
            c.text(x + 16, y, name, size=9.0, color="#33465C", anchor="lm")
            x += 26 + c.measure(name, 9.0)
        y += 19
    c.text(x0 + 10, y0 + 52, "实线 = 视频数据　　虚线 = 配置 / 控制",
           size=8.8, color="#33465C", anchor="lm")


def main():
    c = Canvas(1600, 880)
    d = c.d

    c.text(28, 22, "HDMI_DDR3_OV5640_test　整体框图 v2.0", size=23, bold=True,
           anchor="lm", color="#10243B")
    c.text(28, 52, "简化版：采集 → 帧缓存 → 旋转/畸变矫正 → 显示　＋　上位机参数配置通路",
           size=11.2, color="#41536A", anchor="lm")
    legend(c, 1150, 12)

    # ---------------- FPGA frame ----------------
    FX0, FY0, FX1, FY1 = 170, 88, 1420, 720
    d.rounded_rectangle([FX0 * S, FY0 * S, FX1 * S, FY1 * S], radius=10 * S,
                        outline="#6C93B6", width=max(1, int(1.6 * S)))
    c.text(FX0 + 14, FY0 + 16, "FPGA　PGL50H-FBG484", size=11.2, bold=True,
           color="#2E5F86", anchor="lm")

    # ---------------- 上位机 config path ----------------
    module(c, 26, 112, 150, 192, "上位机（PC）", "参数下发 / 调试", kind="ext", tsize=11.6, ssize=8.8)
    module(c, 190, 112, 350, 192, "上位机接口 ◆", "UART 收帧 + 参数寄存器", kind="cfg",
           tsize=11.6, ssize=8.8, tag="cfg_clk")
    c.arrow([(150, 152), (190, 152)])
    c.arrow([(350, 152), (830, 152), (830, 285)], dash=(7, 5), color=E_CFG)
    c.label(590, 140, "参数：角度 / 缩放 / 平移 / 镜像", size=9.0, color="#5B3F8A")

    # ---------------- 采集 ----------------
    module(c, 26, 262, 150, 392, "CMOS1 / CMOS2", "OV5640 ×2", kind="ext", tsize=11.6)
    module(c, 190, 262, 340, 392, "采集前端", "cmos_8_16bit ×2\n视频源选择 → RGB565", tag="cmos_pclk")
    c.arrow([(150, 320), (190, 320)])
    c.label(170, 306, "8bit 并口", size=8.4)

    # ---------------- 帧缓存 ----------------
    group(c, 370, 250, 570, 560, "帧缓存 fram_buf_fisheye", "四帧环形")
    module(c, 388, 286, 552, 446, "wr_buf + 命令仲裁",
           "相机写 → DDR\n四帧环形 · 16 MB/帧\nAXI4 256-bit 突发", kind="mem", tsize=11.4, ssize=9.0)
    c.text(470, 478, "读口：按 (x,y) 取 64×32 窗口", size=8.8, color=SUB)
    c.text(470, 500, "写 55 MB/s · 读 ≈276 MB/s", size=8.8, color="#8A6A2E")
    c.arrow([(340, 320), (388, 320)])
    c.label(364, 306, "RGB565", size=8.4)

    # ---------------- 矫正引擎 ----------------
    group(c, 600, 250, 1190, 545, "矫正引擎 fisheye_video_top")
    module(c, 615, 285, 735, 355, "tile_scan_gen", "1800 tile 扫描", tsize=10.8, ssize=8.6)
    module(c, 765, 285, 895, 355, "rotate_map ★", "旋转 / 镜像 / 缩放", kind="new",
           tsize=10.8, ssize=8.8)
    module(c, 925, 285, 1055, 355, "corr_top", "坐标 LUT + 双线性", tsize=10.8, ssize=8.6)
    module(c, 1085, 285, 1185, 355, "gamma_top ★", "Gamma / 色彩", kind="new",
           tsize=10.2, ssize=8.6)
    module(c, 925, 400, 1055, 500, "窗口缓存",
           "8×BRAM 乒乓 + 取窗\n5 beat/行 · 异步 FIFO", kind="mem",
           tsize=11.2, ssize=8.8)
    module(c, 1085, 400, 1185, 500, "band_wr", "2 桶 × 16 行\n乒乓缓存", kind="mem",
           tsize=10.6, ssize=8.6)

    c.arrow([(735, 320), (765, 320)])
    c.arrow([(895, 320), (925, 320)])
    c.label(910, 306, "u,v", size=8.2)
    c.arrow([(1055, 320), (1085, 320)])
    c.arrow([(1135, 355), (1135, 400)])
    c.arrow([(990, 400), (990, 355)])
    c.arrow([(570, 450), (925, 450)])
    c.label(628, 436, "读窗口 5 beat/行", size=8.2, anchor="lm")
    c.text(755, 520, "输出 32×16 / tile，每 16 行成一条 band", size=8.8, color=SUB)

    # ---------------- 显示 ----------------
    module(c, 1220, 285, 1350, 355, "sync_vg", "720p30 · 1650×750", tag="pix_clk",
           tsize=11.0, ssize=8.6)
    module(c, 1220, 400, 1390, 500, "band 读出 + HDMI 输出",
           "16 行/band 同步读出\nRGB565 → 8:8:8", tsize=10.8, ssize=8.8)
    c.arrow([(1185, 450), (1220, 450)])
    c.label(1203, 436, "band", size=8.0)
    c.arrow([(1285, 355), (1285, 400)])
    c.label(1292, 378, "vs/hs/de", size=8.2, anchor="lm")

    module(c, 1450, 280, 1570, 520, "HDMI_OUT", "MS7210\n720p30\nRGB888", kind="ext", tsize=12.2)
    c.arrow([(1390, 450), (1450, 450)])
    c.label(1420, 436, "TMDS", size=8.2)

    # ---------------- DDR ----------------
    module(c, 620, 600, 870, 690, "DDR3_50H", "AXI4 从机 · 32 bit · 800 MT/s", kind="ddr",
           tsize=11.6, ssize=9.0)
    c.arrow([(505, 560), (505, 645), (620, 645)])
    c.label(545, 632, "AXI4", size=8.6)
    module(c, 620, 770, 870, 838, "DDR3 颗粒（片外）", "1 GB · 32 bit", kind="ext",
           tsize=11.4, ssize=9.0)
    c.arrow([(680, 690), (680, 770)], dash=(6, 4), both=True)
    c.arrow([(810, 690), (810, 770)], both=True)

    # ---------------- clocks ----------------
    bx0, by0, bx1, by1 = 190, 560, 470, 700
    c.rect(bx0, by0, bx1, by1, "#FCFDFF", "#C3D2E2", r=6, width=1.1)
    c.text(bx0 + 12, by0 + 17, "时钟域", size=10.2, bold=True, color="#33465C", anchor="lm")
    for i, (a, b) in enumerate([("cmos_pclk", "相机像素时钟"),
                                ("pix_clk 37.125 M", "720p30 + 矫正引擎"),
                                ("core_clk ≈100 M", "DDR3 DFI / AXI")]):
        yy = by0 + 42 + i * 26
        c.text(bx0 + 12, yy, a, size=8.7, color="#2F4A66", anchor="lm")
        c.text(bx0 + 130, yy, b, size=8.4, color=SUB, anchor="lm")
    c.text(bx0 + 12, by1 - 14, "跨时钟：异步 FIFO / toggle 同步", size=8.4, color=SUB, anchor="lm")

    c.save(os.path.join(HERE, "arch_overview_v2.png"))


if __name__ == "__main__":
    main()
