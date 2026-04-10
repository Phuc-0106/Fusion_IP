// =============================================================
// ukf_fp_add_reduce_tree.sv — Pipelined FP adder tree (no hidden MAC)
// Pads NUM_IN to the next power of two with +0.
// After a one-cycle sample pulse: leaves are registered; each stage
// runs when dly[s] is set (s = 1..ST). sum_valid pulses 1 cycle
// when sum_out holds the reduced sum (latency 1 + ST from sample).
// =============================================================
`include "params.vh"

`include "fp32_math.svh"

module ukf_fp_add_reduce_tree #(
    parameter int NUM_IN = 4,
    parameter int DATA_W = `DATA_W
)(
    input  logic                     clk,
    input  logic                     rst,

    input  logic                     sample,
    input  logic signed [DATA_W-1:0] leaf_in [0:NUM_IN-1],

    output logic signed [DATA_W-1:0] sum_out,
    output logic                     sum_valid
);

    localparam int P  = (NUM_IN <= 1) ? 1 : (1 << $clog2(NUM_IN));
    localparam int ST = (P <= 1) ? 0 : $clog2(P);

    logic [ST:0] dly;

    logic signed [DATA_W-1:0] lvl [0:ST-1][0:P-1];

    integer ii, jj;

    generate
        if (P == 1) begin : g_one
            logic sam_q;
            always_ff @(posedge clk or posedge rst) begin
                if (rst) begin
                    sam_q     <= 1'b0;
                    sum_out   <= '0;
                    sum_valid <= 1'b0;
                end else begin
                    sum_valid <= 1'b0;
                    sam_q     <= sample;
                    if (sample)
                        sum_out <= leaf_in[0];
                    if (sam_q) begin
                        sum_valid <= 1'b1;
                    end
                end
            end
        end else begin : g_tree
            always_ff @(posedge clk or posedge rst) begin
                if (rst) begin
                    dly       <= '0;
                    sum_out   <= '0;
                    sum_valid <= 1'b0;
                    for (ii = 0; ii < ST; ii = ii + 1)
                        for (jj = 0; jj < P; jj = jj + 1)
                            lvl[ii][jj] <= '0;
                end else begin
                    sum_valid <= 1'b0;
                    dly <= {dly[ST-1:0], sample};

                    if (sample) begin
                        for (ii = 0; ii < NUM_IN; ii = ii + 1)
                            lvl[0][ii] <= leaf_in[ii];
                        for (ii = NUM_IN; ii < P; ii = ii + 1)
                            lvl[0][ii] <= `FP_ZERO;
                    end

                    for (ii = 0; ii < ST - 1; ii = ii + 1) begin
                        if (dly[ii+1]) begin
                            for (jj = 0; jj < (P >> (ii + 1)); jj = jj + 1)
                                lvl[ii+1][jj] <= fp_add(lvl[ii][2*jj], lvl[ii][2*jj+1]);
                        end
                    end
                    if (dly[ST]) begin
                        sum_out   <= fp_add(lvl[ST-1][0], lvl[ST-1][1]);
                        sum_valid <= 1'b1;
                    end
                end
            end
        end
    endgenerate

endmodule
