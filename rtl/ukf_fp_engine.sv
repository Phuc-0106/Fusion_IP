// =============================================================
// ukf_fp_engine.sv — One FP op per start pulse (result valid next cycle)
//
// Stateless: no internal accumulator; MAC must use explicit registers
// outside this module (e.g. sigma_point_generator mac_sum_r + pe_mul).
//
// Default: behavioral FP32 (fp32_math.svh) for Questa.
// Define UKF_SYNTH_XILINX_FP for Vivado: replace the behavioral case with
// Xilinx Floating-Point Operator IP (mul/add/sub/div/sqrt/recip).
// =============================================================
`include "params.vh"
`include "ukf_fp_pkg.svh"

`ifndef UKF_SYNTH_XILINX_FP
`include "fp32_math.svh"
`endif

module ukf_fp_engine #(
    parameter int DATA_W = `DATA_W
)(
    input  logic                     clk,
    input  logic                     rst,

    input  logic                     start,
    input  ukf_fp_op_e               op,
    input  logic signed [DATA_W-1:0] op_a,
    input  logic signed [DATA_W-1:0] op_b,

    output logic signed [DATA_W-1:0] result,
    output logic signed [DATA_W-1:0] acc,
    output logic                     rdy
);

    assign acc = '0;

`ifdef UKF_SYNTH_XILINX_FP
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            result <= '0;
            rdy    <= 1'b0;
        end else begin
            rdy <= 1'b0;
            if (start) begin
                result <= op_a;
                rdy    <= 1'b1;
            end
        end
    end
`else
    logic                     start_d, start_dd;
    ukf_fp_op_e               op_r;
    logic signed [DATA_W-1:0] op_ar, op_br;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            start_d  <= 1'b0;
            start_dd <= 1'b0;
            result   <= '0;
            rdy      <= 1'b0;
        end else begin
            start_d  <= start;
            start_dd <= start_d;
            rdy      <= start_dd;
            if (start) begin
                op_r  <= op;
                op_ar <= op_a;
                op_br <= op_b;
            end
            if (start_d) begin
                case (op_r)
                    UKF_FP_NOP:   result <= op_ar;
                    UKF_FP_MUL:   result <= fp_mul(op_ar, op_br);
                    UKF_FP_ADD:   result <= fp_add(op_ar, op_br);
                    UKF_FP_SUB:   result <= fp_sub(op_ar, op_br);
                    UKF_FP_NEG:   result <= fp_neg(op_ar);
                    UKF_FP_DIV:   result <= fp_mul(op_ar, fp_recip(op_br));
                    UKF_FP_SQRT:  result <= fp_sqrt_nr(op_ar);
                    UKF_FP_RECIP: result <= fp_recip(op_ar);
                    default:      result <= op_ar;
                endcase
            end
        end
    end
`endif

endmodule
