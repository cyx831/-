`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// fisheye_core (band_wr v5)
//   corr_top (L=15) + band_wr double-pointer ping-pong
//////////////////////////////////////////////////////////////////////////////////
module fisheye_core (
    input  wire        clk,
    input  wire        rstn,

    input  wire        vs_in,
    input  wire        hs_in,
    input  wire        de_in,
    input  wire [11:0] u,
    input  wire [11:0] v,

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

    wire [10:0] x_corr;
    wire [9:0]  y_corr;

    corr_top u_corr (
        .clk(clk), .rstn(rstn),
        .vs_in(vs_in), .hs_in(hs_in), .de_in(de_in),
        .u(u), .v(v),
        .win_x0(win_x0), .win_y0(win_y0),
        .src_x(src_x), .src_y(src_y),
        .row0_pair(row0_pair), .row1_pair(row1_pair),
        .win_valid(win_valid),
        .vs_out(vs_out), .hs_out(hs_out), .de_out(de_out),
        .rgb_out(rgb_out),
        .x_out(x_corr), .y_out(y_corr)
    );

    band_wr u_band (
        .clk(clk), .rstn(rstn),
        .valid_in(de_out),
        .x_in(x_corr), .y_in(y_corr), .rgb_in(rgb_out),
        .rd_bank_sel(rd_bank_sel), .rd_addr(rd_addr), .rd_data(rd_data),
        .rd_done(rd_done),
        .band_ready_0(band_ready_0), .band_ready_1(band_ready_1),
        .band_idx(band_idx)
    );

endmodule
