`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// tile_reader_wide (ddr-clock fetch + async FIFO + pclk window writer)
//
// The old pclk-side row handshake (~12 pclk/row) is the throughput bottleneck.
// This version:
//   1. fetch FSM runs in ddr_clk and drives ddr_* directly (no pclk CDC per row)
//   2. 3 x 256-bit beats/row are pushed into a 32-deep async FIFO
//   3. pclk side pops 3 beats (3 cycles) and writes 4 x 128-bit groups (4 cycles)
//
// pclk cost per row ~7-8 cycles -> 32 rows ~224-256 pclk (target for 30 fps).
//////////////////////////////////////////////////////////////////////////////////
module tile_reader_wide #(
    parameter ADDR_WIDTH = 28,
    parameter LINE_WORDS = 640
)(
    input               pclk,
    input               prstn,
    input               ddr_clk,
    input               ddr_rstn,

    input               start,
    input  [11:0]       win_x0,
    input  [11:0]       win_y0,
    input               frame_idx,

    output reg          ddr_rreq,
    output [ADDR_WIDTH-1:0] ddr_raddr,
    output [31:0]       ddr_rd_len,
    input               ddr_rrdy,
    input               ddr_rdone,
    input  [255:0]      ddr_rdata,
    input               ddr_rdata_en,

    output              fill_we,
    output [4:0]        fill_row,
    output [1:0]        fill_col8,
    output [127:0]      fill_data,
    output reg          fill_done,
    output              busy,
    output wire [1:0]   dbg_dst,
    output wire         dbg_fill_done
);

    // rd_cmd_len is the number of 256-bit beats: 48 pixels/row = 3 beats.
    // (wr_cmd_trans maps len=3 -> arlen=2, i.e. exactly 3 beats)
    assign ddr_rd_len = 32'd3;

    //==================================================================
    // pclk -> ddr start/origin CDC
    //==================================================================
    reg        start_tog;
    reg [2:0]  start_sync;
    reg [11:0] x0_s1, x0_s2, y0_s1, y0_s2;
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
            frm_s1 <= 1'b0; frm_s2 <= 1'b0;
        end
        else begin
            start_sync <= {start_sync[1:0], start_tog};
            x0_s1 <= win_x0; x0_s2 <= x0_s1;
            y0_s1 <= win_y0; y0_s2 <= y0_s1;
            frm_s1 <= frame_idx; frm_s2 <= frm_s1;
        end
    end

    //==================================================================
    // async FIFO: 32 x 256 bit, write ddr_clk / read pclk
    //==================================================================
    reg [255:0] mem [0:31];
    reg [4:0]   wbin, rbin;
    reg [5:0]   wgray, rgray;
    reg [5:0]   rgray_s1, rgray_s2;   // read ptr -> ddr
    reg [5:0]   wgray_s1, wgray_s2;   // write ptr -> pclk
    reg [4:0]   rbin_s1, rbin_s2;     // read ptr binary -> ddr (credit)

    wire [4:0] wbin_nxt = wbin + 5'd1;
    wire [5:0] wgray_nxt = (wbin_nxt >> 1) ^ wbin_nxt;
    wire [4:0] rbin_nxt = rbin + 5'd1;
    wire [5:0] rgray_nxt = (rbin_nxt >> 1) ^ rbin_nxt;

    wire fifo_full  = (wgray_nxt == {~rgray_s2[5:4], rgray_s2[3:0]});
    wire fifo_empty = (rgray == wgray_s2);

    wire        fifo_wr = ddr_rdata_en && !fifo_full;
    wire [255:0] fifo_rdata = mem[rbin];
    wire        fifo_rd;

    wire [4:0] fifo_used = wbin - rbin_s2;

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

    //==================================================================
    // ddr fetch FSM: 32 rows x 3 beats
    //==================================================================
    localparam D_IDLE  = 2'd0;
    localparam D_ISSUE = 2'd1;
    localparam D_DATA  = 2'd2;
    localparam D_DONE  = 2'd3;

    reg [1:0]  dst;
    reg [4:0]  drow;
    reg        start_seen;
    reg [11:0] x0_l, y0_l;
    reg        frm_l;

    wire [11:0] y_row = y0_l + {7'd0, drow};
    wire [21:0] line_base = y_row * LINE_WORDS;
    wire [21:0] word_addr = line_base + {16'd0, x0_l[11:1]};

    // wr_buf packs the frame buffer as {frame, 19-bit word offset} (2 MB/frame),
    // so the frame select bit sits at bit 19, not bit 22.
    assign ddr_raddr = {{(ADDR_WIDTH-20){1'b0}}, frm_l, word_addr[18:0]};

    always @(posedge ddr_clk or negedge ddr_rstn) begin
        if (!ddr_rstn) begin
            dst        <= D_IDLE;
            ddr_rreq   <= 1'b0;
            drow       <= 5'd0;
            start_seen <= 1'b0;
            x0_l       <= 12'd0;
            y0_l       <= 12'd0;
            frm_l      <= 1'b0;
        end
        else begin
            case (dst)
                D_IDLE: begin
                    ddr_rreq <= 1'b0;
                    if (start_sync[2] != start_seen) begin
                        x0_l       <= {x0_s2[11:4], 4'b0000};
                        y0_l       <= y0_s2;
                        frm_l      <= frm_s2;
                        drow       <= 5'd0;
                        start_seen <= start_sync[2];
                        dst        <= D_ISSUE;
                    end
                end

                D_ISSUE: begin
                    // wr_cmd_trans captures rd_cmd_en on a rising edge WITHOUT
                    // looking at rd_cmd_ready, and rd_cmd_ready is restored only
                    // by the rd_done_p edge.  Raising the request while the
                    // channel is busy therefore swallows that edge and deadlocks
                    // the read channel.  Only request when ready is high.
                    if (fifo_used <= 5'd28 && ddr_rrdy) begin
                        ddr_rreq <= 1'b1;
                        dst      <= D_DATA;
                    end
                end

                D_DATA: begin
                    ddr_rreq <= 1'b0;
                    if (ddr_rdone) begin
                        if (drow == 5'd31)
                            dst <= D_DONE;
                        else begin
                            drow <= drow + 5'd1;
                            dst  <= D_ISSUE;
                        end
                    end
                end

                D_DONE: begin
                    ddr_rreq <= 1'b0;
                    dst      <= D_IDLE;   // allow next tile's start
                end

                default: dst <= D_IDLE;
            endcase
        end
    end

    //==================================================================
    // pclk window writer: pop 3 beats, write 4 x 128bit groups
    //==================================================================
    localparam P_IDLE = 2'd0;
    localparam P_BEAT = 2'd1;
    localparam P_WR   = 2'd2;

    reg [1:0]   pst;
    assign fifo_rd = (pst == P_BEAT) && !fifo_empty;
    reg [4:0]   prow;
    reg [1:0]   pbeat;
    reg [1:0]   pcol;
    reg [255:0] rb0, rb1, rb2;
    reg [3:0]   off_l;
    reg         run;

    assign busy    = run;

    wire [767:0] pixstream = {rb2, rb1, rb0};
    wire [5:0]   sidx = {2'b0, off_l} + {1'b0, pcol, 3'b000};

    assign fill_we   = (pst == P_WR);
    assign fill_row  = prow;
    assign fill_col8 = pcol;
    assign fill_data = pixstream >> (sidx * 16);

    always @(posedge pclk or negedge prstn) begin
        if (!prstn) begin
            pst       <= P_IDLE;
            prow      <= 5'd0;
            pbeat     <= 2'd0;
            pcol      <= 2'd0;
            rb0       <= 256'd0;
            rb1       <= 256'd0;
            rb2       <= 256'd0;
            off_l     <= 4'd0;
            run       <= 1'b0;
            fill_done <= 1'b0;
        end
        else begin
            fill_done <= 1'b0;

            case (pst)
                P_IDLE: begin
                    if (start) begin
                        prow  <= 5'd0;
                        pbeat <= 2'd0;
                        pcol  <= 2'd0;
                        off_l <= win_x0[3:0];
                        run   <= 1'b1;
                        pst   <= P_BEAT;
                    end
                end

                P_BEAT: begin
                    if (!fifo_empty) begin
                        case (pbeat)
                            2'd0: rb0 <= fifo_rdata;
                            2'd1: rb1 <= fifo_rdata;
                            default: rb2 <= fifo_rdata;
                        endcase
                        pbeat   <= pbeat + 2'd1;
                        if (pbeat == 2'd2) begin
                            pcol <= 2'd0;
                            pst  <= P_WR;
                        end
                    end
                end

                P_WR: begin
                    if (pcol == 2'd3) begin
                        if (prow == 5'd31) begin
                            fill_done <= 1'b1;
                            run       <= 1'b0;
                            pst       <= P_IDLE;
                        end
                        else begin
                            prow  <= prow + 5'd1;
                            pbeat <= 2'd0;
                            pst   <= P_BEAT;
                        end
                    end
                    else pcol <= pcol + 2'd1;
                end

                default: pst <= P_IDLE;
            endcase
        end
    end

assign dbg_dst       = dst;
    assign dbg_fill_done = fill_done;

endmodule
