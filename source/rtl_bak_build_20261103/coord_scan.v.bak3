`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// fisheye_band_reader (band_wr v5)
//
//   rd_bank toggles after each 16-line band; reads the bank whose ready flag is
//   high.  band_wr v5 fills the other bank while this one is read.
//   rd_data is registered in band_wr; de/vs/hs are delayed 1 pclk and rgb_out is
//   combinational so data/de are aligned.
//////////////////////////////////////////////////////////////////////////////////
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

    // Align the band_wr read address/bank with de_out.  band_wr's rd_data is
    // registered, so sample the address on de_in and let the registered data
    // line up with the one-cycle-delayed de_out.
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

    wire        bank_ready = rd_bank_r ? band_ready_1 : band_ready_0;
    assign rd_bank_sel = rd_bank_r;
    assign rd_addr     = rd_addr_r;

    always @(posedge pclk) begin
        if (!rstn) begin
            rd_bank <= 1'b0;
            rd_done <= 1'b0;
        end
        else begin
            rd_done <= de_in && bank_ready &&
                       (x_cnt == H_NUM-1) && (y_in_band == 4'd15);
            if (de_in && bank_ready &&
                (x_cnt == H_NUM-1) && (y_in_band == 4'd15))
                rd_bank <= ~rd_bank;
        end
    end

    // de_out is delayed two cycles so it aligns with band_wr's registered
    // rd_data (address sampled on de_in, data available one cycle later).
    reg de_d0, de_d1, vs_d0, vs_d1, hs_d0, hs_d1;
    reg bank_ready_d0, bank_ready_d1;

    always @(posedge pclk) begin
        if (!rstn) begin
            de_d0 <= 1'b0; de_d1 <= 1'b0;
            vs_d0 <= 1'b0; vs_d1 <= 1'b0;
            hs_d0 <= 1'b0; hs_d1 <= 1'b0;
            bank_ready_d0 <= 1'b0; bank_ready_d1 <= 1'b0;
        end else begin
            de_d0 <= de_in; de_d1 <= de_d0;
            vs_d0 <= vs_in; vs_d1 <= vs_d0;
            hs_d0 <= hs_in; hs_d1 <= hs_d0;
            bank_ready_d0 <= bank_ready;
            bank_ready_d1 <= bank_ready_d0;
        end
    end

    assign vs_out = vs_d1;
    assign hs_out = hs_d1;
    assign de_out = de_d1;
    assign rgb_out = (de_d1 && bank_ready_d1) ? rd_data : 16'd0;

endmodule
