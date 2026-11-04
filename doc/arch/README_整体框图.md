# HDMI_DDR3_OV5640_test 整体框图说明

> 配套图：`arch_overview.png`（1900×1250，报告用）/ `arch_overview@2x.png`（3800×2500，打印用）
> 生成脚本：`draw_arch.py`（Pillow，改坐标即可重排；重新运行可覆盖出图）

本图按“图1 原工程示例”的画法（片外器件在框外、FPGA 虚线框内画模块、块间带箭头标注）绘制，
内容以 **当前工程（方案 B′）** 为准，并把 **成员二目录中接入的高阶模块** 以绿色 ★ 标出。

---

## 1. 层次结构（与 RTL 一一对应）

| 层级 | 模块 / 实例 | 文件 | 职责 | 时钟域 |
|---|---|---|---|---|
| 顶层 | `hdmi_ddr_ov5640_top_fisheye` | `hdmi_ddr_ov5640_top_fisheye.v` | 顶层连线：采集、帧缓存、校正、显示、DDR | 多域 |
| 时钟/配置 | `u_pll` → `pll` | `source/rtl/pll/pll.v` | 50 MHz → pix_clk 37.125 M / cfg_clk 10 M / clk_25M | — |
| | `ms72xx_ctl` | `ms72xx_ctl.v` | HDMI TX（MS7210）I2C 初始化 | cfg_clk |
| | `power_on_delay` | `power_on_delay.v` | 上电时序、摄像头复位 | sys_clk |
| | `reg_config ×2` | `reg_config.v` | OV5640 寄存器配置（I2C） | clk_25M |
| 采集 | `cmos_8_16bit ×2` | `cmos_8_16bit.v` | 8 bit 并口 → 16 bit 像素拼接 | cmos_pclk |
| | 视频源选择 | 顶层 `define CMOS_1/CMOS_2` | 二选一，转 RGB565 | pix_clk |
| 帧缓存 | `fram_buf` → `fram_buf_fisheye` | `fram_buf_fisheye.v` | DDR 帧缓存子系统（写通路 + 命令仲裁） | core_clk |
| | └ `wr_buf` | `wr_buf.v` | 相机写：16→32→256 bit，行突发 80 beat，四帧环形 | vin / core |
| | └ `wr_rd_ctrl_top` | `wr_rd_ctrl_top.v` | 读写命令拆分与仲裁（AXI4 256-bit） | core_clk |
| | 　└ `wr_cmd_trans` | `wr_cmd_trans.v` | 长命令 → 16 beat 突发 | core_clk |
| | 　└ `wr_ctrl` | `wr_ctrl.v` | AW/W 通道、B 响应 | core_clk |
| | 　└ `rd_ctrl` | `rd_ctrl.v` | AR/R 通道（16 拍后出 done） | core_clk |
| 校正引擎 | `u_fisheye` → `fisheye_video_top` | `fisheye_video_top.v` | 1800 tile 调度 + 帧同步 + band 反压 | pix_clk |
| | └ `u_scan` | `tile_scan_gen.v` | 40×45 = 1800 个 32×16 输出 tile 的 (u,v) | pix_clk |
| | └ `u_rotate ★` | `rotate_map.v` | 构图映射（旋转/镜像/缩放），成员二新增 | pix_clk |
| | └ `u_win` | `win_engine_wide.v` | 8×BRAM 乒乓窗口，64×32 源窗口，4 像素对/拍 | pix_clk |
| | 　└ `bbox_rom` | `bbox_rom_case.v` | 每个 tile 的窗口原点 ROM（case 实现） | pix_clk |
| | └ `u_tr` | `tile_reader_wide.v` | 从 DDR 取 64×32 窗口：5 beat/行、32 深异步 FIFO | pix_clk / core_clk |
| | └ `u_core` | `fisheye_core.v` | 校正 + 色彩 + band 写入 | pix_clk |
| | 　└ `u_corr` | `corr_top.v` | `coord_lut` → `win_req` → `bilinear565`，L = 15 拍 | pix_clk |
| | 　└ `u_gamma ★` | `gamma_top.v` | Gamma / 色彩校正，成员二新增 | pix_clk |
| | 　└ `u_band` | `band_wr.v` | 双指针乒乓 band 缓存：2 桶 × 16 行 × 1280 像素 | pix_clk |
| 显示 | `sync_vg` | `sync_vg.v` | 720p30 时序（1650×750 @ 37.125 M） | pix_clk |
| | `u_fisheye_band` | `fisheye_band_reader`（在 `coord_scan.v` 内） | 按 16 行 band 同步读出，rd_done 释放桶 | pix_clk |
| | HDMI 输出寄存器 | 顶层 always 块 | RGB565 → 8:8:8 + vs/hs/de | pix_clk |
| DDR | `u_DDR3_50H` | `source/rtl/DDR3_50H/` | DDR3 IP + PHY，AXI4 从机，32 bit DQ | core_clk |

## 2. 数据流

```
CMOS1/2 ──8bit──► cmos_8_16bit ──16bit──► 视频源选择 ──RGB565──► wr_buf
                                                                  │ 行突发 80 beat
                                                                  ▼
                                                        DDR3_50H ◄──AXI4──► DDR3 颗粒
                                                                  ▲
                                         读窗口 5 beat/行         │
   tile_scan_gen ─► rotate_map ─► corr_top ◄── win_engine_wide ◄── tile_reader_wide
                                      │              ▲
                                      ▼              └── fill 8 像素组
                                  gamma_top
                                      ▼
                                   band_wr ──16 行/band──► fisheye_band_reader ──► HDMI 输出
```

- **相机帧 4 帧环形**：`frame_idx[1:0]`，帧距 16 MB；校正引擎在 `disp_vs` 处锁定 `frm_use`，
  整轮 1800 tile 只读同一相机帧，避免撕裂。
- **band 反压**：band 未读完（`band_ready_*`）时调度器停在 `S_BAND`，不覆盖未读的桶。
- **跨时钟**：tile 读数据走 32 深异步 FIFO；命令/起点用 toggle 三级同步。

## 3. 关键参数与带宽

| 项 | 值 |
|---|---|
| 分辨率 / 帧率 | 1280×720 @ 30 fps（pix_clk 37.125 MHz，1650×750） |
| tile 划分 | 40×45 = 1800 个 tile，每 tile 32×16 输出、64×32 源窗口 |
| band | 16 行 × 1280 像素 = 20480 像素，2 桶 ≈ 80 KB BRAM |
| DDR 写（相机） | 55 MB/s（1.84 MB/帧） |
| DDR 读（窗口） | ≈276 MB/s（1800 × 32 行 × 5 beat × 32 B = 9.2 MB/帧） |
| DDR 合计 | ≈0.33 GB/s（IP 峰值 3.2 GB/s：256-bit @ ≈100 MHz） |
| 显示侧 | 读 BRAM（band 缓存），不走 DDR，55 MB/s |

## 4. 与成员二目录的对应关系 / 差异

- 成员二目录中的 `u_rotate`（`rotate_map.v`）与 `u_gamma`（`gamma_top.v`）**当前这份工程拷贝里没有源文件**，
  本图按“接入后”的位置画出（`tile_scan_gen → rotate_map → corr_top`，`corr_top → gamma_top → band_wr`）。
  实际合入时请确认放置点，若不同只需改 `draw_arch.py` 里的对应坐标/文字。
- `tile_rd_bridge.v` 仍在工程文件列表中，但当前 `tile_reader_wide` 直接驱动 DDR 读命令口，该 bridge 未实例化。
- `fisheye_band_reader` 的**编译版本**在 `coord_scan.v` 内；`fisheye_band_reader.v` 是早期独立版本（未被 pds 收录）。

## 5. 重新出图

```powershell
& "C:\Users\钟振洋\.dsh\dsh-runtimes\dsh-primary-runtime\dependencies\python\python.exe" draw_arch.py
```

- 画布与坐标在 `main()` 里按 1x 设计像素给出，绘制时统一 ×2 再做 LANCZOS 缩小，边缘不发虚。
- `module(..., kind="new")` 画出绿色 ★ 新增块；`group(...)` 画虚线分组框。
- 改文字后若出现溢出，`module()` 会自动按框宽换行。

---

## 6. v2.0 简化版（含成员一上位机通路）

图：`arch_overview_v2.png` / `arch_overview_v2@2x.png`　脚本：`draw_arch_v2.py`（公共绘图库 `archlib.py`）

**与 v1 的区别（按"简洁"重排）**

| 项 | v1.0 | v2.0 |
|---|---|---|
| 模块数 | 25 个盒子 + 大量注记 | 16 个盒子，只保留主通路 |
| 采集侧 | CMOS1/2、reg_config×2、cmos_8_16bit×2、视频源选择 分 7 块 | 合并为「采集前端」1 块（片外 CMOS 1 块） |
| 校正引擎 | tile_scan / rotate / win / tile_reader / corr / gamma / band 全展开 | 主链 4 块 + 窗口缓存、band_wr 各 1 块 |
| 配置通路 | 无 | **新增：上位机 → 上位机接口 → rotate_map** |
| 标注 | 时钟域逐个标 | 只留左侧时钟面板 |

**新增的上位机通路**

```
上位机（PC） ──UART──► 上位机接口 ◆（收帧 + 参数寄存器） ──参数总线──► rotate_map ★
                         角度 / 缩放 / 平移 / 镜像
```

- 图中紫色 ◆ 为**成员一新增**，绿色 ★ 为**成员二新增**，蓝色为当前工程已有模块。
- `上位机接口` 目前按 "UART 收帧 + 参数寄存器 → rotate_map 参数口" 画；若实际是 SPI/CAN/以太网，
  或参数不是直接进 `rotate_map` 而是先进一个参数寄存器组再由 `tile_scan_gen` 读取，
  改 `draw_arch_v2.py` 里对应的一个 `module(...)` 文案与一处 `arrow(...)` 即可。
- 参数总线画成**虚线**，与视频数据的实线区分：它只在切模式时变一次，不参与逐像素流水。

**出图**

```powershell
python draw_arch_v2.py   # 生成 arch_overview_v2.png 与 @2x
```
