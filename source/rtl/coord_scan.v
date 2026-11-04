`timescale 1ns / 1ps
////////////////////////////////////////////////////////////////////////////////
// fisheye_band_reader (band_wr v5)
//
//   rd_bank advances once per 16-line display band, unconditionally, so the
//   display stays locked to the frame instead of drifting when a band arrives
//   late.  rd_addr = (y%16)*1280 + x.
//
//   2026-11-03: the band pointer used to advance only when the bank was ready,
//   which made a single late band desynchronise the writer/reader pairing for
//   the rest of the frame.  It now always advances, and a late band simply
//   shows the previous content of that bank instead of black.
////////////////////////////////////////////////////////////////////////////////
module fisheye_band_reader #(
    parameter H_NUM = 1280,
    parameter V_NUM = 720
)(
    input  wire        pclk,
    input  wire        rstn,

    input  wire        vs_in,
    input  wire        hs_in,
    input  wire        de_in,

    input  wire        band_ready_0,
    input  wire        band_ready_1,
    input  wire        band_idx,

    output wire        rd_bank_sel,
    output wire [14:0] rd_addr,
    input  wire [15:0] rd_data,
    output reg         rd_done,

    output wire        vs_out,
    output wire        hs_out,
    output wire        de_out,
    output wire [15:0] rgb_out
);

    reg [10:0] x_cnt;
    reg [9:0]  y_cnt;
    reg        vs_d, de_d;
    reg        rd_bank;

    always @(posedge pclk) begin
        vs_d <= vs_in;
        de_d <= de_in;
    end

    wire vs_rise = vs_in & ~vs_d;

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

    // sample the address/bank on de_in so band_wr's registered rd_data lines up
    // with the one-cycle-delayed de_out
    reg [14:0] rd_addr_r;
    reg        rd_bank_r;
    always @(posedge pclk) begin
        if (!rstn) begin
            rd_addr_r <= 15'd0;
            rd_bank_r <= 1'b0;
        end else if (de_in) begin
            rd_addr_r <= y_offset + {4'd0, x_cnt};
            rd_bank_r <= rd_bank;
        end
    end

    assign rd_bank_sel = rd_bank_r;
    assign rd_addr     = rd_addr_r;

    // end of a 16-line band: free the bank and advance, ALWAYS
    wire band_end = de_in && (x_cnt == H_NUM-1) && (y_in_band == 4'd15);

    always @(posedge pclk) begin
        if (!rstn) begin
            rd_bank <= 1'b0;
            rd_done <= 1'b0;
        end
        else begin
            rd_done <= band_end;
            if (band_end) rd_bank <= ~rd_bank;
        end
    end

    // de_out is delayed two cycles so it aligns with band_wr's registered rd_data
    reg de_d0, de_d1, vs_d0, vs_d1, hs_d0, hs_d1;

    always @(posedge pclk) begin
        if (!rstn) begin
            de_d0 <= 1'b0; de_d1 <= 1'b0;
            vs_d0 <= 1'b0; vs_d1 <= 1'b0;
            hs_d0 <= 1'b0; hs_d1 <= 1'b0;
        end else begin
            de_d0 <= de_in; de_d1 <= de_d0;
            vs_d0 <= vs_in; vs_d1 <= vs_d0;
            hs_d0 <= hs_in; hs_d1 <= hs_d0;
        end
    end

    assign vs_out  = vs_d1;
    assign hs_out  = hs_d1;
    assign de_out  = de_d1;
    assign rgb_out = de_d1 ? rd_data : 16'd0;

endmodule
