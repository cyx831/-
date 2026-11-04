`timescale 1ns / 1ps
////////////////////////////////////////////////////////////////////////////////
// fisheye_video_top (single-buffer win_engine)  [plan B']
//
//   32x16 output tiles, 40x45 = 1800 tiles, 64x40 source window
//
//   INIT    : wait bbox valid, start fill tile 0
//   PREFILL : wait win_engine fill_done
//   WAIT2   : 2 pclk, then enable tile scan
//   RUN     : 512 pixels
//   DRAIN   : back to PREFILL, start reader for the next tile
//
// band_wr v5: separate band_ready_0/1; HDMI gives rd_bank_sel/rd_addr/rd_done.
//
// 2026-11-03: rotate_mode_active is declared BEFORE it is used (implicit 1-bit
//             net used to be created by the port connections, which made the
//             later "reg" declaration illegal and left the bbox/rotate mux
//             undriven).  File rewritten ASCII-only.
////////////////////////////////////////////////////////////////////////////////
module fisheye_video_top (
    input  wire        pclk,
    input  wire        rstn,

    input  wire        ddr_clk,
    input  wire        ddr_rstn,
    output wire        ddr_rreq,
    output wire [27:0] ddr_raddr,
    output wire [31:0] ddr_rd_len,
    input  wire        ddr_rrdy,
    input  wire        ddr_rdone,
    input  wire [255:0] ddr_rdata,
    input  wire        ddr_rdata_en,

    input  wire        frame_idx,
    input  wire        disp_vs,
    input  wire [1:0]  rotate_mode_rx,

    input  wire        rd_bank_sel,
    input  wire [14:0] rd_addr,
    output wire [15:0] rd_data,
    input  wire        rd_done,
    output wire        band_ready_0,
    output wire        band_ready_1,
    output wire        band_idx,

    output wire [11:0] win_x0,
    output wire [11:0] win_y0,
    output wire [11:0] tile_idx,
    output wire        win_ready,
    output wire        dbg_next_tile_valid,
    output wire        dbg_next_ready,
    output wire [1:0]  dbg_tile_dst,
    output wire        dbg_fill_done
);

    //------------------------------------------------------------------
    // rotate mode latch (declared first: it is used by the instantiations)
    //------------------------------------------------------------------
    reg [1:0] mode_sync1, mode_sync2;
    always @(posedge pclk or negedge rstn) begin
        if (!rstn) begin
            mode_sync1 <= 2'b00;
            mode_sync2 <= 2'b00;
        end else begin
            mode_sync1 <= rotate_mode_rx;
            mode_sync2 <= mode_sync1;
        end
    end
    wire [1:0] safe_mode = (mode_sync2 == 2'b11) ? 2'b00 : mode_sync2;

    reg        disp_d;
    always @(posedge pclk or negedge rstn) begin
        if (!rstn) disp_d <= 1'b0;
        else       disp_d <= disp_vs;
    end
    wire disp_edge = disp_vs & ~disp_d;

    reg [1:0] rotate_mode_active;
    always @(posedge pclk or negedge rstn) begin
        if (!rstn) rotate_mode_active <= 2'b00;
        else if (disp_edge) rotate_mode_active <= safe_mode;
    end

    // one-cycle pulse on the frame where a new angle takes effect, used by the
    // adaptive gamma to fall back to the normal level on an angle switch
    wire mode_changed = disp_edge & (safe_mode != rotate_mode_active);

    //------------------------------------------------------------------
    // tile scan
    //------------------------------------------------------------------
    reg         enable;
    wire [11:0] u, v;
    wire        de_tile;
    wire [5:0]  tile_tx;
    wire [5:0]  tile_ty;
    wire        tile_start;

    tile_scan_gen u_scan (
        .clk(pclk), .rstn(rstn), .enable(enable),
        .u_out(u), .v_out(v), .de_out(de_tile),
        .tile_tx(tile_tx), .tile_ty(tile_ty), .tile_start(tile_start)
    );

    //------------------------------------------------------------------
    // window engine
    //------------------------------------------------------------------
    wire        fill_we;
    wire [5:0]  fill_row;
    wire [2:0]  fill_col8;
    wire [127:0] fill_data;
    wire        fill_done;
    wire [11:0] next_win_x0, next_win_y0;
    wire [5:0]  next_win_h;
    wire        next_tile_valid, next_ready;
    wire [11:0] src_x, src_y;
    wire [63:0] row0_pair, row1_pair;
    wire        win_valid;
    reg         win_start;
    reg         frm_use;
    reg         tr_start;

    win_engine_wide #(.TILES(1800), .TILE(32), .WIN(64)) u_win (
        .pclk(pclk), .rstn(rstn), .frame_start(1'b0),
        .rotate_mode(rotate_mode_active),
        .tr_start_d1(),
        .fill_start(tr_start), .start(win_start),
        .tile_idx(tile_idx), .win_x0(win_x0), .win_y0(win_y0),
        .next_win_x0(next_win_x0), .next_win_y0(next_win_y0),
        .next_win_h(next_win_h),
        .next_tile_valid(next_tile_valid),
        .win_ready(win_ready), .next_ready(next_ready),
        .fill_we(fill_we), .fill_row(fill_row), .fill_col8(fill_col8),
        .fill_data(fill_data), .fill_done(fill_done),
        .src_x(src_x), .src_y(src_y),
        .row0_pair(row0_pair), .row1_pair(row1_pair), .win_valid(win_valid)
    );

    //------------------------------------------------------------------
    // tile reader + DDR bridge (fills current tile)
    //------------------------------------------------------------------
    tile_reader_wide #(.ADDR_WIDTH(28), .LINE_WORDS(640)) u_tr (
        .pclk(pclk), .prstn(rstn), .ddr_clk(ddr_clk), .ddr_rstn(ddr_rstn),
        .start(tr_start), .win_x0(next_win_x0), .win_y0(next_win_y0),
        .win_h(next_win_h),
        .frame_idx(frm_use),
        .ddr_rreq(ddr_rreq), .ddr_raddr(ddr_raddr), .ddr_rd_len(ddr_rd_len),
        .ddr_rrdy(ddr_rrdy), .ddr_rdone(ddr_rdone),
        .ddr_rdata(ddr_rdata), .ddr_rdata_en(ddr_rdata_en),
        .fill_we(fill_we), .fill_row(fill_row), .fill_col8(fill_col8),
        .fill_data(fill_data), .fill_done(fill_done), .busy(),
        .dbg_dst(dbg_tile_dst), .dbg_fill_done(dbg_fill_done)
    );

    //------------------------------------------------------------------
    // correction + band buffer (v5 ports)
    //------------------------------------------------------------------
    wire vs_c, hs_c, de_c;
    wire [15:0] rgb_c;

    wire        de_rot;
    wire        valid_rot;
    wire [15:0] u_rot, v_rot;
    wire [11:0] u_rot12 = u_rot[15:4];
    wire [11:0] v_rot12 = v_rot[15:4];

    wire frame_end_pulse = 1'b0;

    rotate_map u_rot_map (
        .clk(pclk), .rstn(rstn), .rotate_mode(rotate_mode_active),
        .de_in(de_tile), .u_in(u), .v_in(v),
        .de_out(de_rot), .u_out(u_rot), .v_out(v_rot),
        .u_disp_out(), .v_disp_out(), .valid_out(valid_rot)
    );

    fisheye_core u_core (
        .clk(pclk), .rstn(rstn),
        .frame_end_pulse(frame_end_pulse),
        .mode_changed(mode_changed),
        .de_in(de_rot),
        .u(u_rot), .v(v_rot),
        .valid_aff(valid_rot),
        .u_disp(u_rot12), .v_disp(v_rot12),
        .win_x0(win_x0), .win_y0(win_y0),
        .row0_pair(row0_pair), .row1_pair(row1_pair),
        .win_valid(win_valid),
        .src_x(src_x), .src_y(src_y),
        .vs_out(vs_c), .hs_out(hs_c), .de_out(de_c),
        .rgb_out(rgb_c),
        .rd_bank_sel(rd_bank_sel), .rd_addr(rd_addr), .rd_data(rd_data),
        .rd_done(rd_done),
        .band_ready_0(band_ready_0), .band_ready_1(band_ready_1),
        .band_idx(band_idx)
    );

    //------------------------------------------------------------------
    // scheduler
    //------------------------------------------------------------------
    localparam S_INIT    = 4'd0;
    localparam S_PREFILL = 4'd1;
    localparam S_WAIT2   = 4'd2;
    localparam S_RUN     = 4'd3;
    localparam S_BAND    = 4'd4;
    localparam S_FRAME   = 4'd5;
    localparam S_FRAMED  = 4'd6;
    localparam S_FILLW   = 4'd7;
    localparam S_DRAIN   = 4'd8;

    reg [3:0] st;
    reg [3:0] drain_cnt;
    reg [8:0] pixcnt;
    reg [5:0] tilecnt;
    reg [1:0] wait_cnt;

    // Frame sync: one pass = 1800 tiles.  The pass start is aligned to the
    // HDMI display vsync so the band sequence stays locked to the display
    // frame (no rolling bottom-half tear).  The camera frame index is latched
    // at that instant and used for the whole pass.
    reg [10:0] tilefrm;
    reg        no_prefetch;
    reg [1:0]  frm_sync;
    reg [16:0] frm_delay;

    always @(posedge pclk or negedge rstn) begin
        if (!rstn) frm_sync <= 2'b00;
        else       frm_sync <= {frm_sync[0], frame_idx};
    end

    // Band-level backpressure.  The band's last pixel reaches band_wr ~15 pclk
    // after the scan's last pixel (corr_top L=15), so the scheduler must first
    // drain that pipeline, then look at the *new* band_idx bank.  If that bank
    // is still full (HDMI has not finished reading it), hold the scan instead
    // of letting band_wr drop the first part of the band.
    wire band_bank_full = band_idx ? band_ready_1 : band_ready_0;
    reg  [4:0] band_drain;

    always @(posedge pclk) begin
        if (!rstn) begin
            st           <= S_INIT;
            pixcnt       <= 9'd0;
            tilecnt      <= 6'd0;
            wait_cnt     <= 2'd0;
            drain_cnt    <= 4'd0;
            band_drain   <= 5'd0;
            tilefrm      <= 11'd0;
            no_prefetch  <= 1'b0;
            frm_use      <= 1'b0;
            frm_delay    <= 17'd0;
            tr_start     <= 1'b0;
            win_start    <= 1'b0;
            enable       <= 1'b0;
        end
        else begin
            tr_start     <= 1'b0;
            win_start    <= 1'b0;

            case (st)
                S_INIT: begin
                    if (next_tile_valid) begin
                        tr_start <= 1'b1;
                        st       <= S_PREFILL;
                    end
                end

                S_PREFILL: begin
                    if (no_prefetch) begin
                        // the prefetch of tile 0 was suppressed at tile 1799
                        no_prefetch <= 1'b0;
                        st          <= S_FRAME;
                    end
                    else if (next_ready) begin
                        if (tilecnt == 6'd0) begin
                            // band boundary: wait for the L=15 pipeline to drain
                            band_drain <= 5'd20;
                            st         <= S_BAND;
                        end
                        else begin
                            win_start <= 1'b1;
                            tilecnt   <= (tilecnt == 6'd39) ? 6'd0 : tilecnt + 6'd1;
                            wait_cnt  <= 2'd0;
                            st        <= S_WAIT2;
                            if (tilefrm == 11'd1799) begin
                                // last tile of the pass: display it, do not
                                // prefetch tile 0 of the next frame yet
                                no_prefetch <= 1'b1;
                                tilefrm     <= 11'd0;
                            end
                            else begin
                                tr_start <= 1'b1;
                                tilefrm  <= tilefrm + 11'd1;
                            end
                        end
                    end
                end

                S_BAND: begin
                    if (band_drain != 5'd0)
                        band_drain <= band_drain - 5'd1;
                    else if (!band_bank_full) begin
                        win_start <= 1'b1;
                        tr_start  <= 1'b1;
                        tilecnt   <= 6'd1;
                        tilefrm   <= tilefrm + 11'd1;
                        wait_cnt  <= 2'd0;
                        st        <= S_WAIT2;
                    end
                end

                S_FRAME: begin
                    // start on the display frame boundary, not the camera one
                    if (disp_edge) begin
                        frm_use   <= frm_sync[1];
                        frm_delay <= 17'd2000;
                        st        <= S_FRAMED;
                    end
                end

                S_FRAMED: begin
                    if (frm_delay != 17'd0)
                        frm_delay <= frm_delay - 17'd1;
                    else begin
                        tr_start <= 1'b1;   // re-fetch tile 0 of the new pass
                        st       <= S_FILLW;
                    end
                end

                S_FILLW: begin
                    if (next_ready && !band_bank_full) begin
                        win_start <= 1'b1;
                        tr_start  <= 1'b1;  // prefetch tile 1
                        tilecnt   <= 6'd1;
                        tilefrm   <= 11'd1;
                        wait_cnt  <= 2'd0;
                        st        <= S_WAIT2;
                    end
                end

                S_WAIT2: begin
                    if (wait_cnt == 2'd1) begin
                        enable   <= 1'b1;
                        pixcnt   <= 9'd0;
                        st       <= S_RUN;
                    end
                    else wait_cnt <= wait_cnt + 2'd1;
                end

                S_RUN: begin
                    if (pixcnt == 9'd511) begin
                        enable    <= 1'b0;
                        drain_cnt <= 4'd0;
                        st        <= S_DRAIN;
                    end
                    else pixcnt <= pixcnt + 9'd1;
                end

                // Let the last pixels of this tile finish their BRAM read
                // before start switches cur_x0 / the ping-pong bank.
                S_DRAIN: begin
                    if (drain_cnt == 4'd11)
                        st <= S_PREFILL;
                    else
                        drain_cnt <= drain_cnt + 4'd1;
                end

                default: st <= S_INIT;
            endcase
        end
    end

    assign dbg_next_tile_valid = next_tile_valid;
    assign dbg_next_ready      = next_ready;

endmodule
