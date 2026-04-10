// =============================================================
// pe_mul.sv — One FP multiply lane (explicit PE, no hidden acc)
// 1-cycle latency: en latches operands; next cycle product is valid
// and rdy=1. If valid_l=0 at capture, product is +0.
// =============================================================
`include "params.vh"
`include "fp32_math.svh"

module pe_mul #(
    parameter int DATA_W = `DATA_W
)(
    input  logic                     clk,
    input  logic                     rst,

    input  logic                     en,
    input  logic                     valid_l,
    input  logic signed [DATA_W-1:0] op_a,
    input  logic signed [DATA_W-1:0] op_b,

    output logic signed [DATA_W-1:0] product,
    output logic                     rdy
);

    logic                     en_q;
    logic                     cap_v;
    logic signed [DATA_W-1:0] cap_a, cap_b;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            en_q    <= 1'b0;
            cap_a   <= '0;
            cap_b   <= '0;
            cap_v   <= 1'b0;
            product <= '0;
            rdy     <= 1'b0;
        end else begin
            en_q <= en;
            rdy  <= 1'b0;
            if (en) begin
                cap_a <= op_a;
                cap_b <= op_b;
                cap_v <= valid_l;
            end
            if (en_q) begin
                rdy     <= 1'b1;
                product <= cap_v ? fp_mul(cap_a, cap_b) : `FP_ZERO;
            end
        end
    end

endmodule
