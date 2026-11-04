`timescale 1ns / 1ps

module uart_rx #(
    parameter integer CLK_FREQ = 37125000,
    parameter integer BAUD     = 115200
)(
    input  wire       clk,
    input  wire       rstn,
    input  wire       uart_rx_pin,

    output reg [7:0]  rx_data,
    output reg        rx_valid
);

localparam integer CLKS_PER_BIT = CLK_FREQ / BAUD;
localparam integer HALF_BIT     = CLKS_PER_BIT / 2;

localparam [1:0] S_IDLE  = 2'd0,
                 S_START = 2'd1,
                 S_DATA  = 2'd2,
                 S_STOP  = 2'd3;

reg [1:0]  state;
reg [31:0] clk_cnt;
reg [2:0]  bit_idx;
reg [7:0]  data_buf;

reg rx_sync1;
reg rx_sync2;

// 输入同步
always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        rx_sync1 <= 1'b1;
        rx_sync2 <= 1'b1;
    end
    else begin
        rx_sync1 <= uart_rx_pin;
        rx_sync2 <= rx_sync1;
    end
end

// UART接收状态机
always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        state    <= S_IDLE;
        clk_cnt  <= 32'd0;
        bit_idx  <= 3'd0;
        data_buf <= 8'd0;
        rx_data  <= 8'd0;
        rx_valid <= 1'b0;
    end
    else begin
        rx_valid <= 1'b0;

        case (state)

            S_IDLE: begin
                clk_cnt <= 32'd0;
                bit_idx <= 3'd0;

                if (rx_sync2 == 1'b0)
                    state <= S_START;
            end

            S_START: begin
                if (clk_cnt == HALF_BIT - 1) begin
                    clk_cnt <= 32'd0;

                    if (rx_sync2 == 1'b0)
                        state <= S_DATA;
                    else
                        state <= S_IDLE;
                end
                else begin
                    clk_cnt <= clk_cnt + 1'b1;
                end
            end

            S_DATA: begin
                if (clk_cnt == CLKS_PER_BIT - 1) begin
                    clk_cnt <= 32'd0;

                    data_buf[bit_idx] <= rx_sync2;

                    if (bit_idx == 3'd7) begin
                        bit_idx <= 3'd0;
                        state <= S_STOP;
                    end
                    else begin
                        bit_idx <= bit_idx + 1'b1;
                    end
                end
                else begin
                    clk_cnt <= clk_cnt + 1'b1;
                end
            end

            S_STOP: begin
                if (clk_cnt == CLKS_PER_BIT - 1) begin
                    clk_cnt <= 32'd0;
                    state <= S_IDLE;

                    if (rx_sync2 == 1'b1) begin
                        rx_data <= data_buf;
                        rx_valid <= 1'b1;
                    end
                end
                else begin
                    clk_cnt <= clk_cnt + 1'b1;
                end
            end

            default: begin
                state <= S_IDLE;
                clk_cnt <= 32'd0;
            end

        endcase
    end
end

endmodule