`timescale 1ns / 1ps

module uart_tx #(
    parameter integer CLK_FREQ = 37125000,
    parameter integer BAUD     = 115200
)(
    input  wire       clk,
    input  wire       rstn,

    input  wire       tx_start,
    input  wire [7:0] tx_data,

    output reg        uart_tx_pin,
    output reg        tx_busy,
    output reg        tx_done
);

localparam integer CLKS_PER_BIT = CLK_FREQ / BAUD;

localparam [1:0] IDLE  = 2'd0,
                 START = 2'd1,
                 DATA  = 2'd2,
                 STOP  = 2'd3;

reg [1:0]  state;
reg [31:0] clk_cnt;
reg [2:0]  bit_index;
reg [7:0]  data_buf;

// UART·¢ËÍ×´Ì¬»ú
always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        state       <= IDLE;
        clk_cnt     <= 32'd0;
        bit_index   <= 3'd0;
        data_buf    <= 8'd0;

        uart_tx_pin <= 1'b1;
        tx_busy     <= 1'b0;
        tx_done     <= 1'b0;
    end
    else begin
        tx_done <= 1'b0;

        case (state)

            IDLE: begin
                uart_tx_pin <= 1'b1;
                tx_busy     <= 1'b0;
                clk_cnt     <= 32'd0;
                bit_index   <= 3'd0;

                if (tx_start) begin
                    data_buf    <= tx_data;
                    tx_busy     <= 1'b1;
                    uart_tx_pin <= 1'b0;
                    state       <= START;
                end
            end

            START: begin
                if (clk_cnt == CLKS_PER_BIT - 1) begin
                    clk_cnt     <= 32'd0;
                    bit_index   <= 3'd0;
                    uart_tx_pin <= data_buf[0];
                    state       <= DATA;
                end
                else begin
                    clk_cnt <= clk_cnt + 1'b1;
                end
            end

            DATA: begin
                if (clk_cnt == CLKS_PER_BIT - 1) begin
                    clk_cnt <= 32'd0;

                    if (bit_index == 3'd7) begin
                        uart_tx_pin <= 1'b1;
                        state <= STOP;
                    end
                    else begin
                        bit_index <= bit_index + 1'b1;
                        uart_tx_pin <= data_buf[bit_index + 1'b1];
                    end
                end
                else begin
                    clk_cnt <= clk_cnt + 1'b1;
                end
            end

            STOP: begin
                if (clk_cnt == CLKS_PER_BIT - 1) begin
                    clk_cnt <= 32'd0;
                    tx_busy <= 1'b0;
                    tx_done <= 1'b1;
                    state <= IDLE;
                end
                else begin
                    clk_cnt <= clk_cnt + 1'b1;
                end
            end

            default: begin
                state       <= IDLE;
                uart_tx_pin <= 1'b1;
                tx_busy     <= 1'b0;
                clk_cnt     <= 32'd0;
            end

        endcase
    end
end

endmodule