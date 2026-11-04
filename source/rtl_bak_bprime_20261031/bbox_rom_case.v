`timescale 1ns / 1ps
module bbox_rom #(
    parameter TILES  = 3600,
    parameter ADDR_W = 12
)(
    input                     clk,
    input      [ADDR_W-1:0]   tile_idx,
    output [11:0]             win_x0,
    output [11:0]             win_y0,
    output                    tile_valid
);
    wire [31:0] dout;
    bbox_rom_ip u_ip (
        .addr    (tile_idx),
        .rd_data (dout),
        .clk     (clk),
        .rst     (1'b0)
    );
    assign win_x0     = dout[23:12];
    assign win_y0     = dout[11:0];
    assign tile_valid = dout[24];
endmodule
