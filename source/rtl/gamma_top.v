// ============================================================
// gamma_top: 5档自适应 Gamma (0.35, 0.65, 1.0, 1.5, 2.0)
// 包含来自前方的有效标识门控，绝不将黑边和越界计入统计
// 【修复】加入 mode_changed 信号，切换角度时强制回正常档防闪烁
// ============================================================
module gamma_top (
    input  wire        clk,
    input  wire        rstn,
    input  wire        frame_end_pulse, // 来自 tile_scan_gen 的帧末单拍脉冲
    input  wire        mode_changed,    // 【新增】来自顶层的角度切换脉冲
    input  wire        de_in,           // 满屏 DE
    input  wire        valid_in,        // 来自 corr_top 的 pix_valid_out (已包含圆外和仿射越界标识)
    input  wire [15:0] rgb_in,          // 掩膜后的 RGB565 数据
    input  wire [10:0] x_in,
    input  wire [9:0]  y_in,
    output reg         de_out,
    output reg  [15:0] rgb_out,
    output reg  [10:0] x_out,
    output reg  [9:0]  y_out
);

    // ---------------- 拆解 RGB565 ----------------
    wire [4:0] r_in = rgb_in[15:11];
    wire [5:0] g_in = rgb_in[10:5];
    wire [4:0] b_in = rgb_in[4:0];

    // 亮度计算：Y = 4R + 2G + B，最大值 281
    (* keep = "true" *) wire [8:0] y_val = (r_in << 2) + (g_in << 1) + b_in;

    // ---------------- 帧末脉冲（本地精确产生） ----------------
    // 顶层把 frame_end_pulse 接成 0 时，用显示坐标自己产生：一帧最后一个像素
    // (x=1279, y=719) 到达 gamma 的那一拍，正好是本遍扫描统计的边界。
    wire last_pix_of_pass = de_in && (x_in == 11'd1279) && (y_in == 10'd719);
    wire fep = frame_end_pulse | last_pix_of_pass;

    // ---------------- 门控统计 ----------------
    wire pix_eff = de_in && valid_in;

    (* keep = "true" *) reg [31:0] sum_y;
    (* keep = "true" *) reg [20:0] cnt;

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            sum_y <= 32'd0;
            cnt   <= 21'd0;
        end else if (fep) begin
            sum_y <= 32'd0;
            cnt   <= 21'd0;
        end else if (pix_eff) begin
            sum_y <= sum_y + y_val;
            cnt   <= cnt + 1'b1;
        end
    end

    // ---------------- 5档自适应选档 ----------------
    wire [31:0] th1 = 32'd40  * cnt;
    wire [31:0] th2 = 32'd80  * cnt;
    wire [31:0] th3 = 32'd160 * cnt;
    wire [31:0] th4 = 32'd220 * cnt;

    (* keep = "true" *) reg [2:0] auto_sel;

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            auto_sel <= 3'd2; // 默认正常档
        end else if (fep) begin
            // 【隐患13修复】如果发生了角度切换，强制回到 2 (正常档)，让下一帧稳定
            if (mode_changed) begin
                auto_sel <= 3'd2;
            end 
            // 否则正常根据亮度判断
            else if (cnt != 21'd0) begin
                if (sum_y < th1)      auto_sel <= 3'd0; // 极暗 -> 0.35
                else if (sum_y < th2) auto_sel <= 3'd1; // 偏暗 -> 0.65
                else if (sum_y < th3) auto_sel <= 3'd2; // 正常 -> 1.0
                else if (sum_y < th4) auto_sel <= 3'd3; // 偏亮 -> 1.5
                else                  auto_sel <= 3'd4; // 极亮 -> 2.0
            end
        end
    end

    // ---------------- RGB565 LUT 查表 ----------------
    reg [4:0] r_lut;
    reg [5:0] g_lut;
    reg [4:0] b_lut;

    always @(*) begin
        case (auto_sel)
            // 档位 0: Gamma = 0.35 (提亮)
            3'd0: begin
                case (r_in)
                    5'd0: r_lut = 5'd0; 5'd1: r_lut = 5'd9; 5'd2: r_lut = 5'd12; 5'd3: r_lut = 5'd14; 
                    5'd4: r_lut = 5'd15; 5'd5: r_lut = 5'd16; 5'd6: r_lut = 5'd17; 5'd7: r_lut = 5'd18; 
                    5'd8: r_lut = 5'd19; 5'd9: r_lut = 5'd20; 5'd10: r_lut = 5'd21; 5'd11: r_lut = 5'd22; 
                    5'd12: r_lut = 5'd22; 5'd13: r_lut = 5'd23; 5'd14: r_lut = 5'd23; 5'd15: r_lut = 5'd24; 
                    5'd16: r_lut = 5'd25; 5'd17: r_lut = 5'd25; 5'd18: r_lut = 5'd26; 5'd19: r_lut = 5'd26; 
                    5'd20: r_lut = 5'd27; 5'd21: r_lut = 5'd27; 5'd22: r_lut = 5'd27; 5'd23: r_lut = 5'd28; 
                    5'd24: r_lut = 5'd28; 5'd25: r_lut = 5'd29; 5'd26: r_lut = 5'd29; 5'd27: r_lut = 5'd30; 
                    5'd28: r_lut = 5'd30; 5'd29: r_lut = 5'd30; 5'd30: r_lut = 5'd31; 5'd31: r_lut = 5'd31; 
                    default: r_lut = r_in;
                endcase
                case (g_in)
                    6'd0: g_lut = 6'd0; 6'd1: g_lut = 6'd15; 6'd2: g_lut = 6'd19; 6'd3: g_lut = 6'd22; 
                    6'd4: g_lut = 6'd24; 6'd5: g_lut = 6'd26; 6'd6: g_lut = 6'd28; 6'd7: g_lut = 6'd29; 
                    6'd8: g_lut = 6'd31; 6'd9: g_lut = 6'd32; 6'd10: g_lut = 6'd33; 6'd11: g_lut = 6'd34; 
                    6'd12: g_lut = 6'd35; 6'd13: g_lut = 6'd36; 6'd14: g_lut = 6'd37; 6'd15: g_lut = 6'd38; 
                    6'd16: g_lut = 6'd39; 6'd17: g_lut = 6'd40; 6'd18: g_lut = 6'd41; 6'd19: g_lut = 6'd41; 
                    6'd20: g_lut = 6'd42; 6'd21: g_lut = 6'd43; 6'd22: g_lut = 6'd44; 6'd23: g_lut = 6'd44; 
                    6'd24: g_lut = 6'd45; 6'd25: g_lut = 6'd46; 6'd26: g_lut = 6'd46; 6'd27: g_lut = 6'd47; 
                    6'd28: g_lut = 6'd47; 6'd29: g_lut = 6'd48; 6'd30: g_lut = 6'd49; 6'd31: g_lut = 6'd49; 
                    6'd32: g_lut = 6'd50; 6'd33: g_lut = 6'd50; 6'd34: g_lut = 6'd51; 6'd35: g_lut = 6'd51; 
                    6'd36: g_lut = 6'd52; 6'd37: g_lut = 6'd52; 6'd38: g_lut = 6'd53; 6'd39: g_lut = 6'd53; 
                    6'd40: g_lut = 6'd54; 6'd41: g_lut = 6'd54; 6'd42: g_lut = 6'd55; 6'd43: g_lut = 6'd55; 
                    6'd44: g_lut = 6'd56; 6'd45: g_lut = 6'd56; 6'd46: g_lut = 6'd56; 6'd47: g_lut = 6'd57; 
                    6'd48: g_lut = 6'd57; 6'd49: g_lut = 6'd58; 6'd50: g_lut = 6'd58; 6'd51: g_lut = 6'd59; 
                    6'd52: g_lut = 6'd59; 6'd53: g_lut = 6'd59; 6'd54: g_lut = 6'd60; 6'd55: g_lut = 6'd60; 
                    6'd56: g_lut = 6'd60; 6'd57: g_lut = 6'd61; 6'd58: g_lut = 6'd61; 6'd59: g_lut = 6'd62; 
                    6'd60: g_lut = 6'd62; 6'd61: g_lut = 6'd62; 6'd62: g_lut = 6'd63; 6'd63: g_lut = 6'd63; 
                    default: g_lut = g_in;
                endcase
                case (b_in)
                    5'd0: b_lut = 5'd0; 5'd1: b_lut = 5'd9; 5'd2: b_lut = 5'd12; 5'd3: b_lut = 5'd14; 
                    5'd4: b_lut = 5'd15; 5'd5: b_lut = 5'd16; 5'd6: b_lut = 5'd17; 5'd7: b_lut = 5'd18; 
                    5'd8: b_lut = 5'd19; 5'd9: b_lut = 5'd20; 5'd10: b_lut = 5'd21; 5'd11: b_lut = 5'd22; 
                    5'd12: b_lut = 5'd22; 5'd13: b_lut = 5'd23; 5'd14: b_lut = 5'd23; 5'd15: b_lut = 5'd24; 
                    5'd16: b_lut = 5'd25; 5'd17: b_lut = 5'd25; 5'd18: b_lut = 5'd26; 5'd19: b_lut = 5'd26; 
                    5'd20: b_lut = 5'd27; 5'd21: b_lut = 5'd27; 5'd22: b_lut = 5'd27; 5'd23: b_lut = 5'd28; 
                    5'd24: b_lut = 5'd28; 5'd25: b_lut = 5'd29; 5'd26: b_lut = 5'd29; 5'd27: b_lut = 5'd30; 
                    5'd28: b_lut = 5'd30; 5'd29: b_lut = 5'd30; 5'd30: b_lut = 5'd31; 5'd31: b_lut = 5'd31; 
                    default: b_lut = b_in;
                endcase
            end

            // 档位 1: Gamma = 0.65
            3'd1: begin
                case (r_in)
                    5'd0: r_lut = 5'd0; 5'd1: r_lut = 5'd3; 5'd2: r_lut = 5'd5; 5'd3: r_lut = 5'd7; 
                    5'd4: r_lut = 5'd8; 5'd5: r_lut = 5'd9; 5'd6: r_lut = 5'd11; 5'd7: r_lut = 5'd12; 
                    5'd8: r_lut = 5'd13; 5'd9: r_lut = 5'd14; 5'd10: r_lut = 5'd15; 5'd11: r_lut = 5'd16; 
                    5'd12: r_lut = 5'd17; 5'd13: r_lut = 5'd18; 5'd14: r_lut = 5'd18; 5'd15: r_lut = 5'd19; 
                    5'd16: r_lut = 5'd20; 5'd17: r_lut = 5'd21; 5'd18: r_lut = 5'd22; 5'd19: r_lut = 5'd23; 
                    5'd20: r_lut = 5'd23; 5'd21: r_lut = 5'd24; 5'd22: r_lut = 5'd25; 5'd23: r_lut = 5'd26; 
                    5'd24: r_lut = 5'd26; 5'd25: r_lut = 5'd27; 5'd26: r_lut = 5'd28; 5'd27: r_lut = 5'd28; 
                    5'd28: r_lut = 5'd29; 5'd29: r_lut = 5'd30; 5'd30: r_lut = 5'd30; 5'd31: r_lut = 5'd31; 
                    default: r_lut = r_in;
                endcase
                case (g_in)
                    6'd0: g_lut = 6'd0; 6'd1: g_lut = 6'd4; 6'd2: g_lut = 6'd7; 6'd3: g_lut = 6'd9; 
                    6'd4: g_lut = 6'd10; 6'd5: g_lut = 6'd12; 6'd6: g_lut = 6'd14; 6'd7: g_lut = 6'd15; 
                    6'd8: g_lut = 6'd16; 6'd9: g_lut = 6'd18; 6'd10: g_lut = 6'd19; 6'd11: g_lut = 6'd20; 
                    6'd12: g_lut = 6'd21; 6'd13: g_lut = 6'd23; 6'd14: g_lut = 6'd24; 6'd15: g_lut = 6'd25; 
                    6'd16: g_lut = 6'd26; 6'd17: g_lut = 6'd27; 6'd18: g_lut = 6'd28; 6'd19: g_lut = 6'd29; 
                    6'd20: g_lut = 6'd30; 6'd21: g_lut = 6'd31; 6'd22: g_lut = 6'd32; 6'd23: g_lut = 6'd33; 
                    6'd24: g_lut = 6'd34; 6'd25: g_lut = 6'd35; 6'd26: g_lut = 6'd35; 6'd27: g_lut = 6'd36; 
                    6'd28: g_lut = 6'd37; 6'd29: g_lut = 6'd38; 6'd30: g_lut = 6'd39; 6'd31: g_lut = 6'd40; 
                    6'd32: g_lut = 6'd41; 6'd33: g_lut = 6'd41; 6'd34: g_lut = 6'd42; 6'd35: g_lut = 6'd43; 
                    6'd36: g_lut = 6'd44; 6'd37: g_lut = 6'd45; 6'd38: g_lut = 6'd45; 6'd39: g_lut = 6'd46; 
                    6'd40: g_lut = 6'd47; 6'd41: g_lut = 6'd48; 6'd42: g_lut = 6'd48; 6'd43: g_lut = 6'd49; 
                    6'd44: g_lut = 6'd50; 6'd45: g_lut = 6'd51; 6'd46: g_lut = 6'd51; 6'd47: g_lut = 6'd52; 
                    6'd48: g_lut = 6'd53; 6'd49: g_lut = 6'd54; 6'd50: g_lut = 6'd54; 6'd51: g_lut = 6'd55; 
                    6'd52: g_lut = 6'd56; 6'd53: g_lut = 6'd56; 6'd54: g_lut = 6'd57; 6'd55: g_lut = 6'd58; 
                    6'd56: g_lut = 6'd58; 6'd57: g_lut = 6'd59; 6'd58: g_lut = 6'd60; 6'd59: g_lut = 6'd60; 
                    6'd60: g_lut = 6'd61; 6'd61: g_lut = 6'd62; 6'd62: g_lut = 6'd62; 6'd63: g_lut = 6'd63; 
                    default: g_lut = g_in;
                endcase
                case (b_in)
                    5'd0: b_lut = 5'd0; 5'd1: b_lut = 5'd3; 5'd2: b_lut = 5'd5; 5'd3: b_lut = 5'd7; 
                    5'd4: b_lut = 5'd8; 5'd5: b_lut = 5'd9; 5'd6: b_lut = 5'd11; 5'd7: b_lut = 5'd12; 
                    5'd8: b_lut = 5'd13; 5'd9: b_lut = 5'd14; 5'd10: b_lut = 5'd15; 5'd11: b_lut = 5'd16; 
                    5'd12: b_lut = 5'd17; 5'd13: b_lut = 5'd18; 5'd14: b_lut = 5'd18; 5'd15: b_lut = 5'd19; 
                    5'd16: b_lut = 5'd20; 5'd17: b_lut = 5'd21; 5'd18: b_lut = 5'd22; 5'd19: b_lut = 5'd23; 
                    5'd20: b_lut = 5'd23; 5'd21: b_lut = 5'd24; 5'd22: b_lut = 5'd25; 5'd23: b_lut = 5'd26; 
                    5'd24: b_lut = 5'd26; 5'd25: b_lut = 5'd27; 5'd26: b_lut = 5'd28; 5'd27: b_lut = 5'd28; 
                    5'd28: b_lut = 5'd29; 5'd29: b_lut = 5'd30; 5'd30: b_lut = 5'd30; 5'd31: b_lut = 5'd31; 
                    default: b_lut = b_in;
                endcase
            end

            // 档位 2: Gamma = 1.0 (直通)
            3'd2: begin
                r_lut = r_in; g_lut = g_in; b_lut = b_in;
            end

            // 档位 3: Gamma = 1.5 (压暗)
            3'd3: begin
                case (r_in)
                    5'd0: r_lut = 5'd0; 5'd1: r_lut = 5'd0; 5'd2: r_lut = 5'd1; 5'd3: r_lut = 5'd1; 
                    5'd4: r_lut = 5'd1; 5'd5: r_lut = 5'd2; 5'd6: r_lut = 5'd3; 5'd7: r_lut = 5'd3; 
                    5'd8: r_lut = 5'd4; 5'd9: r_lut = 5'd5; 5'd10: r_lut = 5'd6; 5'd11: r_lut = 5'd7; 
                    5'd12: r_lut = 5'd7; 5'd13: r_lut = 5'd8; 5'd14: r_lut = 5'd9; 5'd15: r_lut = 5'd10; 
                    5'd16: r_lut = 5'd11; 5'd17: r_lut = 5'd13; 5'd18: r_lut = 5'd14; 5'd19: r_lut = 5'd15; 
                    5'd20: r_lut = 5'd16; 5'd21: r_lut = 5'd17; 5'd22: r_lut = 5'd19; 5'd23: r_lut = 5'd20; 
                    5'd24: r_lut = 5'd21; 5'd25: r_lut = 5'd22; 5'd26: r_lut = 5'd24; 5'd27: r_lut = 5'd25; 
                    5'd28: r_lut = 5'd27; 5'd29: r_lut = 5'd28; 5'd30: r_lut = 5'd30; 5'd31: r_lut = 5'd31; 
                    default: r_lut = r_in;
                endcase
                case (g_in)
                    6'd0: g_lut = 6'd0; 6'd1: g_lut = 6'd0; 6'd2: g_lut = 6'd0; 6'd3: g_lut = 6'd1; 
                    6'd4: g_lut = 6'd1; 6'd5: g_lut = 6'd1; 6'd6: g_lut = 6'd2; 6'd7: g_lut = 6'd2; 
                    6'd8: g_lut = 6'd3; 6'd9: g_lut = 6'd3; 6'd10: g_lut = 6'd4; 6'd11: g_lut = 6'd5; 
                    6'd12: g_lut = 6'd5; 6'd13: g_lut = 6'd6; 6'd14: g_lut = 6'd7; 6'd15: g_lut = 6'd7; 
                    6'd16: g_lut = 6'd8; 6'd17: g_lut = 6'd9; 6'd18: g_lut = 6'd10; 6'd19: g_lut = 6'd10; 
                    6'd20: g_lut = 6'd11; 6'd21: g_lut = 6'd12; 6'd22: g_lut = 6'd13; 6'd23: g_lut = 6'd14; 
                    6'd24: g_lut = 6'd15; 6'd25: g_lut = 6'd16; 6'd26: g_lut = 6'd17; 6'd27: g_lut = 6'd18; 
                    6'd28: g_lut = 6'd19; 6'd29: g_lut = 6'd20; 6'd30: g_lut = 6'd21; 6'd31: g_lut = 6'd22; 
                    6'd32: g_lut = 6'd23; 6'd33: g_lut = 6'd24; 6'd34: g_lut = 6'd25; 6'd35: g_lut = 6'd26; 
                    6'd36: g_lut = 6'd27; 6'd37: g_lut = 6'd28; 6'd38: g_lut = 6'd30; 6'd39: g_lut = 6'd31; 
                    6'd40: g_lut = 6'd32; 6'd41: g_lut = 6'd33; 6'd42: g_lut = 6'd34; 6'd43: g_lut = 6'd36; 
                    6'd44: g_lut = 6'd37; 6'd45: g_lut = 6'd38; 6'd46: g_lut = 6'd39; 6'd47: g_lut = 6'd41; 
                    6'd48: g_lut = 6'd42; 6'd49: g_lut = 6'd43; 6'd50: g_lut = 6'd45; 6'd51: g_lut = 6'd46; 
                    6'd52: g_lut = 6'd47; 6'd53: g_lut = 6'd49; 6'd54: g_lut = 6'd50; 6'd55: g_lut = 6'd51; 
                    6'd56: g_lut = 6'd53; 6'd57: g_lut = 6'd54; 6'd58: g_lut = 6'd56; 6'd59: g_lut = 6'd57; 
                    6'd60: g_lut = 6'd59; 6'd61: g_lut = 6'd60; 6'd62: g_lut = 6'd62; 6'd63: g_lut = 6'd63; 
                    default: g_lut = g_in;
                endcase
                case (b_in)
                    5'd0: b_lut = 5'd0; 5'd1: b_lut = 5'd0; 5'd2: b_lut = 5'd1; 5'd3: b_lut = 5'd1; 
                    5'd4: b_lut = 5'd1; 5'd5: b_lut = 5'd2; 5'd6: b_lut = 5'd3; 5'd7: b_lut = 5'd3; 
                    5'd8: b_lut = 5'd4; 5'd9: b_lut = 5'd5; 5'd10: b_lut = 5'd6; 5'd11: b_lut = 5'd7; 
                    5'd12: b_lut = 5'd7; 5'd13: b_lut = 5'd8; 5'd14: b_lut = 5'd9; 5'd15: b_lut = 5'd10; 
                    5'd16: b_lut = 5'd11; 5'd17: b_lut = 5'd13; 5'd18: b_lut = 5'd14; 5'd19: b_lut = 5'd15; 
                    5'd20: b_lut = 5'd16; 5'd21: b_lut = 5'd17; 5'd22: b_lut = 5'd19; 5'd23: b_lut = 5'd20; 
                    5'd24: b_lut = 5'd21; 5'd25: b_lut = 5'd22; 5'd26: b_lut = 5'd24; 5'd27: b_lut = 5'd25; 
                    5'd28: b_lut = 5'd27; 5'd29: b_lut = 5'd28; 5'd30: b_lut = 5'd30; 5'd31: b_lut = 5'd31; 
                    default: b_lut = b_in;
                endcase
            end

            // 档位 4: Gamma = 2.0 (极度压暗)
            3'd4: begin
                case (r_in)
                    5'd0: r_lut = 5'd0; 5'd1: r_lut = 5'd0; 5'd2: r_lut = 5'd0; 5'd3: r_lut = 5'd0; 
                    5'd4: r_lut = 5'd1; 5'd5: r_lut = 5'd1; 5'd6: r_lut = 5'd1; 5'd7: r_lut = 5'd2; 
                    5'd8: r_lut = 5'd2; 5'd9: r_lut = 5'd3; 5'd10: r_lut = 5'd3; 5'd11: r_lut = 5'd4; 
                    5'd12: r_lut = 5'd5; 5'd13: r_lut = 5'd5; 5'd14: r_lut = 5'd6; 5'd15: r_lut = 5'd7; 
                    5'd16: r_lut = 5'd8; 5'd17: r_lut = 5'd9; 5'd18: r_lut = 5'd10; 5'd19: r_lut = 5'd12; 
                    5'd20: r_lut = 5'd13; 5'd21: r_lut = 5'd14; 5'd22: r_lut = 5'd16; 5'd23: r_lut = 5'd17; 
                    5'd24: r_lut = 5'd19; 5'd25: r_lut = 5'd20; 5'd26: r_lut = 5'd22; 5'd27: r_lut = 5'd24; 
                    5'd28: r_lut = 5'd25; 5'd29: r_lut = 5'd27; 5'd30: r_lut = 5'd29; 5'd31: r_lut = 5'd31; 
                    default: r_lut = r_in;
                endcase
                case (g_in)
                    6'd0: g_lut = 6'd0; 6'd1: g_lut = 6'd0; 6'd2: g_lut = 6'd0; 6'd3: g_lut = 6'd0; 
                    6'd4: g_lut = 6'd0; 6'd5: g_lut = 6'd0; 6'd6: g_lut = 6'd1; 6'd7: g_lut = 6'd1; 
                    6'd8: g_lut = 6'd1; 6'd9: g_lut = 6'd1; 6'd10: g_lut = 6'd2; 6'd11: g_lut = 6'd2; 
                    6'd12: g_lut = 6'd2; 6'd13: g_lut = 6'd3; 6'd14: g_lut = 6'd3; 6'd15: g_lut = 6'd4; 
                    6'd16: g_lut = 6'd4; 6'd17: g_lut = 6'd5; 6'd18: g_lut = 6'd5; 6'd19: g_lut = 6'd6; 
                    6'd20: g_lut = 6'd6; 6'd21: g_lut = 6'd7; 6'd22: g_lut = 6'd8; 6'd23: g_lut = 6'd8; 
                    6'd24: g_lut = 6'd9; 6'd25: g_lut = 6'd10; 6'd26: g_lut = 6'd11; 6'd27: g_lut = 6'd12; 
                    6'd28: g_lut = 6'd12; 6'd29: g_lut = 6'd13; 6'd30: g_lut = 6'd14; 6'd31: g_lut = 6'd15; 
                    6'd32: g_lut = 6'd16; 6'd33: g_lut = 6'd17; 6'd34: g_lut = 6'd18; 6'd35: g_lut = 6'd19; 
                    6'd36: g_lut = 6'd21; 6'd37: g_lut = 6'd22; 6'd38: g_lut = 6'd23; 6'd39: g_lut = 6'd24; 
                    6'd40: g_lut = 6'd25; 6'd41: g_lut = 6'd27; 6'd42: g_lut = 6'd28; 6'd43: g_lut = 6'd29; 
                    6'd44: g_lut = 6'd31; 6'd45: g_lut = 6'd32; 6'd46: g_lut = 6'd34; 6'd47: g_lut = 6'd35; 
                    6'd48: g_lut = 6'd37; 6'd49: g_lut = 6'd38; 6'd50: g_lut = 6'd40; 6'd51: g_lut = 6'd41; 
                    6'd52: g_lut = 6'd43; 6'd53: g_lut = 6'd45; 6'd54: g_lut = 6'd46; 6'd55: g_lut = 6'd48; 
                    6'd56: g_lut = 6'd50; 6'd57: g_lut = 6'd52; 6'd58: g_lut = 6'd53; 6'd59: g_lut = 6'd55; 
                    6'd60: g_lut = 6'd57; 6'd61: g_lut = 6'd59; 6'd62: g_lut = 6'd61; 6'd63: g_lut = 6'd63; 
                    default: g_lut = g_in;
                endcase
                case (b_in)
                    5'd0: b_lut = 5'd0; 5'd1: b_lut = 5'd0; 5'd2: b_lut = 5'd0; 5'd3: b_lut = 5'd0; 
                    5'd4: b_lut = 5'd1; 5'd5: b_lut = 5'd1; 5'd6: b_lut = 5'd1; 5'd7: b_lut = 5'd2; 
                    5'd8: b_lut = 5'd2; 5'd9: b_lut = 5'd3; 5'd10: b_lut = 5'd3; 5'd11: b_lut = 5'd4; 
                    5'd12: b_lut = 5'd5; 5'd13: b_lut = 5'd5; 5'd14: b_lut = 5'd6; 5'd15: b_lut = 5'd7; 
                    5'd16: b_lut = 5'd8; 5'd17: b_lut = 5'd9; 5'd18: b_lut = 5'd10; 5'd19: b_lut = 5'd12; 
                    5'd20: b_lut = 5'd13; 5'd21: b_lut = 5'd14; 5'd22: b_lut = 5'd16; 5'd23: b_lut = 5'd17; 
                    5'd24: b_lut = 5'd19; 5'd25: b_lut = 5'd20; 5'd26: b_lut = 5'd22; 5'd27: b_lut = 5'd24; 
                    5'd28: b_lut = 5'd25; 5'd29: b_lut = 5'd27; 5'd30: b_lut = 5'd29; 5'd31: b_lut = 5'd31; 
                    default: b_lut = b_in;
                endcase
            end

            default: begin
                r_lut = r_in; g_lut = g_in; b_lut = b_in;
            end
        endcase
    end

    // ---------------- 输出同步打拍 ----------------
    wire [15:0] rgb_final = {r_lut, g_lut, b_lut};

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            de_out  <= 1'b0;
            rgb_out <= 16'd0;
            x_out   <= 11'd0;
            y_out   <= 10'd0;
        end else begin
            de_out  <= de_in;
            rgb_out <= rgb_final;
            x_out   <= x_in;
            y_out   <= y_in;
        end
    end

endmodule