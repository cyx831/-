// ============================================================
// win_req: 全局坐标 -> 窗口局部坐标 + 64bit pair 半字拆分
// ============================================================
module win_req (
    input  wire        clk, rstn,
    input  wire [15:0] xs_q, ys_q,
    input  wire        de_in,
    input  wire [11:0] win_x0, win_y0,
    output wire [11:0] src_x, src_y,
    input  wire [63:0] row0_pair, row1_pair,
    input  wire        win_valid,
    output reg  [15:0] p00, p01, p10, p11,
    output reg  [3:0]  fx_out, fy_out,
    output reg         valid_out
);
    wire [15:0] win_x0_q = {win_x0, 4'b0};
    wire [15:0] win_y0_q = {win_y0, 4'b0};
    wire [15:0] src_x_q = xs_q - win_x0_q;
    wire [15:0] src_y_q = ys_q - win_y0_q;
    wire [11:0] src_x_int = src_x_q[15:4];
    wire [11:0] src_y_int = src_y_q[15:4];
    wire [3:0]  frac_x = src_x_q[3:0];
    wire [3:0]  frac_y = src_y_q[3:0];

    assign src_x = src_x_int;
    assign src_y = src_y_int;

    reg [1:0] sel_d;
    reg [3:0] fx_d1, fx_d2, fy_d1, fy_d2;
    reg       de_d1, de_d2;

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            sel_d <= 0; fx_d1 <= 0; fx_d2 <= 0; fy_d1 <= 0; fy_d2 <= 0; de_d1 <= 0; de_d2 <= 0;
        end else begin
            sel_d[0] <= src_x_int[0]; sel_d[1] <= sel_d[0];
            fx_d1 <= frac_x; fx_d2 <= fx_d1; fy_d1 <= frac_y; fy_d2 <= fy_d1;
            de_d1 <= de_in;  de_d2 <= de_d1;
        end
    end

    wire [15:0] p00_c = sel_d[1] ? row0_pair[31:16] : row0_pair[15:0];
    wire [15:0] p01_c = sel_d[1] ? row0_pair[47:32] : row0_pair[31:16];
    wire [15:0] p10_c = sel_d[1] ? row1_pair[31:16] : row1_pair[15:0];
    wire [15:0] p11_c = sel_d[1] ? row1_pair[47:32] : row1_pair[31:16];

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            p00 <= 0; p01 <= 0; p10 <= 0; p11 <= 0; fx_out <= 0; fy_out <= 0; valid_out <= 0;
        end else begin
            p00 <= p00_c; p01 <= p01_c; p10 <= p10_c; p11 <= p11_c;
            fx_out <= fx_d2; fy_out <= fy_d2; valid_out <= de_d2 & win_valid;
        end
    end
endmodule