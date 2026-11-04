`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// tile_rd_bridge
//
// Bridges the pclk tile_reader_wide tr_* interface to the existing fram_buf
// ddr_* read command interface (wr_rd_ctrl_top rd_cmd/read stream).
//
// One 3-beat row segment at a time:
//   pclk  : tr_rreq/tr_raddr -> req_tog + req_addr
//   ddr   : req_event -> ddr_rreq/ddr_raddr/ddr_rd_len=2
//           3 x ddr_rdata_en beats -> bank0..2 -> ack_tog
//   pclk  : ack_event -> stream bank0..2 -> tr_rdata/tr_rdata_en/tr_rdone
//           consume_tog
//   ddr   : consume_event -> ready for next row
//////////////////////////////////////////////////////////////////////////////////
module tile_rd_bridge (
    // pclk / tile_reader side
    input               pclk,
    input               prstn,
    input               tr_rreq,
    input  [27:0]       tr_raddr,
    input  [7:0]        tr_rlen,
    output              tr_rrdy,
    output [255:0]      tr_rdata,
    output              tr_rdata_en,
    output              tr_rdone,

    // ddr_clk / framebuf side
    input               ddr_clk,
    input               ddr_rstn,
    output              ddr_rreq,
    output [27:0]       ddr_raddr,
    output [31:0]       ddr_rd_len,
    input               ddr_rrdy,
    input               ddr_rdone,
    input  [255:0]      ddr_rdata,
    input               ddr_rdata_en
);

    //------------------------------------------------------------------
    // pclk side
    //------------------------------------------------------------------
    localparam P_IDLE   = 2'd0;
    localparam P_WAIT   = 2'd1;
    localparam P_STREAM = 2'd2;

    reg [1:0]  pst;
    reg [1:0]  pbeat;
    reg        req_tog;
    reg [27:0] req_addr;
    reg        tr_rrdy_r, tr_rdata_en_r, tr_rdone_r;
    reg [255:0] tr_rdata_r;
    reg        consume_tog;
    reg        ack_tog;

    reg [255:0] bank0, bank1, bank2;

    // ack_tog sync into pclk
    reg ak_s1, ak_s2, ak_s3;
    always @(posedge pclk) begin
        ak_s1 <= ack_tog;
        ak_s2 <= ak_s1;
        ak_s3 <= ak_s2;
    end
    wire ack_event = ak_s2 ^ ak_s3;

    always @(posedge pclk) begin
        if (!prstn) begin
            pst          <= P_IDLE;
            pbeat        <= 2'd0;
            req_tog      <= 1'b0;
            req_addr     <= 28'd0;
            tr_rrdy_r    <= 1'b1;
            tr_rdata_en_r<= 1'b0;
            tr_rdone_r   <= 1'b0;
            tr_rdata_r   <= 256'd0;
            consume_tog  <= 1'b0;
        end
        else begin
            tr_rdata_en_r <= 1'b0;
            tr_rdone_r    <= 1'b0;

            case (pst)
                P_IDLE: begin
                    tr_rrdy_r <= 1'b1;
                    if (tr_rreq) begin
                        req_addr  <= tr_raddr;
                        req_tog   <= ~req_tog;
                        tr_rrdy_r <= 1'b0;
                        pst       <= P_WAIT;
                    end
                end

                P_WAIT: begin
                    if (ack_event) begin
                        pbeat <= 2'd0;
                        pst   <= P_STREAM;
                    end
                end

                P_STREAM: begin
                    tr_rdata_en_r <= 1'b1;
                    case (pbeat)
                        2'd0: tr_rdata_r <= bank0;
                        2'd1: tr_rdata_r <= bank1;
                        default: tr_rdata_r <= bank2;
                    endcase
                    if (pbeat == 2'd2) begin
                        tr_rdone_r  <= 1'b1;
                        consume_tog <= ~consume_tog;
                        pst         <= P_IDLE;
                    end
                    else begin
                        pbeat <= pbeat + 2'd1;
                    end
                end

                default: pst <= P_IDLE;
            endcase
        end
    end

    assign tr_rrdy    = tr_rrdy_r;
    assign tr_rdata   = tr_rdata_r;
    assign tr_rdata_en= tr_rdata_en_r;
    assign tr_rdone   = tr_rdone_r;

    //------------------------------------------------------------------
    // ddr side
    //------------------------------------------------------------------
    localparam D_IDLE = 2'd0;
    localparam D_CMD  = 2'd1;
    localparam D_DATA = 2'd2;
    localparam D_DONE = 2'd3;

    reg [1:0]  dst;
    reg [3:0]  dbeat;
    reg        ddr_rreq_r;
    reg [27:0] ddr_addr_r;

    // req_tog sync into ddr_clk
    reg rq_s1, rq_s2, rq_s3;
    always @(posedge ddr_clk) begin
        rq_s1 <= req_tog;
        rq_s2 <= rq_s1;
        rq_s3 <= rq_s2;
    end
    wire req_event = rq_s2 ^ rq_s3;

    // consume_tog sync into ddr_clk
    reg cs_s1, cs_s2, cs_s3;
    always @(posedge ddr_clk) begin
        cs_s1 <= consume_tog;
        cs_s2 <= cs_s1;
        cs_s3 <= cs_s2;
    end
    wire consume_event = cs_s2 ^ cs_s3;

    always @(posedge ddr_clk) begin
        if (!ddr_rstn) begin
            dst        <= D_IDLE;
            dbeat      <= 4'd0;
            ddr_rreq_r <= 1'b0;
            ddr_addr_r <= 28'd0;
            ack_tog    <= 1'b0;
            bank0      <= 256'd0;
            bank1      <= 256'd0;
            bank2      <= 256'd0;
        end
        else begin
            case (dst)
                D_IDLE: begin
                    ddr_rreq_r <= 1'b0;
                    if (req_event) begin
                        ddr_addr_r <= req_addr;
                        dst        <= D_CMD;
                    end
                end

                D_CMD: begin
                    if (ddr_rrdy) begin
                        ddr_rreq_r <= 1'b1;
                        dbeat      <= 4'd0;
                        dst        <= D_DATA;
                    end
                end

                D_DATA: begin
                    ddr_rreq_r <= 1'b0;
                    if (ddr_rdata_en) begin
                        if (dbeat == 4'd0)      bank0 <= ddr_rdata;
                        else if (dbeat == 4'd1) bank1 <= ddr_rdata;
                        else if (dbeat == 4'd2) bank2 <= ddr_rdata;
                        // beats 3..15 are the rest of the 16-beat burst and
                        // are ignored; only 3 beats (48 pixels) are needed.
                        if (ddr_rdone) begin
                            ack_tog <= ~ack_tog;
                            dst     <= D_DONE;
                        end
                        else begin
                            dbeat <= dbeat + 4'd1;
                        end
                    end
                end

                D_DONE: begin
                    if (consume_event)
                        dst <= D_IDLE;
                end

                default: dst <= D_IDLE;
            endcase
        end
    end

    assign ddr_rreq   = ddr_rreq_r;
    assign ddr_raddr  = ddr_addr_r;
    assign ddr_rd_len = 32'd2;      // 3-beat burst (wr_cmd_trans patched for short reads)

endmodule
