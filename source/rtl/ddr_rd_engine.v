`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// ddr_rd_engine  --  pipelined AXI read master for the DDR3 frame buffer
//
// Why this module exists
// ----------------------
// The old read path (rd_ctrl + the read half of wr_cmd_trans) is a single
// command FSM:
//   * a command is launched only on the RISING EDGE of rd_cmd_en
//     (wr_cmd_trans: rd_cmd_trig = ~rd_cmd_en_1d & rd_cmd_en)
//   * rd_cmd_ready is held low from that edge until rd_done_p, and rd_done_p
//     is a fixed 16-clock delay after the AR handshake, so a second command
//     can never be in flight
//   * the address is captured two clocks after the edge, which is fine only
//     because the old serial FSM holds the address until the command ends
//
// With that front-end a "MAXPEND = 4" reader cannot work at all: a level-held
// rd_cmd_en issues exactly one row per tile (measured: 6 commands offered,
// 1 AR on the bus), and an advancing address is sampled one row late.
//
// This engine replaces it with a plain valid/ready command stream and up to
// MAXOUT commands in flight:
//   * cmd_en/cmd_ready: one command accepted per cycle
//   * address and beat count are captured on the accept cycle
//   * AR is issued as soon as a command is queued and the bus is ready
//   * the data of each command is counted so that cmd_done marks its last
//     beat, exactly as ddr_rdone did before
// Data stays in order (one AXI ID), therefore the beat counter follows the
// same ring order as the address queue.
//////////////////////////////////////////////////////////////////////////////
module ddr_rd_engine #(
    parameter ADDR_WIDTH = 28,
    parameter DATA_WIDTH = 256,
    parameter MAXOUT     = 4          // commands in flight (1..7)
)(
    input                       clk,
    input                       rstn,

    //------------------------------------------------------------------
    // command stream (one command per cycle while cmd_en && cmd_ready)
    //------------------------------------------------------------------
    input                       cmd_en,
    input  [ADDR_WIDTH-1:0]     cmd_addr,
    input  [3:0]                cmd_beats,   // beats in this command
    output                      cmd_ready,
    output reg                  cmd_done,    // 1-cycle pulse at last beat

    //------------------------------------------------------------------
    // read data (same shape the tile FIFO expects)
    //------------------------------------------------------------------
    output [DATA_WIDTH-1:0]     rdata,
    output                      rdata_en,

    //------------------------------------------------------------------
    // AXI read address channel
    //------------------------------------------------------------------
    output [ADDR_WIDTH-1:0]     araddr,
    output [3:0]                arlen,
    output                      arvalid,
    input                       arready,

    //------------------------------------------------------------------
    // AXI read data channel
    //------------------------------------------------------------------
    input  [DATA_WIDTH-1:0]     axi_rdata,
    input                       axi_rvalid,
    input                       axi_rlast,
    output                      axi_rready
);

    reg [ADDR_WIDTH-1:0] q_addr  [0:7];
    reg [3:0]            q_beats [0:7];

    reg [2:0] wptr;        // commands accepted
    reg [2:0] aptr;        // commands whose AR was accepted
    reg [2:0] rptr;        // commands whose data is complete
    reg [3:0] beat_cnt;    // beats already received of command rptr

    wire [2:0] occ  = wptr - rptr;    // accepted but not finished
    wire [2:0] aocc = wptr - aptr;    // accepted but AR not yet on the bus

    assign cmd_ready = (occ < MAXOUT);
    assign arvalid   = (aocc != 3'd0);
    assign araddr    = q_addr[aptr];
    assign arlen     = q_beats[aptr];

    // last beat of the command currently being received
    wire [3:0] cur_beats = q_beats[rptr];
    wire       last_beat = axi_rvalid && ((beat_cnt + 4'd1) >= cur_beats);

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            wptr     <= 3'd0;
            aptr     <= 3'd0;
            rptr     <= 3'd0;
            beat_cnt <= 4'd0;
            cmd_done <= 1'b0;
        end
        else begin
            cmd_done <= 1'b0;

            if (cmd_en && cmd_ready) begin
                q_addr [wptr] <= cmd_addr;
                q_beats[wptr] <= (cmd_beats == 4'd0) ? 4'd1 : cmd_beats;
                wptr          <= wptr + 3'd1;
            end

            if (arvalid && arready)
                aptr <= aptr + 3'd1;

            if (axi_rvalid) begin
                if (last_beat) begin
                    beat_cnt <= 4'd0;
                    rptr     <= rptr + 3'd1;
                    cmd_done <= 1'b1;
                end
                else
                    beat_cnt <= beat_cnt + 4'd1;
            end
        end
    end

    assign rdata      = axi_rdata;
    assign rdata_en   = axi_rvalid;
    assign axi_rready = 1'b1;

endmodule
