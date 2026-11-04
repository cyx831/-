`timescale 1ns / 1ps
////////////////////////////////////////////////////////////////////////////////
// win_engine_wide  --  ping-pong window, 8 true-dual-port BRAMs   [方案 B']
// 修复：传入 rotate_mode，修正 bbox_rom 延迟一拍读取的问题
////////////////////////////////////////////////////////////////////////////////
module win_engine_wide #(
    parameter TILES = 1800,
    parameter TILE  = 32,
    parameter WIN   = 64
)(
    input               pclk,
    input               rstn,
    input               frame_start,
    input               fill_start,
    input               start,
    input  wire [1:0]   rotate_mode,    // 【修复】新增：当前旋转模式

    output [11:0]       tile_idx,
    output [11:0]       win_x0,
    output [11:0]       win_y0,
    output [11:0]       next_win_x0,
    output [11:0]       next_win_y0,
    output [5:0]        next_win_h,     // rows this window really needs
    output              next_tile_valid,
    output reg          win_ready,
    output reg          next_ready,
    output wire         tr_start_d1,    // 【修复】新增：打一拍给 tile_reader_wide 用

    input               fill_we,
    input      [5:0]    fill_row,
    input      [2:0]    fill_col8,
    input      [127:0]  fill_data,
    input               fill_done,

    input      [11:0]   src_x,
    input      [11:0]   src_y,
    output wire [63:0]  row0_pair,
    output wire [63:0]  row1_pair,
    output reg          win_valid
);

    //------------------------------------------------------------------
    // control (ping-pong)
    //------------------------------------------------------------------
    reg [11:0] fill_idx;
    reg [11:0] fill_x0, fill_y0;
    reg [11:0] filled_x0, filled_y0;
    reg        wr_bank, rd_bank, filled_bank;
    reg [11:0] cur_x0, cur_y0;

    assign tile_idx = fill_idx;
    assign win_x0   = cur_x0;
    assign win_y0   = cur_y0;

    wire [11:0] bx0, by0;
    wire [5:0]  bh;
    wire        bvalid;

    // 【修复】例化 bbox_rom，把 rotate_mode 接进去，去掉不存在的参数
    bbox_rom u_bbox_rom (
        .clk        (pclk),
        .rotate_mode(rotate_mode),
        .tile_idx   (fill_idx),
        .win_x0     (bx0),
        .win_y0     (by0),
        .win_h      (bh),
        .tile_valid (bvalid)
    );

    assign next_win_x0     = bx0;
    assign next_win_y0     = by0;
    assign next_win_h      = bh;
    assign next_tile_valid = bvalid;

    // 【修复】把 fill_start 打一拍，此时 bbox_rom 的数据才是当前 tile 的
    reg tr_start_d1_r;
    always @(posedge pclk or negedge rstn) begin
        if (!rstn) tr_start_d1_r <= 1'b0;
        else       tr_start_d1_r <= fill_start;
    end
    assign tr_start_d1 = tr_start_d1_r;

    always @(posedge pclk) begin
        if (!rstn || frame_start) begin
            fill_idx    <= 12'd0;
            fill_x0     <= 12'd0;
            fill_y0     <= 12'd0;
            filled_x0   <= 12'd0;
            filled_y0   <= 12'd0;
            wr_bank     <= 1'b0;
            rd_bank     <= 1'b0;
            filled_bank <= 1'b0;
            cur_x0      <= 12'd0;
            cur_y0      <= 12'd0;
            win_ready   <= 1'b0;
            next_ready  <= 1'b0;
        end
        else begin
            // 【修复】用打一拍的信号采 bbox，保证采到的是当前 tile 的坐标
            if (tr_start_d1_r) begin
                fill_x0 <= bx0;
                fill_y0 <= by0;
            end
            if (fill_start) begin
                fill_idx <= (fill_idx == TILES-1) ? 12'd0 : fill_idx + 12'd1;
            end
            if (fill_done) begin
                filled_x0   <= fill_x0;
                filled_y0   <= fill_y0;
                filled_bank <= wr_bank;
                wr_bank     <= ~wr_bank;
                next_ready  <= 1'b1;
            end
            if (start) begin
                cur_x0     <= filled_x0;
                cur_y0     <= filled_y0;
                rd_bank    <= filled_bank;
                win_ready  <= 1'b1;
                next_ready <= 1'b0;
            end
        end
    end

    //------------------------------------------------------------------
    // 8 x (512 x 32) window bank, 64 x 40
    //------------------------------------------------------------------
    reg [31:0] b0 [0:511];
    reg [31:0] b1 [0:511];
    reg [31:0] b2 [0:511];
    reg [31:0] b3 [0:511];
    reg [31:0] b4 [0:511];
    reg [31:0] b5 [0:511];
    reg [31:0] b6 [0:511];
    reg [31:0] b7 [0:511];

    wire [8:0] waddr = {wr_bank, fill_row[5:1], fill_col8};

    always @(posedge pclk) if (fill_we && !fill_row[0]) begin
        b0[waddr] <= fill_data[ 31: 0];
        b1[waddr] <= fill_data[ 63:32];
        b2[waddr] <= fill_data[ 95:64];
        b3[waddr] <= fill_data[127:96];
    end
    always @(posedge pclk) if (fill_we && fill_row[0]) begin
        b4[waddr] <= fill_data[ 31: 0];
        b5[waddr] <= fill_data[ 63:32];
        b6[waddr] <= fill_data[ 95:64];
        b7[waddr] <= fill_data[127:96];
    end

    //------------------------------------------------------------------
    // read side: 4 words / cycle (保持不变)
    //------------------------------------------------------------------
    reg [11:0] sx_d1, sy_d1, sx_d2, sy_d2;
    reg        ready_d1, ready_d2;

    always @(posedge pclk) begin
        sx_d1    <= src_x;
        sy_d1    <= src_y;
        ready_d1 <= win_ready;
        sx_d2    <= sx_d1;
        sy_d2    <= sy_d1;
        ready_d2 <= ready_d1;
    end

    wire [5:0] k    = sx_d1[5:1];
    wire [5:0] k1   = k + 6'd1;
    wire [5:0] r1y  = sy_d1[5:0] + 6'd1;
    wire       k_ok = (k != 6'd31);
    wire       r_ok = (sy_d1 < 12'd39);

    wire [2:0] g0 = sy_d1[0] ? 3'd4 : 3'd0;
    wire [2:0] g1 = sy_d1[0] ? 3'd0 : 3'd4;

    wire [2:0] sA = g0 + {1'b0, k[1:0]};
    wire [2:0] sB = g0 + {1'b0, k1[1:0]};
    wire [2:0] sC = g1 + {1'b0, k[1:0]};
    wire [2:0] sD = g1 + {1'b0, k1[1:0]};

    wire [8:0] addrA = {rd_bank, sy_d1[5:1], k[4:2]};
    wire [8:0] addrB = {rd_bank, sy_d1[5:1], k1[4:2]};
    wire [8:0] addrC = {rd_bank, r1y[5:1],  k[4:2]};
    wire [8:0] addrD = {rd_bank, r1y[5:1],  k1[4:2]};

    reg [8:0] ra0, ra1, ra2, ra3, ra4, ra5, ra6, ra7;
    always @(posedge pclk) begin
        ra0 <= (sA==3'd0) ? addrA : (sB==3'd0) ? addrB : (sC==3'd0) ? addrC : (sD==3'd0) ? addrD : 9'd0;
        ra1 <= (sA==3'd1) ? addrA : (sB==3'd1) ? addrB : (sC==3'd1) ? addrC : (sD==3'd1) ? addrD : 9'd0;
        ra2 <= (sA==3'd2) ? addrA : (sB==3'd2) ? addrB : (sC==3'd2) ? addrC : (sD==3'd2) ? addrD : 9'd0;
        ra3 <= (sA==3'd3) ? addrA : (sB==3'd3) ? addrB : (sC==3'd3) ? addrC : (sD==3'd3) ? addrD : 9'd0;
        ra4 <= (sA==3'd4) ? addrA : (sB==3'd4) ? addrB : (sC==3'd4) ? addrC : (sD==3'd4) ? addrD : 9'd0;
        ra5 <= (sA==3'd5) ? addrA : (sB==3'd5) ? addrB : (sC==3'd5) ? addrC : (sD==3'd5) ? addrD : 9'd0;
        ra6 <= (sA==3'd6) ? addrA : (sB==3'd6) ? addrB : (sC==3'd6) ? addrC : (sD==3'd6) ? addrD : 9'd0;
        ra7 <= (sA==3'd7) ? addrA : (sB==3'd7) ? addrB : (sC==3'd7) ? addrC : (sD==3'd7) ? addrD : 9'd0;
    end

    reg [31:0] q0, q1, q2, q3, q4, q5, q6, q7;
    always @(posedge pclk) begin
        q0 <= b0[ra0];
        q1 <= b1[ra1];
        q2 <= b2[ra2];
        q3 <= b3[ra3];
        q4 <= b4[ra4];
        q5 <= b5[ra5];
        q6 <= b6[ra6];
        q7 <= b7[ra7];
    end

    reg [2:0] sA_d, sB_d, sC_d, sD_d;
    reg [2:0] sA_d2, sB_d2, sC_d2, sD_d2;
    reg       kB_d, rD_d, kB_d2, rD_d2;
    always @(posedge pclk) begin
        sA_d <= sA; sB_d <= sB; sC_d <= sC; sD_d <= sD;
        kB_d <= k_ok; rD_d <= r_ok;
        sA_d2 <= sA_d; sB_d2 <= sB_d; sC_d2 <= sC_d; sD_d2 <= sD_d;
        kB_d2 <= kB_d; rD_d2 <= rD_d;
    end

    wire [255:0] qbus = {q7, q6, q5, q4, q3, q2, q1, q0};

    wire [31:0] dA = qbus[{sA_d2, 5'b00000} +: 32];
    wire [31:0] dB = kB_d2 ? qbus[{sB_d2, 5'b00000} +: 32] : 32'd0;
    wire [31:0] dC = rD_d2 ? qbus[{sC_d2, 5'b00000} +: 32] : 32'd0;
    wire [31:0] dD = (rD_d2 && kB_d2) ? qbus[{sD_d2, 5'b00000} +: 32] : 32'd0;

    assign row0_pair = {dB, dA};
    assign row1_pair = {dD, dC};

    always @(posedge pclk) begin
        if (!rstn) win_valid <= 1'b0;
        else       win_valid <= ready_d2 && (sx_d2 < 12'd64) && (sy_d2 < 12'd40);
    end

endmodule