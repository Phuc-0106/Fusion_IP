// cordic_fp32.sv — Drop-in FP32 sin/cos (simulation) for predict_block
//
// Same ports as cordic.sv. One-cycle pipeline: `done` is high in the first
// full cycle after `start` was high (matches predict FSM wait behavior).
//
`include "params.vh"

module cordic_fp32 #(
    parameter int DATA_W  = `DATA_W,
    parameter int FP_FRAC = `FP_FRAC,
    parameter int ITERS   = 16
)(
    input  logic                        clk,
    input  logic                        rst,

    input  logic                        start,
    input  logic signed [DATA_W-1:0]    angle,

    output logic signed [DATA_W-1:0]    cos_out,
    output logic signed [DATA_W-1:0]    sin_out,
    output logic                        done
);
    logic start_d;

    always_ff @(posedge clk or posedge rst) begin
        if (rst)
            start_d <= 1'b0;
        else
            start_d <= start;
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            done    <= 1'b0;
            sin_out <= '0;
            cos_out <= '0;
        end else begin
            if (start) begin
                sin_out <= $shortrealtobits($sin($bitstoshortreal(angle)));
                cos_out <= $shortrealtobits($cos($bitstoshortreal(angle)));
            end
            done <= start_d;
        end
    end
endmodule
