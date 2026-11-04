`timescale 1ns / 1ps
module lut_rom (
    input  wire        clk,
    input  wire [11:0] addr0,
    output wire [17:0] K0,
    output wire [17:0] K1
);
    wire [35:0] dout;
    lut_rom_ip u_ip (
        .addr    (addr0),
        .rd_data (dout),
        .clk     (clk),
        .rst     (1'b0)
    );
    assign K0 = dout[35:18];
    assign K1 = dout[17:0];
endmodule
