// ============================================================
// gamma_top: 【诊断版】Gamma bypass
// 保留与正式版相同的端口和 1 拍输出延迟，pix 直通。
// 用于判断 0° 黑列是否来自 gamma LUT/选档逻辑。
// ============================================================
module gamma_top (
    input  wire        clk,
    input  wire        rstn,
    input  wire        frame_end_pulse,
    input  wire        mode_changed,
    input  wire        de_in,
    input  wire        valid_in,
    input  wire [15:0] rgb_in,
    input  wire [10:0] x_in,
    input  wire [9:0]  y_in,
    output reg         de_out,
    output reg  [15:0] rgb_out,
    output reg  [10:0] x_out,
    output reg  [9:0]  y_out
);

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            de_out  <= 1'b0;
            rgb_out <= 16'd0;
            x_out   <= 11'd0;
            y_out   <= 10'd0;
        end else begin
            de_out  <= de_in;
            rgb_out <= rgb_in;
            x_out   <= x_in;
            y_out   <= y_in;
        end
    end

endmodule
