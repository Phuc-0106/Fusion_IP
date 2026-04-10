// =============================================================
// ukf_fmac_pe.sv — Explicit MAC (acc in this wrapper, not in ukf_fp_engine)
// clr_pulse: acc <= a*b; mac_pulse: acc <= acc + a*b (same-cycle operands).
// rdy pulses with the initiating pulse; acc_reg is updated in the same
// cycle (combinational mul/add into the accumulator register).
// =============================================================
`include "params.vh"
`include "fp32_math.svh"

module ukf_fmac_pe #(
    parameter int DATA_W = `DATA_W
)(
    input  logic                     clk,
    input  logic                     rst,

    input  logic                     clr_pulse,
    input  logic                     mac_pulse,
    input  logic signed [DATA_W-1:0] a,
    input  logic signed [DATA_W-1:0] b,

    output logic signed [DATA_W-1:0] acc_out,
    output logic signed [DATA_W-1:0] last_result,
    output logic                     rdy
);

    logic signed [DATA_W-1:0] acc_reg;

    assign acc_out = acc_reg;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            acc_reg     <= '0;
            last_result <= '0;
            rdy         <= 1'b0;
        end else begin
            rdy <= clr_pulse | mac_pulse;
            if (clr_pulse) begin
                acc_reg     <= fp_mul(a, b);
                last_result <= fp_mul(a, b);
            end else if (mac_pulse) begin
                last_result <= fp_add(acc_reg, fp_mul(a, b));
                acc_reg     <= fp_add(acc_reg, fp_mul(a, b));
            end
        end
    end

endmodule
