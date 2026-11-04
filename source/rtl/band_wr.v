// ============================================================
// band_wr: 真正的双指针乒乓 (v5)
// 写侧与读侧完全解耦，消除串行等待
// ============================================================
module band_wr (
    input  wire        clk,
    input  wire        rstn,
    // 写端口 (来自 corr_top)
    input  wire        valid_in,
    input  wire [10:0] x_in,
    input  wire [9:0]  y_in,
    input  wire [15:0] rgb_in,
    
    // 读端口 (给 HDMI)
    input  wire        rd_bank_sel, // 由 HDMI 侧给出当前想读哪个桶 (0或1)
    input  wire [14:0] rd_addr,
    output reg  [15:0] rd_data,
    input  wire        rd_done,     // 读侧读完一个 Band 的脉冲
    
    // 状态给顶层/HDMI
    output wire        band_ready_0, // Bank 0 是否写满（HDMI可读）
    output wire        band_ready_1, // Bank 1 是否写满（HDMI可读）
    output reg         band_idx      // 当前写的是哪个 Bank
);

    (* ram_style = "block" *) reg [15:0] band_mem [0:1][0:20479];

    // 写地址计算 (y % 16)*1280 + x
    wire [9:0]  y_mod16 = y_in[3:0];
    wire [14:0] y_offset = ({5'b0, y_mod16} << 10) + ({5'b0, y_mod16} << 8);
    wire [14:0] wr_addr = y_offset + x_in;

    // ---------------- 桶状态 ----------------
    reg bank_full_0, bank_full_1;
    assign band_ready_0 = bank_full_0;
    assign band_ready_1 = bank_full_1;

    // ---------------- 写逻辑 ----------------
    // 目标写桶已满就停，等 HDMI rd_done 清掉满标志；否则会覆盖未读的满桶。
    wire wr_bank_full = band_idx ? bank_full_1 : bank_full_0;
    wire wr_stall = wr_bank_full;

    wire write_en = valid_in && !wr_stall;

    always @(posedge clk) begin
        if (write_en) begin
            band_mem[band_idx][wr_addr] <= rgb_in;
        end
    end

    // ---------------- 读逻辑 (同步读) ----------------
    always @(posedge clk) begin
        rd_data <= band_mem[rd_bank_sel][rd_addr];
    end

    // ---------------- 状态机：翻转与握手 ----------------
    // 写完最后一个像素的条件
    wire wr_last_pixel = write_en && (x_in == 11'd1279) && (y_in[3:0] == 4'd15);

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            band_idx <= 0;
            bank_full_0 <= 0;
            bank_full_1 <= 0;
        end else begin
            // 1. 写侧填满了一个桶
            if (wr_last_pixel) begin
                if (band_idx == 0) bank_full_0 <= 1;
                else               bank_full_1 <= 1;
                
                band_idx <= ~band_idx; // 立刻翻转写指针，去写另一个桶
            end
            
            // 2. 读侧读完了一个桶（清除满标志）
            if (rd_done) begin
                if (rd_bank_sel == 0) bank_full_0 <= 0;
                else                  bank_full_1 <= 0;
            end
        end
    end

endmodule