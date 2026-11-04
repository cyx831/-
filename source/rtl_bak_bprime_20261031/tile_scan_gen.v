// ============================================================
// tile_scan_gen: 生成 Tile 顺序的 (u, v)
// 输出 16x16 的 tile 像素流，扫完 80x45 个 tile
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
    output reg  [6:0]  tile_tx, // 0~79
    output reg  [5:0]  tile_ty, // 0~44
    output reg         tile_start // 换 tile 时拉高 1 拍
);

    reg [7:0] pix_cnt; // 0~255

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            u_out <= 0; v_out <= 0; de_out <= 0;
            tile_tx <= 0; tile_ty <= 0; tile_start <= 0;
            pix_cnt <= 0;
        end else if (enable) begin
            de_out <= 1;
            
            // 16x16 tile 内按列/行扫描
            u_out <= (tile_tx << 4) + (pix_cnt & 15);
            v_out <= (tile_ty << 4) + (pix_cnt >> 4);

            if (pix_cnt == 8'd255) begin
                pix_cnt <= 0;
                tile_start <= 1; // 告诉成员3：开始下一个 tile
                
                if (tile_tx == 7'd79) begin
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