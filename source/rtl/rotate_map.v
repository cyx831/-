// ============================================================
// rotate_map: 逆仿射变换 (0°, 15°, 25°)
// 输出 16-bit Q12.4 坐标，并带越界标识
// ============================================================
module rotate_map (
    input  wire        clk, rstn,
    input  wire [1:0]  rotate_mode,
    input  wire        de_in,
    input  wire [11:0] u_in, v_in,
    output reg         de_out,
    output reg  [15:0] u_out, v_out,
    output reg  [11:0] u_disp_out, v_disp_out,
    output reg         valid_out
);
    reg signed [15:0] m00, m01, m02, m10, m11, m12;
    always @(*) begin
        case (rotate_mode)
            2'b00: begin m00=16'sh1000; m01=16'sh0000; m02=16'sh0000; m10=16'sh0000; m11=16'sh1000; m12=16'sh0000; end
            2'b01: begin m00=16'sh0F74; m01=16'sh0424; m02=16'shFB8A; m10=16'shFBDC; m11=16'sh0F74; m12=16'sh0B1F; end
            2'b10: begin m00=16'sh0E80; m01=16'sh06C3; m02=16'shFA3F; m10=16'shF93D; m11=16'sh0E80; m12=16'sh1303; end
            default: begin m00=16'sh1000; m01=16'sh0000; m02=16'sh0000; m10=16'sh0000; m11=16'sh1000; m12=16'sh0000; end
        endcase
    end

    reg signed [15:0] u_q, v_q;
    reg de_1;
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin u_q<=0; v_q<=0; de_1<=0; end
        else begin
            u_q <= {u_in, 4'b0000};
            v_q <= {v_in, 4'b0000};
            de_1 <= de_in;
        end
    end

    reg signed [31:0] p00, p01, p10, p11;
    reg de_2;
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin p00<=0; p01<=0; p10<=0; p11<=0; de_2<=0; end
        else begin
            p00 <= u_q * m00; p01 <= v_q * m01;
            p10 <= u_q * m10; p11 <= v_q * m11;
            de_2 <= de_1;
        end
    end

    reg signed [32:0] u_sum, v_sum;
    reg de_3;
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin u_sum<=0; v_sum<=0; de_3<=0; end
        else begin
            u_sum <= p00 + p01 + ({{17{m02[15]}}, m02} <<< 12);
            v_sum <= p10 + p11 + ({{17{m12[15]}}, m12} <<< 12);
            de_3 <= de_2;
        end
    end

    reg [11:0] du1, du2, du3, du4, dv1, dv2, dv3, dv4;
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            du1<=0; du2<=0; du3<=0; du4<=0;
            dv1<=0; dv2<=0; dv3<=0; dv4<=0;
        end else begin
            du1<=u_in; du2<=du1; du3<=du2; du4<=du3;
            dv1<=v_in; dv2<=dv1; dv3<=dv2; dv4<=dv3;
        end
    end

    wire signed [32:0] u_rnd = u_sum + 33'sd2048;
    wire signed [32:0] v_rnd = v_sum + 33'sd2048;
    wire signed [16:0] u_q4  = u_rnd[28:12];
    wire signed [16:0] v_q4  = v_rnd[28:12];

    wire [15:0] u_clamp = u_q4[15:0];
    wire [15:0] v_clamp = v_q4[15:0];
    wire u_in_range = 1'b1;
    wire v_in_range = 1'b1;

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            u_out<=0; v_out<=0;
            u_disp_out<=0; v_disp_out<=0;
            de_out<=0; valid_out<=0;
        end else begin
            u_out      <= u_clamp;
            v_out      <= v_clamp;
            u_disp_out <= du4;
            v_disp_out <= dv4;
            de_out     <= de_3;
            valid_out  <= u_in_range & v_in_range & de_3;
        end
    end

endmodule
