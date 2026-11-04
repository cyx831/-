// ============================================================
// coord_lut: 输出像素(u,v) -> 源图取样坐标(xs_q,ys_q), Q12.4
// 高阶版修改：
// 1. 输入位宽扩宽为 16-bit Q12.4，去掉内部左移
// 2. 新增 coord_valid 输出，与坐标严格同拍
// ============================================================
module coord_lut #(
    parameter CXN_Q    = 16'sd10122,
    parameter CYN_Q    = 16'sd6051,
    parameter CX_Q     = 16'sd10164,
    parameter CY_Q     = 16'sd5907,
    parameter GAIN_INT = 32'd116681
)(
    input  wire        clk,
    input  wire        rstn,
    input  wire        de_in,
    input  wire [15:0] u,           // 修改：16-bit Q12.4
    input  wire [15:0] v,           // 修改：16-bit Q12.4
    output reg  [15:0] xs_q,
    output reg  [15:0] ys_q,
    output reg         de_out,
    output reg         coord_valid  // 新增：越界/圆外标识
);

    reg signed [15:0] dx_q_1, dy_q_1;
    reg de_1;
    reg [31:0] r2_px_2;
    reg de_2;
    reg [63:0] r2_gain_3;
    reg de_3;
    reg [23:0] addr_fixed_4;
    reg de_4;
    reg [11:0] addr0_5;
    reg [7:0]  frac_5;
    reg de_5;
    wire [17:0] K0_6, K1_6;
    reg [7:0]  frac_6;
    reg de_6;
    reg signed [17:0] K_interp_7;
    reg de_7;
    reg signed [31:0] prod_x_8, prod_y_8;
    reg de_8;

    reg signed [15:0] dx_q_2, dx_q_3, dx_q_4, dx_q_5, dx_q_6, dx_q_7;
    reg signed [15:0] dy_q_2, dy_q_3, dy_q_4, dy_q_5, dy_q_6, dy_q_7;

    // 级1：去掉原来的 4'b0 左移
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            dx_q_1 <= 0; dy_q_1 <= 0; de_1 <= 0;
        end else begin
            dx_q_1 <= $signed(u) - CXN_Q; 
            dy_q_1 <= $signed(v) - CYN_Q;
            de_1   <= de_in;
        end
    end

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            dx_q_2<=0; dx_q_3<=0; dx_q_4<=0; dx_q_5<=0; dx_q_6<=0; dx_q_7<=0;
            dy_q_2<=0; dy_q_3<=0; dy_q_4<=0; dy_q_5<=0; dy_q_6<=0; dy_q_7<=0;
        end else begin
            dx_q_2<=dx_q_1; dx_q_3<=dx_q_2; dx_q_4<=dx_q_3;
            dx_q_5<=dx_q_4; dx_q_6<=dx_q_5; dx_q_7<=dx_q_6;
            dy_q_2<=dy_q_1; dy_q_3<=dy_q_2; dy_q_4<=dy_q_3;
            dy_q_5<=dy_q_4; dy_q_6<=dy_q_5; dy_q_7<=dy_q_6;
        end
    end

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin r2_px_2 <= 0; de_2 <= 0; end
        else begin r2_px_2 <= dx_q_1*dx_q_1 + dy_q_1*dy_q_1; de_2 <= de_1; end
    end

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin r2_gain_3 <= 0; de_3 <= 0; end
        else begin r2_gain_3 <= r2_px_2 * GAIN_INT; de_3 <= de_2; end
    end

    wire [39:0] shifted  = r2_gain_3[63:24];
    wire [23:0] sat_val  = {12'd4094, 8'd255};
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin addr_fixed_4 <= 0; de_4 <= 0; end
        else begin
            if (shifted > {16'd0, sat_val}) addr_fixed_4 <= sat_val;
            else addr_fixed_4 <= shifted[23:0];
            de_4 <= de_3;
        end
    end

    wire [11:0] addr0_5_w = (addr_fixed_4[19:8] > 12'd4094) ? 12'd4094 : addr_fixed_4[19:8];
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin addr0_5 <= 0; frac_5 <= 0; de_5 <= 0; end
        else begin addr0_5 <= addr0_5_w; frac_5 <= addr_fixed_4[7:0]; de_5 <= de_4; end
    end

    wire [17:0] rom_K0, rom_K1;
    lut_rom u_rom (.clk(clk), .addr0(addr0_5), .K0(rom_K0), .K1(rom_K1));
    assign K0_6 = rom_K0;
    assign K1_6 = rom_K1;

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin frac_6 <= 0; de_6 <= 0; end
        else begin frac_6 <= frac_5; de_6 <= de_5; end
    end

    wire [26:0] interp = K0_6*(256 - frac_6) + K1_6*frac_6 + 128;
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin K_interp_7 <= 0; de_7 <= 0; end
        else begin K_interp_7 <= interp[26:8]; de_7 <= de_6; end
    end

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin prod_x_8 <= 0; prod_y_8 <= 0; de_8 <= 0; end
        else begin prod_x_8 <= dx_q_7 * K_interp_7; prod_y_8 <= dy_q_7 * K_interp_7; de_8 <= de_7; end
    end

    function signed [32:0] rshift_round;
        input signed [31:0] term;
        reg signed [32:0] ext, abs_v, rnd, sh;
        begin
            ext   = {term[31], term};
            abs_v = ext[32] ? -ext : ext;
            rnd   = (abs_v + 33'sd32768) >>> 16;
            sh    = ext[32] ? -rnd : rnd;
            rshift_round = sh;
        end
    endfunction

    wire signed [32:0] px_out = rshift_round(prod_x_8);
    wire signed [32:0] py_out = rshift_round(prod_y_8);
    wire signed [32:0] xs_pre = $signed({17'b0, CX_Q}) + px_out;
    wire signed [32:0] ys_pre = $signed({17'b0, CY_Q}) + py_out;
    
    // 越界判断（在翻转钳位前判断）
    wire in_bound = (xs_pre >= 0) && (xs_pre <= 33'sd20464) &&
                    (ys_pre >= 0) && (ys_pre <= 33'sd11504);

    wire [15:0] xs_flip = 16'd20464 - xs_pre[15:0];
    wire [15:0] ys_flip = 16'd11504 - ys_pre[15:0];

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            xs_q <= 0; ys_q <= 0; de_out <= 0; coord_valid <= 0;
        end else begin
            xs_q   <= (xs_flip > 16'd20464) ? 16'd20464 : xs_flip;
            ys_q   <= (ys_flip > 16'd11504) ? 16'd11504 : ys_flip;
            de_out <= de_8; 
            coord_valid <= in_bound; // 严格跟 de_out 同拍
        end
    end

endmodule