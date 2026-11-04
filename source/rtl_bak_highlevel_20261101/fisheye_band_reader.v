`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// fisheye_band_reader
//
// Converts the 720p timing from sync_vg into a 16-line band read:
//   rd_addr      = (y%16)*1280 + x
//   rd_band_sel  = band_idx  (the bank band_wr has just filled)
//   rd_done      = 1-cycle pulse at the last pixel of each 16-line band
//
// band_wr's rd_data is registered (1 pclk); de/vs/hs are delayed 1 pclk to
// match.  If band_ready is low, the output is black (the display timing is
// never stalled).
//////////////////////////////////////////////////////////////////////////////////
module fisheye_band_reader #(
    parameter H_NUM = 1280,
    parameter V_NUM = 720
)(
    input  wire        pclk,
    input  wire        rstn,

    // timing from sync_vg
    input  wire        vs_in,
    input  wire        hs_in,
    input  wire        de_in,

    // band_wr side
    input  wire        band_ready,
    input  wire        band_idx,
    output wire        rd_band_sel,
    output wire [14:0] rd_addr,
    input  wire [15:0] rd_data,
    output reg         rd_done,

    // HDMI output (aligned with rd_data)
    output reg         vs_out,
    output reg         hs_out,
    output reg         de_out,
    output wire [15:0] rgb_out
);

    reg [10:0] x_cnt;
    reg [9:0]  y_cnt;
    reg        vs_d, de_d;

    always @(posedge pclk) begin
        vs_d <= vs_in;
        de_d <= de_in;
    end

    wire vs_rise = vs_in & ~vs_d;
    wire de_rise = de_in & ~de_d;

    always @(posedge pclk) begin
        if (!rstn)
            x_cnt <= 11'd0;
        else if (!de_in)
            x_cnt <= 11'd0;
        else if (x_cnt == H_NUM-1)
            x_cnt <= 11'd0;
        else
            x_cnt <= x_cnt + 11'd1;
    end

    always @(posedge pclk) begin
        if (!rstn)
            y_cnt <= 10'd0;
        else if (vs_rise)
            y_cnt <= 10'd0;
        else if (de_in && (x_cnt == H_NUM-1))
            y_cnt <= y_cnt + 10'd1;
    end

    wire [3:0]  y_in_band = y_cnt[3:0];
    wire [14:0] y_offset = ({5'd0, y_in_band} << 10) + ({5'd0, y_in_band} << 8);

    assign rd_band_sel = band_idx;
    assign rd_addr     = y_offset + {4'd0, x_cnt};

    // rd_done at the last pixel of a 16-line band; only if that band is ready
    always @(posedge pclk) begin
        if (!rstn)
            rd_done <= 1'b0;
        else
            rd_done <= de_in && band_ready && (x_cnt == H_NUM-1) && (y_in_band == 4'd15);
    end

    // rd_data is registered in band_wr; delay timing by 1
    // rd_data is registered in band_wr; de_out is the 1-cycle-delayed de.
    // rgb_out is combinational so data and de are aligned at the same cycle.
    assign rgb_out = (de_out && band_ready) ? rd_data : 16'd0;

    always @(posedge pclk) begin
        if (!rstn) begin
            vs_out  <= 1'b0;
            hs_out  <= 1'b0;
            de_out  <= 1'b0;
        end
        else begin
            vs_out  <= vs_in;
            hs_out  <= hs_in;
            de_out  <= de_in;
        end
    end

endmodule
