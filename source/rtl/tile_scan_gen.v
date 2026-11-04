// ============================================================
// tile_scan_gen: 生成 Tile 顺序的 (u, v)  [方案 B']
// 每 tile 32x16 = 512 像素，共 40x45 = 1800 个 tile
//   u = tx*32 + (cnt & 31)
//   v = ty*16 + (cnt >> 5)
// ============================================================
module tile_scan_gen (
    input  wire        clk,
    input  wire        rstn,
    input  wire        enable,
    // 输出给 corr_top 的 u/v 和 de
    output reg  [11:0] u_out,
    output reg  [11:0] v_out,
    output reg         de_out,
    // 输出给窗口引擎的控制信号
    output reg  [5:0]  tile_tx, // 0~39
    output reg  [5:0]  tile_ty, // 0~44
    output reg         tile_start // 换 tile 时拉高 1 拍
);

    reg [8:0] pix_cnt; // 0~511

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            u_out <= 0; v_out <= 0; de_out <= 0;
            tile_tx <= 0; tile_ty <= 0; tile_start <= 0;
            pix_cnt <= 0;
        end else if (enable) begin
            de_out <= 1;

            // 32x16 tile 内按行扫描：先 32 列，再下一行
            u_out <= (tile_tx << 5) + {7'd0, pix_cnt[4:0]};
            v_out <= (tile_ty << 4) + {5'd0, pix_cnt[8:5]};

            if (pix_cnt == 9'd511) begin
                pix_cnt <= 0;
                tile_start <= 1; // 开始下一个 tile

                if (tile_tx == 6'd39) begin
                    tile_tx <= 0;
                    if (tile_ty == 6'd44)
                        tile_ty <= 0;
                    else
                        tile_ty <= tile_ty + 1'b1;
                end else begin
                    tile_tx <= tile_tx + 1'b1;
                end
            end else begin
                pix_cnt <= pix_cnt + 1'b1;
                tile_start <= 0;
            end
        end else begin
            de_out <= 0;
            tile_start <= 0;
        end
    end
endmodule
