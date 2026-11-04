`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// tile_reader_wide  --  DDR fetch of one window + async FIFO + pclk writer
//
// 2026-11-03 (pipelined reads, credit-controlled FIFO):
//   * command interface is now a plain valid/ready stream (ddr_rreq is a
//     level, ddr_rrdy is the engine's cmd_ready): one row command per cycle
//     is accepted while the engine has room
//   * up to MAXPEND row reads are in flight, each one is 4 x 256 bit = 64 px
//   * the issue condition is a CREDIT test, not a "FIFO used" test:
//         fifo_used + 4*pending + 4 <= FIFO_DEPTH-1
//     i.e. the beats still in flight are reserved before a new command is
//     offered.  The old version only looked at fifo_used, so 16 beats in
//     flight could land on top of a 16-beat-occupied FIFO and the write port
//     silently dropped beats (fifo_full -> no wr), shifting every following
//     row of the tile.
//   * dbg_drop counts beats that would have been dropped (sticky); it must
//     stay 0.
//////////////////////////////////////////////////////////////////////////////
module tile_reader_wide #(
    parameter ADDR_WIDTH = 28,
    parameter LINE_WORDS = 640,
    parameter MAXPEND    = 4
)(
    input               pclk,
    input               prstn,
    input               ddr_clk,
    input               ddr_rstn,

    input               start,
    input  [11:0]       win_x0,
    input  [11:0]       win_y0,
    input  [5:0]        win_h,
    input               frame_idx,

    output wire         ddr_rreq,
    output [ADDR_WIDTH-1:0] ddr_raddr,
    output [31:0]       ddr_rd_len,
    input               ddr_rrdy,
    input               ddr_rdone,
    input  [255:0]      ddr_rdata,
    input               ddr_rdata_en,

    output              fill_we,
    output [5:0]        fill_row,
    output [2:0]        fill_col8,
    output [127:0]      fill_data,
    output reg          fill_done,
    output              busy,
    output wire [1:0]   dbg_dst,
    output wire         dbg_fill_done,
    output wire [7:0]   dbg_drop
);

    // 4 beats of 256 bit = 64 pixels per row
    assign ddr_rd_len = 32'd4;

    localparam FIFO_DEPTH = 32;
    localparam BEATS_CMD  = 4;
    localparam [2:0] PEND_MAX = MAXPEND;

    //==================================================================
    // pclk -> ddr start/origin CDC
    //==================================================================
    reg        start_tog;
    reg [2:0]  start_sync;
    reg [11:0] x0_s1, x0_s2, y0_s1, y0_s2;
    reg [5:0]  h_s1, h_s2;
    reg        frm_s1, frm_s2;

    always @(posedge pclk or negedge prstn) begin
        if (!prstn) start_tog <= 1'b0;
        else if (start) start_tog <= ~start_tog;
    end

    always @(posedge ddr_clk or negedge ddr_rstn) begin
        if (!ddr_rstn) begin
            start_sync <= 3'd0;
            x0_s1 <= 12'd0; x0_s2 <= 12'd0;
            y0_s1 <= 12'd0; y0_s2 <= 12'd0;
            h_s1  <= 6'd16; h_s2  <= 6'd16;
            frm_s1 <= 1'b0; frm_s2 <= 1'b0;
        end
        else begin
            start_sync <= {start_sync[1:0], start_tog};
            x0_s1 <= win_x0; x0_s2 <= x0_s1;
            y0_s1 <= win_y0; y0_s2 <= y0_s1;
            h_s1  <= win_h;  h_s2  <= h_s1;
            frm_s1 <= frame_idx; frm_s2 <= frm_s1;
        end
    end

    //==================================================================
    // async FIFO: 32 x 256 bit, write ddr_clk / read pclk
    //==================================================================
    reg [255:0] mem [0:FIFO_DEPTH-1];
    reg [4:0]   wbin, rbin;
    reg [5:0]   wgray, rgray;
    reg [5:0]   rgray_s1, rgray_s2;
    reg [5:0]   wgray_s1, wgray_s2;
    reg [4:0]   rbin_s1, rbin_s2;

    wire [4:0] wbin_nxt = wbin + 5'd1;
    wire [5:0] wgray_nxt = (wbin_nxt >> 1) ^ wbin_nxt;
    wire [4:0] rbin_nxt = rbin + 5'd1;
    wire [5:0] rgray_nxt = (rbin_nxt >> 1) ^ rbin_nxt;

    wire fifo_full  = (wgray_nxt == {~rgray_s2[5:4], rgray_s2[3:0]});
    wire fifo_empty = (rgray == wgray_s2);

    wire         fifo_wr    = ddr_rdata_en && !fifo_full;
    wire         fifo_ovf   = ddr_rdata_en &&  fifo_full;   // must never happen
    wire [255:0] fifo_rdata = mem[rbin];

    wire        fifo_rd;
    wire [4:0]  fifo_used = wbin - rbin_s2;

    always @(posedge ddr_clk or negedge ddr_rstn) begin
        if (!ddr_rstn) begin
            wbin <= 5'd0; wgray <= 6'd0;
            rgray_s1 <= 6'd0; rgray_s2 <= 6'd0;
            rbin_s1 <= 5'd0; rbin_s2 <= 5'd0;
        end
        else begin
            rgray_s1 <= rgray; rgray_s2 <= rgray_s1;
            rbin_s1 <= rbin; rbin_s2 <= rbin_s1;
            if (fifo_wr) begin
                mem[wbin] <= ddr_rdata;
                wbin  <= wbin_nxt;
                wgray <= wgray_nxt;
            end
        end
    end

    always @(posedge pclk or negedge prstn) begin
        if (!prstn) begin
            rbin <= 5'd0; rgray <= 6'd0;
            wgray_s1 <= 6'd0; wgray_s2 <= 6'd0;
        end
        else begin
            wgray_s1 <= wgray; wgray_s2 <= wgray_s1;
            if (fifo_rd && !fifo_empty) begin
                rbin  <= rbin_nxt;
                rgray <= rgray_nxt;
            end
        end
    end

    // sticky overflow counter (debug only)
    reg [7:0] drop_cnt;
    always @(posedge ddr_clk or negedge ddr_rstn) begin
        if (!ddr_rstn) drop_cnt <= 8'd0;
        else if (fifo_ovf && drop_cnt != 8'hFF) drop_cnt <= drop_cnt + 8'd1;
    end
    assign dbg_drop = drop_cnt;

    //==================================================================
    // ddr fetch: pipelined row reads, win_h rows x 4 beats
    //
    // credit: every command that is still in flight will deliver BEATS_CMD
    // beats, and those beats are NOT yet visible in fifo_used.  Reserving
    // them up front is what keeps the write port away from fifo_full.
    //==================================================================
    reg        active;
    reg [5:0]  row_iss, row_rec;
    reg [2:0]  pending;
    reg [11:0] x0_l, y0_l;
    reg [5:0]  h_l;
    reg        frm_l;
    reg        start_seen;

    wire [5:0]  h_last = (h_l == 6'd0) ? 6'd0 : (h_l - 6'd1);
    wire [11:0] y_row  = y0_l + {6'd0, row_iss};
    wire [21:0] line_base = y_row * LINE_WORDS;
    wire [21:0] word_addr = line_base + {16'd0, x0_l[11:1]};

    // worst-case occupancy after the new command's beats have landed
    wire [6:0] occ_after = {2'b00, fifo_used} + {2'b00, pending, 2'b00} + 7'd4;
    wire       credit_ok = (occ_after <= (FIFO_DEPTH - 1));

    wire offer   = active && (row_iss <= h_last) && (pending != PEND_MAX) && credit_ok;
    wire acc_now = offer && ddr_rrdy;
    wire rec_ok  = active && ddr_rdone;
    wire [2:0] pend_nxt = pending + (acc_now ? 3'd1 : 3'd0) - (rec_ok ? 3'd1 : 3'd0);
    wire rec_last = rec_ok && (row_rec == h_last);

    assign ddr_rreq  = offer;
    assign ddr_raddr = {{(ADDR_WIDTH-23){1'b0}}, frm_l, word_addr};
    assign dbg_dst   = active ? 2'd1 : 2'd0;

    always @(posedge ddr_clk or negedge ddr_rstn) begin
        if (!ddr_rstn) begin
            active     <= 1'b0;
            row_iss    <= 6'd0;
            row_rec    <= 6'd0;
            pending    <= 3'd0;
            x0_l       <= 12'd0;
            y0_l       <= 12'd0;
            h_l        <= 6'd40;
            frm_l      <= 1'b0;
            start_seen <= 1'b0;
        end
        else begin
            if (!active) begin
                if (start_sync[2] != start_seen) begin
                    x0_l       <= x0_s2;
                    y0_l       <= y0_s2;
                    h_l        <= (h_s2 == 6'd0) ? 6'd1 : h_s2;
                    frm_l      <= frm_s2;
                    row_iss    <= 6'd0;
                    row_rec    <= 6'd0;
                    pending    <= 3'd0;
                    start_seen <= start_sync[2];
                    active     <= 1'b1;
                end
            end
            else begin
                if (acc_now) row_iss <= row_iss + 6'd1;
                if (rec_ok) begin
                    row_rec <= row_rec + 6'd1;
                    if (rec_last) active <= 1'b0;
                end
                pending <= pend_nxt;
            end
        end
    end

    //==================================================================
    // pclk window writer: pop 4 beats, write 8 x 128bit groups per row
    //==================================================================
    localparam P_IDLE = 2'd0;
    localparam P_BEAT = 2'd1;
    localparam P_WR   = 2'd2;

    reg [1:0]   pst;
    reg [5:0]   prow;
    reg [2:0]   pbeat;
    reg [2:0]   pcol;
    reg [255:0] rb0, rb1, rb2, rb3;
    reg [5:0]   h_p;
    reg         run;

    assign fifo_rd = (pst == P_BEAT) && !fifo_empty;
    assign busy    = run;

    // 4 beats = 1024 bit = 64 pixels; one 128-bit group per fill_col8 step
    wire [1023:0] pixstream = {rb3, rb2, rb1, rb0};
    assign fill_we   = (pst == P_WR);
    assign fill_row  = prow;
    assign fill_col8 = pcol;
    assign fill_data = pixstream >> ({5'd0, pcol, 7'd0});

    always @(posedge pclk or negedge prstn) begin
        if (!prstn) begin
            pst       <= P_IDLE;
            prow      <= 6'd0;
            pbeat     <= 3'd0;
            pcol      <= 3'd0;
            rb0       <= 256'd0;
            rb1       <= 256'd0;
            rb2       <= 256'd0;
            rb3       <= 256'd0;
            h_p       <= 6'd40;
            run       <= 1'b0;
            fill_done <= 1'b0;
        end
        else begin
            fill_done <= 1'b0;

            case (pst)
                P_IDLE: begin
                    if (start) begin
                        prow  <= 6'd0;
                        pbeat <= 3'd0;
                        pcol  <= 3'd0;
                        h_p   <= (win_h == 6'd0) ? 6'd1 : win_h;
                        run   <= 1'b1;
                        pst   <= P_BEAT;
                    end
                end

                P_BEAT: begin
                    if (!fifo_empty) begin
                        case (pbeat)
                            3'd0: rb0 <= fifo_rdata;
                            3'd1: rb1 <= fifo_rdata;
                            3'd2: rb2 <= fifo_rdata;
                            default: rb3 <= fifo_rdata;
                        endcase
                        pbeat   <= pbeat + 3'd1;
                        if (pbeat == 3'd3) begin
                            pcol <= 3'd0;
                            pst  <= P_WR;
                        end
                    end
                end

                P_WR: begin
                    if (pcol == 3'd7) begin
                        if (prow == h_p - 6'd1) begin
                            fill_done <= 1'b1;
                            run       <= 1'b0;
                            pst       <= P_IDLE;
                        end
                        else begin
                            prow  <= prow + 6'd1;
                            pbeat <= 3'd0;
                            pst   <= P_BEAT;
                        end
                    end
                    else pcol <= pcol + 3'd1;
                end

                default: pst <= P_IDLE;
            endcase
        end
    end

    assign dbg_fill_done = fill_done;

endmodule
