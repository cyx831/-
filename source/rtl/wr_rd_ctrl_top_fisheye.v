`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// wr_rd_ctrl_top_fisheye
//
// Same write path as wr_rd_ctrl_top (wr_cmd_trans + wr_ctrl), but the read
// path is replaced by ddr_rd_engine so that several row reads can be in
// flight instead of one.
//
// The write half of wr_cmd_trans is kept untouched; its read half is tied
// off (rd_cmd_en = 0) and the AXI read channels are driven by the engine.
//////////////////////////////////////////////////////////////////////////////
module wr_rd_ctrl_top_fisheye #(
    parameter CTRL_ADDR_WIDTH = 28,
    parameter MEM_DQ_WIDTH    = 32,
    parameter MAXOUT          = 4
)(
    input                        clk,
    input                        rstn,

    // write command
    input                        wr_cmd_en,
    input  [CTRL_ADDR_WIDTH-1:0] wr_cmd_addr,
    input  [31:0]                wr_cmd_len,
    output                       wr_cmd_ready,
    output                       wr_cmd_done,

    output                       wr_bac,
    input  [MEM_DQ_WIDTH*8-1:0]  wr_ctrl_data,
    output                       wr_data_re,

    // read command (pipelined)
    input                        rd_cmd_en,
    input  [CTRL_ADDR_WIDTH-1:0] rd_cmd_addr,
    input  [31:0]                rd_cmd_len,
    output                       rd_cmd_ready,
    output                       rd_cmd_done,

    input                        read_ready,
    output [MEM_DQ_WIDTH*8-1:0]  read_rdata,
    output                       read_en,

    // write channel
    output [CTRL_ADDR_WIDTH-1:0] axi_awaddr,
    output [3:0]                 axi_awid,
    output [3:0]                 axi_awlen,
    output [2:0]                 axi_awsize,
    output [1:0]                 axi_awburst,
    input                        axi_awready,
    output                       axi_awvalid,

    output [MEM_DQ_WIDTH*8-1:0]  axi_wdata,
    output [MEM_DQ_WIDTH-1:0]    axi_wstrb,
    input                        axi_wlast,
    output                       axi_wvalid,
    input                        axi_wready,
    input  [3:0]                 axi_bid,
    input  [1:0]                 axi_bresp,
    input                        axi_bvalid,
    output                       axi_bready,

    // read channel
    output [CTRL_ADDR_WIDTH-1:0] axi_araddr,
    output [3:0]                 axi_arid,
    output [3:0]                 axi_arlen,
    output [2:0]                 axi_arsize,
    output [1:0]                 axi_arburst,
    output                       axi_arvalid,
    input                        axi_arready,

    output                       axi_rready,
    input  [MEM_DQ_WIDTH*8-1:0]  axi_rdata,
    input                        axi_rvalid,
    input                        axi_rlast,
    input  [3:0]                 axi_rid,
    input  [1:0]                 axi_rresp
);

    //------------------------------------------------------------------
    // write command translator (read half unused)
    //------------------------------------------------------------------
    wire        wr_en;
    wire [CTRL_ADDR_WIDTH-1:0] wr_addr;
    wire [3:0]  wr_id;
    wire [3:0]  wr_len;
    wire        wr_data_en;
    wire        wr_ready;
    wire        wr_done;
    wire        wr_data_re_i;

    wr_cmd_trans #(
        .CTRL_ADDR_WIDTH (CTRL_ADDR_WIDTH),
        .MEM_DQ_WIDTH    (MEM_DQ_WIDTH)
    ) wr_cmd_trans_i (
        .clk            (clk),
        .rstn           (rstn),
        .wr_cmd_en      (wr_cmd_en),
        .wr_cmd_addr    (wr_cmd_addr),
        .wr_cmd_len     (wr_cmd_len),
        .wr_cmd_ready   (wr_cmd_ready),
        .wr_cmd_done    (wr_cmd_done),
        .wr_bac         (wr_bac),
        .wr_ctrl_data   (wr_ctrl_data),
        .wr_data_re     (wr_data_re_i),
        .wr_en          (wr_en),
        .wr_addr        (wr_addr),
        .wr_id          (wr_id),
        .wr_len         (wr_len),
        .wr_data_en     (wr_data_en),
        .wr_data        (),
        .wr_ready       (wr_ready),
        .wr_done        (wr_done),
        // read half tied off
        .rd_cmd_en      (1'b0),
        .rd_cmd_addr    ({(CTRL_ADDR_WIDTH){1'b0}}),
        .rd_cmd_len     (32'd0),
        .rd_cmd_ready   (),
        .rd_cmd_done    (),
        .read_en        (1'b0),
        .rd_en          (),
        .rd_addr        (),
        .rd_id          (),
        .rd_len         (),
        .rd_done_p      (1'b0)
    );
    assign wr_data_re = wr_data_re_i;

    //------------------------------------------------------------------
    // write channel
    //------------------------------------------------------------------
    wr_ctrl #(
        .CTRL_ADDR_WIDTH (CTRL_ADDR_WIDTH),
        .MEM_DQ_WIDTH    (MEM_DQ_WIDTH)
    ) wr_ctrl_i (
        .clk            (clk),
        .rst_n          (rstn),
        .wr_en          (wr_en),
        .wr_addr        (wr_addr),
        .wr_id          (wr_id),
        .wr_len         (wr_len),
        .wr_cmd_done    (wr_done),
        .wr_ready       (wr_ready),
        .wr_data_en     (wr_data_en),
        .wr_data        (wr_ctrl_data),
        .wr_bac         (wr_bac),
        .axi_awaddr     (axi_awaddr),
        .axi_awid       (axi_awid),
        .axi_awlen      (axi_awlen),
        .axi_awsize     (axi_awsize),
        .axi_awburst    (axi_awburst),
        .axi_awready    (axi_awready),
        .axi_awvalid    (axi_awvalid),
        .axi_wdata      (axi_wdata),
        .axi_wstrb      (axi_wstrb),
        .axi_wlast      (axi_wlast),
        .axi_wvalid     (axi_wvalid),
        .axi_wready     (axi_wready),
        .axi_bid        (axi_bid),
        .axi_bresp      (axi_bresp),
        .axi_bvalid     (axi_bvalid),
        .axi_bready     (axi_bready),
        .test_wr_state  ()
    );

    //------------------------------------------------------------------
    // pipelined read channel
    //------------------------------------------------------------------
    ddr_rd_engine #(
        .ADDR_WIDTH (CTRL_ADDR_WIDTH),
        .DATA_WIDTH (MEM_DQ_WIDTH*8),
        .MAXOUT     (MAXOUT)
    ) rd_engine_i (
        .clk        (clk),
        .rstn       (rstn),
        .cmd_en     (rd_cmd_en),
        .cmd_addr   (rd_cmd_addr),
        .cmd_beats  (rd_cmd_len[3:0]),
        .cmd_ready  (rd_cmd_ready),
        .cmd_done   (rd_cmd_done),
        .rdata      (read_rdata),
        .rdata_en   (read_en),
        .araddr     (axi_araddr),
        .arlen      (axi_arlen),
        .arvalid    (axi_arvalid),
        .arready    (axi_arready),
        .axi_rdata  (axi_rdata),
        .axi_rvalid (axi_rvalid),
        .axi_rlast  (axi_rlast),
        .axi_rready (axi_rready)
    );

    assign axi_arid    = 4'd0;
    assign axi_arsize  = 3'b110;
    assign axi_arburst = 2'b01;

endmodule
