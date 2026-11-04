`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// fisheye_core (高阶版：corr_top + gamma_top + band_wr)
//////////////////////////////////////////////////////////////////////////////////
module fisheye_core (
    input  wire        clk,
    input  wire        rstn,
    
    input  wire        frame_end_pulse, // 来自顶层 tile_scan_gen
    input  wire        mode_changed,    // 【新增】来自顶层的角度切换脉冲
    input  wire        de_in,
    input  wire [15:0] u,               // 扩宽为 16-bit Q12.4
    input  wire [15:0] v,               // 扩宽为 16-bit Q12.4
    input  wire        valid_aff,       // 来自 rotate_map 的越界标识
    input  wire [11:0] u_disp,          // 显示坐标(未旋转)
    input  wire [11:0] v_disp,

    input  wire [11:0] win_x0,
    input  wire [11:0] win_y0,
    input  wire [63:0] row0_pair,
    input  wire [63:0] row1_pair,
    input  wire        win_valid,

    output wire [11:0] src_x,
    output wire [11:0] src_y,

    output wire        vs_out,
    output wire        hs_out,
    output wire        de_out,
    output wire [15:0] rgb_out,

    // band_wr v5 read side
    input  wire        rd_bank_sel,
    input  wire [14:0] rd_addr,
    output wire [15:0] rd_data,
    input  wire        rd_done,
    output wire        band_ready_0,
    output wire        band_ready_1,
    output wire        band_idx
);

    wire [10:0] x_corr, x_gamma;
    wire [9:0]  y_corr, y_gamma;
    wire [15:0] rgb_c, rgb_g;
    wire        de_c, de_g;
    wire        pix_valid_c;
    wire        vs_c, hs_c;

    // 1. 鱼眼矫正链路
    corr_top u_corr (
        .clk(clk), .rstn(rstn),
        .vs_in(1'b0), .hs_in(1'b0), .de_in(de_in),
        .u(u), .v(v), .valid_aff(valid_aff), 
        .u_disp(u_disp), .v_disp(v_disp),
        .win_x0(win_x0), .win_y0(win_y0),
        .src_x(src_x), .src_y(src_y),
        .row0_pair(row0_pair), .row1_pair(row1_pair),
        .win_valid(win_valid),
        .vs_out(vs_c), .hs_out(hs_c), .de_out(de_c),
        .rgb_out(rgb_c), 
        .pix_valid_out(pix_valid_c),         
        .x_out(x_corr), .y_out(y_corr)
    );

    // 2. 自适应 Gamma 模块
    gamma_top u_gamma (
        .clk(clk), .rstn(rstn),
        .frame_end_pulse(frame_end_pulse),   
        .mode_changed(mode_changed),         // 【修改】接入切换脉冲
        .de_in(de_c), 
        .valid_in(pix_valid_c),              
        .rgb_in(rgb_c),
        .x_in(x_corr), .y_in(y_corr),
        .de_out(de_g), .rgb_out(rgb_g), 
        .x_out(x_gamma), .y_out(y_gamma)
    );

    // 3. 乒乓写缓存
    band_wr u_band (
        .clk(clk), .rstn(rstn),
        .valid_in(de_g),                     
        .x_in(x_gamma), .y_in(y_gamma), .rgb_in(rgb_g),
        .rd_bank_sel(rd_bank_sel), .rd_addr(rd_addr), .rd_data(rd_data),
        .rd_done(rd_done),
        .band_ready_0(band_ready_0), .band_ready_1(band_ready_1),
        .band_idx(band_idx)
    );

    // 对顶层输出
    assign vs_out = vs_c;
    assign hs_out = hs_c;
    assign de_out = de_g;
    assign rgb_out = rgb_g;

endmodule