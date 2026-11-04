// ============================================================
// bilinear565: 4 邻域 RGB565 + Q0.4 权重 -> 双线性 RGB565
// 3 级流水线：行插值 -> 列插值 -> 舍入拼合
// ============================================================
module bilinear565 (
    input  wire        clk,
    input  wire        rstn,
    input  wire        valid_in,
    input  wire [15:0] p00, p01, p10, p11,  // 4 邻域 RGB565
    input  wire [3:0]  fx, fy,              // Q0.4 权重，0~15
    output reg  [15:0] rgb_out,
    output reg         valid_out
);

    // ---------------- 拆通道 ----------------
    wire [4:0] r00 = p00[15:11], r01 = p01[15:11];
    wire [4:0] r10 = p10[15:11], r11 = p11[15:11];
    wire [5:0] g00 = p00[10:5],  g01 = p01[10:5];
    wire [5:0] g10 = p10[10:5],  g11 = p11[10:5];
    wire [4:0] b00 = p00[4:0],   b01 = p01[4:0];
    wire [4:0] b10 = p10[4:0],   b11 = p11[4:0];

    // ---------------- 级1：行插值 ----------------
    // row = p_left*(16-fx) + p_right*fx，权重和=16
    // R/B: 最大 31*16=496，9位；G: 最大 63*16=1008，10位
    reg [8:0]  r0_1, r1_1;
    reg [9:0]  g0_1, g1_1;
    reg [8:0]  b0_1, b1_1;
    reg [3:0]  fy_1;
    reg        valid_1;

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            r0_1<=0; r1_1<=0; g0_1<=0; g1_1<=0; b0_1<=0; b1_1<=0;
            fy_1<=0; valid_1<=0;
        end else begin
            r0_1 <= r00*(16-fx) + r01*fx;
            r1_1 <= r10*(16-fx) + r11*fx;
            g0_1 <= g00*(16-fx) + g01*fx;
            g1_1 <= g10*(16-fx) + g11*fx;
            b0_1 <= b00*(16-fx) + b01*fx;
            b1_1 <= b10*(16-fx) + b11*fx;
            fy_1  <= fy;
            valid_1 <= valid_in;
        end
    end

    // ---------------- 级2：列插值 ----------------
    // sum = row0*(16-fy) + row1*fy，权重和=256
    // R/B: 最大 496*16=7936，13位；G: 最大 1008*16=16128，14位
    reg [12:0] r_sum_2, b_sum_2;
    reg [13:0] g_sum_2;
    reg        valid_2;

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            r_sum_2<=0; g_sum_2<=0; b_sum_2<=0; valid_2<=0;
        end else begin
            r_sum_2 <= r0_1*(16-fy_1) + r1_1*fy_1;
            g_sum_2 <= g0_1*(16-fy_1) + g1_1*fy_1;
            b_sum_2 <= b0_1*(16-fy_1) + b1_1*fy_1;
            valid_2 <= valid_1;
        end
    end

    // ---------------- 级3：舍入 + clamp + 拼合 ----------------
    // out = (sum + 128) >> 8，clamp 到 31/63/31
    wire [12:0] r_rnd = (r_sum_2 + 13'd128) >> 8;
    wire [13:0] g_rnd = (g_sum_2 + 14'd128) >> 8;
    wire [12:0] b_rnd = (b_sum_2 + 13'd128) >> 8;

    wire [4:0] r_out = (r_rnd > 13'd31) ? 5'd31 : r_rnd[4:0];
    wire [5:0] g_out = (g_rnd > 14'd63) ? 6'd63 : g_rnd[5:0];
    wire [4:0] b_out = (b_rnd > 13'd31) ? 5'd31 : b_rnd[4:0];

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            rgb_out <= 0; valid_out <= 0;
        end else begin
            rgb_out   <= {r_out, g_out, b_out};
            valid_out <= valid_2;
        end
    end

endmodule