// ============================================================
// corr_top: coord_lut -> win_req -> bilinear565
// 高阶版修改：
// 1. u, v 扩宽为 16-bit (Q12.4)
// 2. 接入 valid_aff (仿射越界标识)
// 3. 输出 pix_valid_out 给 Gamma 做统计门控
// 4. 所有输出严格对齐在 15 拍 (修复了 win_x0 对齐延迟不足的问题)
// ============================================================
module corr_top (
    input  wire        clk,
    input  wire        rstn,
    input  wire        vs_in,
    input  wire        hs_in,
    input  wire        de_in,
    input  wire [15:0] u,           // 修改：扩宽为 16-bit Q12.4
    input  wire [15:0] v,           // 修改：扩宽为 16-bit Q12.4
    input  wire        valid_aff,   // 新增：来自 rotate_map 的仿射越界标识
    input  wire [11:0] u_disp,      // 显示坐标(未旋转)，给 band_wr 用
    input  wire [11:0] v_disp,
    input  wire [11:0] win_x0,
    input  wire [11:0] win_y0,
    output wire [11:0] src_x,
    output wire [11:0] src_y,
    input  wire [63:0] row0_pair,
    input  wire [63:0] row1_pair,
    input  wire        win_valid,
    output wire        vs_out,
    output wire        hs_out,
    output wire        de_out,
    output wire [15:0] rgb_out,
    output wire        pix_valid_out, // 新增：给 Gamma 的有效标志
    output wire [10:0] x_out,
    output wire [9:0]  y_out
);

    // ---------------- win_x0/win_y0 延迟 13 拍 ----------------
    // 【修复】rotate_map 4 拍 + coord_lut 9 拍 = 13 拍；
    // 原来的 15 拍比真实延迟晚 2 拍，tile 开头 2 个像素会拿上一个 tile 的
    // win_x0 去算 src_x，局部 sx 超出 64 窗口 -> win_valid=0 -> 每 32 像素黑 2 列。
    reg [11:0] win_x0_sr [0:12];
    reg [11:0] win_y0_sr [0:12];
    integer j;
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            for (j = 0; j < 13; j = j + 1) begin win_x0_sr[j] <= 0; win_y0_sr[j] <= 0; end
        end else begin
            win_x0_sr[0] <= win_x0; win_y0_sr[0] <= win_y0;
            for (j = 1; j < 13; j = j + 1) begin win_x0_sr[j] <= win_x0_sr[j-1]; win_y0_sr[j] <= win_y0_sr[j-1]; end
        end
    end
    wire [11:0] win_x0_aligned = win_x0_sr[12];
    wire [11:0] win_y0_aligned = win_y0_sr[12];

    // ---------------- coord_lut ----------------
    wire [15:0] xs_q, ys_q;
    wire        de_coord;
    wire        coord_valid; // 来自 coord_lut 的坐标有效性

    coord_lut u_coord (
        .clk(clk), .rstn(rstn), .de_in(de_in), 
        .u(u), .v(v),                       // 输入 16-bit Q12.4
        .xs_q(xs_q), .ys_q(ys_q), 
        .de_out(de_coord),
        .coord_valid(coord_valid)           // 输出有效性 (9拍)
    );

    // ---------------- win_req ----------------
    wire [15:0] p00, p01, p10, p11;
    wire [3:0]  fx, fy;
    wire        de_win;

    win_req u_win (
        .clk(clk), .rstn(rstn),
        .xs_q(xs_q), .ys_q(ys_q), .de_in(de_coord),
        .win_x0(win_x0_aligned), .win_y0(win_y0_aligned),
        .src_x(src_x), .src_y(src_y),
        .row0_pair(row0_pair), .row1_pair(row1_pair), .win_valid(win_valid),
        .p00(p00), .p01(p01), .p10(p10), .p11(p11),
        .fx_out(fx), .fy_out(fy), .valid_out(de_win)
    );

    // ---------------- bilinear565 ----------------
    wire [15:0] rgb;
    wire        de_bil;

    bilinear565 u_bil (
        .clk(clk), .rstn(rstn), .valid_in(de_win),
        .p00(p00), .p01(p01), .p10(p10), .p11(p11), .fx(fx), .fy(fy),
        .rgb_out(rgb), .valid_out(de_bil)
    );

    // ---------------- 15拍延迟对齐 ----------------
    localparam L = 15;
    reg [L-1:0] vs_sr, hs_sr, de_sr;
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin vs_sr <= 0; hs_sr <= 0; de_sr <= 0; end
        else begin
            vs_sr <= {vs_sr[L-2:0], vs_in}; 
            hs_sr <= {hs_sr[L-2:0], hs_in}; 
            de_sr <= {de_sr[L-2:0], de_in};
        end
    end

    reg [10:0] x_sr [0:L-1];
    reg [9:0]  y_sr [0:L-1];
    integer i;
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            for (i = 0; i < L; i = i + 1) begin x_sr[i] <= 0; y_sr[i] <= 0; end
        end else begin
            // 注意：显示坐标用未旋转的 u_disp/v_disp，不能拿旋转后的 u/v
            x_sr[0] <= u_disp; 
            y_sr[0] <= v_disp;
            for (i = 1; i < L; i = i + 1) begin 
                x_sr[i] <= x_sr[i-1]; 
                y_sr[i] <= y_sr[i-1]; 
            end
        end
    end

    // ---------------- valid 标识对齐 ----------------
    // 1. 来自 coord_lut 的 valid 是 9 拍，需要再延迟 6 拍到 15 拍
    reg [5:0] coord_valid_sr;
    always @(posedge clk or negedge rstn) begin
        if (!rstn) coord_valid_sr <= 0;
        else       coord_valid_sr <= {coord_valid_sr[4:0], coord_valid};
    end

    // 2. 来自 rotate_map 的 valid_aff 随 de_in 一起进，需要延迟 15 拍
    reg [14:0] valid_aff_sr;
    always @(posedge clk or negedge rstn) begin
        if (!rstn) valid_aff_sr <= 0;
        else       valid_aff_sr <= {valid_aff_sr[13:0], valid_aff};
    end

    // 最终的有效信号 = 坐标有效 & 窗口命中插值有效 & 仿射未越界 & 输出圆内
    // Python: r_norm <= 1.0 - RADIAL_SHRINK, RADIAL_SHRINK=0.04
    // r_norm = sqrt((x-640)^2+(y-360)^2)/sqrt(640^2+360^2) <= 0.96
    wire signed [12:0] dx_rad = $signed({1'b0, x_sr[L-1]}) - 13'sd640;
    wire signed [11:0] dy_rad = $signed({2'b00, y_sr[L-1]}) - 12'sd360;
    wire [26:0] rad2 = dx_rad*dx_rad + dy_rad*dy_rad;
    wire radial_ok = (rad2 <= 27'd496927); // (0.96^2)*(640^2+360^2)

    wire final_pix_valid = coord_valid_sr[5] & de_bil & valid_aff_sr[14] & radial_ok;

    // ---------------- 输出赋值 ----------------
    assign vs_out  = vs_sr[L-1];
    assign hs_out  = hs_sr[L-1];
    assign de_out  = de_sr[L-1];  // 满屏 DE，不断流
    
    // 掩膜填黑：越界的强制输出纯黑，有效标识给 Gamma
    assign rgb_out = final_pix_valid ? rgb : 16'h0000;
    assign pix_valid_out = final_pix_valid;
    
    assign x_out   = x_sr[L-1];
    assign y_out   = y_sr[L-1];

endmodule