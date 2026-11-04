// ============================================================
// corr_top: coord_lut -> win_req -> bilinear565
// 修复：win_x0/win_y0 延迟 9 拍，总延迟 L=15 拍。
// ============================================================
module corr_top (
    input  wire        clk,
    input  wire        rstn,
    input  wire        vs_in,
    input  wire        hs_in,
    input  wire        de_in,
    input  wire [11:0] u,
    input  wire [11:0] v,
    input  wire [11:0] win_x0,
    input  wire [11:0] win_y0,
    output wire [11:0] src_x,
    output wire [11:0] src_y,
    input  wire [63:0] row0_pair,
    input  wire [63:0] row1_pair,
    input  wire        win_valid,
    output wire        vs_out,
    output wire        hs_out,
    output wire        de_out,
    output wire [15:0] rgb_out,
    output wire [10:0] x_out,
    output wire [9:0]  y_out
);

    // win_x0/win_y0 延迟 9 拍
    reg [11:0] win_x0_sr [0:8];
    reg [11:0] win_y0_sr [0:8];
    integer j;
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            for (j = 0; j < 9; j = j + 1) begin win_x0_sr[j] <= 0; win_y0_sr[j] <= 0; end
        end else begin
            win_x0_sr[0] <= win_x0; win_y0_sr[0] <= win_y0;
            for (j = 1; j < 9; j = j + 1) begin win_x0_sr[j] <= win_x0_sr[j-1]; win_y0_sr[j] <= win_y0_sr[j-1]; end
        end
    end
    wire [11:0] win_x0_aligned = win_x0_sr[8];
    wire [11:0] win_y0_aligned = win_y0_sr[8];

    wire [15:0] xs_q, ys_q;
    wire        de_coord;
    coord_lut u_coord (
        .clk(clk), .rstn(rstn), .de_in(de_in), .u(u), .v(v),
        .xs_q(xs_q), .ys_q(ys_q), .de_out(de_coord)
    );

    wire [15:0] p00, p01, p10, p11;
    wire [3:0]  fx, fy;
    wire        de_win;
    win_req u_win (
        .clk(clk), .rstn(rstn),
        .xs_q(xs_q), .ys_q(ys_q), .de_in(de_coord),
        .win_x0(win_x0_aligned), .win_y0(win_y0_aligned),
        .src_x(src_x), .src_y(src_y),
        .row0_pair(row0_pair), .row1_pair(row1_pair), .win_valid(win_valid),
        .p00(p00), .p01(p01), .p10(p10), .p11(p11),
        .fx_out(fx), .fy_out(fy), .valid_out(de_win)
    );

    wire [15:0] rgb;
    wire        de_bil;
    bilinear565 u_bil (
        .clk(clk), .rstn(rstn), .valid_in(de_win),
        .p00(p00), .p01(p01), .p10(p10), .p11(p11), .fx(fx), .fy(fy),
        .rgb_out(rgb), .valid_out(de_bil)
    );

    // L = 15 : win_valid / row pairs already carry the extra BRAM cycle
    localparam L = 15;
    reg [L-1:0] vs_sr, hs_sr, de_sr;
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin vs_sr <= 0; hs_sr <= 0; de_sr <= 0; end
        else begin
            vs_sr <= {vs_sr[L-2:0], vs_in}; hs_sr <= {hs_sr[L-2:0], hs_in}; de_sr <= {de_sr[L-2:0], de_in};
        end
    end

    reg [10:0] x_sr [0:L-1];
    reg [9:0]  y_sr [0:L-1];
    integer i;
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            for (i = 0; i < L; i = i + 1) begin x_sr[i] <= 0; y_sr[i] <= 0; end
        end else begin
            x_sr[0] <= u; y_sr[0] <= v;
            for (i = 1; i < L; i = i + 1) begin x_sr[i] <= x_sr[i-1]; y_sr[i] <= y_sr[i-1]; end
        end
    end

    assign vs_out  = vs_sr[L-1];
    assign hs_out  = hs_sr[L-1];
    assign de_out  = de_sr[L-1];
    assign rgb_out = rgb;
    assign x_out   = x_sr[L-1];
    assign y_out   = y_sr[L-1];

endmodule