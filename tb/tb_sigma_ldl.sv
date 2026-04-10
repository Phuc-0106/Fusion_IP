// =============================================================
// tb_sigma_ldl.sv — Standalone testbench for sigma_point_generator
//                   (LDLᵀ, FP32 arithmetic)
//
// Compares the DUT output against a SystemVerilog reference model.
//
// Three test cases:
//   TC1 — P = I₅,       x = 0,  γ = 1.0
//   TC2 — P = 4·I₅,     x = 0,  γ = UKF_GAMMA (≈0.22361)
//   TC3 — SPD 5×5,      x ≠ 0,  γ = UKF_GAMMA
//   TC4 — Symmetry check on TC3 result
// =============================================================
`timescale 1ns/1ps
`include "params.vh"
`include "fp32_math.svh"
`include "ukf_scalar_ops.svh"

`define TOL 32'h00004000   // ≈ 1.9e-4 (FP32 tolerance)

module tb_sigma_ldl;

    localparam int DATA_W  = `DATA_W;
    localparam int FP_FRAC = `FP_FRAC;
    localparam int N       = `N_STATE;
    localparam int N_SIG   = `N_SIGMA;
    localparam int NN      = N * N;
    localparam int MEM_D   = 256;

    // FP32 helper functions (mirrors fp32_math.svh, for use in tasks/functions)
    function automatic logic signed [DATA_W-1:0] tb_fp_sqrt;
        input logic signed [DATA_W-1:0] v;
        shortreal rv;
        begin
            rv = $bitstoshortreal(v);
            tb_fp_sqrt = (rv <= 0.0) ? 32'h0 : $shortrealtobits($sqrt(rv));
        end
    endfunction

    function automatic logic signed [DATA_W-1:0] tb_fp_recip;
        input logic signed [DATA_W-1:0] d;
        shortreal rd;
        begin
            rd = $bitstoshortreal(d);
            if (rd == 0.0) rd = 1.0e-30;
            tb_fp_recip = $shortrealtobits(1.0 / rd);
        end
    endfunction

    // Reference model: LDLᵀ decomposition + sigma-point assembly
    task automatic ldl_sigma_ref(
        input  logic signed [DATA_W-1:0] P_in [0:NN-1],
        input  logic signed [DATA_W-1:0] x_in [0:N-1],
        input  logic signed [DATA_W-1:0] gamma_in,
        output logic signed [DATA_W-1:0] sigma_ref [0:N_SIG*N-1]
    );
        logic signed [DATA_W-1:0] L [0:NN-1];
        logic signed [DATA_W-1:0] D [0:N-1];
        logic signed [DATA_W-1:0] d_val, off_sum, lij_num, s;

        for (int ii = 0; ii < NN; ii++) L[ii] = P_in[ii];

        for (int j = 0; j < N; j++) begin
            d_val = L[j*N+j];
            for (int k = 0; k < j; k++)
                d_val = ukf_sub(d_val, fp_mul(fp_mul(L[j*N+k], L[j*N+k]), D[k]));
            if ($bitstoshortreal(d_val) <= 0.0) d_val = `FP_EPSILON;
            D[j] = d_val;

            for (int i = j+1; i < N; i++) begin
                off_sum = '0;
                for (int k = 0; k < j; k++)
                    off_sum = ukf_add(off_sum,
                                  fp_mul(fp_mul(L[i*N+k], L[j*N+k]), D[k]));
                lij_num = ukf_sub(L[i*N+j], off_sum);
                L[i*N+j] = fp_mul(lij_num, tb_fp_recip(D[j]));
            end
        end

        for (int ii = 0; ii < N; ii++)
            for (int jj = ii+1; jj < N; jj++)
                L[ii*N+jj] = '0;

        for (int j = 0; j < N; j++) begin
            s = fp_mul(gamma_in, tb_fp_sqrt(D[j]));
            L[j*N+j] = s;
            for (int i = j+1; i < N; i++)
                L[i*N+j] = fp_mul(s, L[i*N+j]);
        end

        for (int ii = 0; ii < N; ii++)
            sigma_ref[ii] = x_in[ii];
        for (int j = 0; j < N; j++) begin
            for (int ii = 0; ii < N; ii++) begin
                sigma_ref[(j+1)*N+ii]   = ukf_add(x_in[ii], L[ii*N+j]);
                sigma_ref[(N+j+1)*N+ii] = ukf_sub(x_in[ii], L[ii*N+j]);
            end
        end
    endtask

    function automatic bit within_tol(
        input logic signed [DATA_W-1:0] a, b
    );
        shortreal ra, rb, diff;
        begin
            ra   = $bitstoshortreal(a);
            rb   = $bitstoshortreal(b);
            diff = (ra > rb) ? (ra - rb) : (rb - ra);
            within_tol = (diff < $bitstoshortreal(`TOL));
        end
    endfunction

    // DUT signals
    logic                    clk, rst;
    logic                    start, done, sigma_err;
    logic                    mem_rd_en;
    logic [`ADDR_W-1:0]      mem_rd_addr;
    logic [DATA_W-1:0]       mem_rd_data;
    logic                    mem_wr_en;
    logic [`ADDR_W-1:0]      mem_wr_addr;
    logic [DATA_W-1:0]       mem_wr_data;
    logic signed [DATA_W-1:0] gamma_dut;

    // State memory model
    logic [DATA_W-1:0] state_mem [0:MEM_D-1];
    assign mem_rd_data = state_mem[mem_rd_addr];
    always_ff @(posedge clk) if (mem_wr_en) state_mem[mem_wr_addr] <= mem_wr_data;

    // DUT
    sigma_point_generator #(.DATA_W(DATA_W), .FP_FRAC(FP_FRAC), .N(N), .N_SIG(N_SIG)) dut (
        .clk(clk), .rst(rst), .start(start), .done(done), .sigma_err(sigma_err),
        .mem_rd_en(mem_rd_en), .mem_rd_addr(mem_rd_addr), .mem_rd_data(mem_rd_data),
        .mem_wr_en(mem_wr_en), .mem_wr_addr(mem_wr_addr), .mem_wr_data(mem_wr_data),
        .gamma(gamma_dut)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    task automatic run_dut(
        input logic signed [DATA_W-1:0] P_in [0:NN-1],
        input logic signed [DATA_W-1:0] x_in [0:N-1],
        input logic signed [DATA_W-1:0] gam
    );
        int timeout;
        for (int ii = 0; ii < N; ii++)  state_mem[`ADDR_X + ii] = x_in[ii];
        for (int ii = 0; ii < NN; ii++) state_mem[`ADDR_P + ii] = P_in[ii];
        gamma_dut = gam;
        @(posedge clk); #1; start = 1'b1;
        @(posedge clk); #1; start = 1'b0;
        timeout = 0;
        while (!done && timeout < 5000) begin @(posedge clk); #1; timeout++; end
        if (timeout >= 5000) begin $display("TIMEOUT"); $fatal; end
    endtask

    task automatic compare_sigma(
        input string              tc_name,
        input logic signed [DATA_W-1:0] ref_sig [0:N_SIG*N-1]
    );
        int errors = 0;
        logic [DATA_W-1:0] dut_val;
        for (int sp = 0; sp < N_SIG; sp++)
            for (int el = 0; el < N; el++) begin
                dut_val = state_mem[`ADDR_SIGMA + sp*N + el];
                if (!within_tol(dut_val, ref_sig[sp*N+el])) begin
                    $display("[%s] MISMATCH chi[%0d][%0d] dut=0x%08h ref=0x%08h",
                             tc_name, sp, el, dut_val, ref_sig[sp*N+el]);
                    errors++;
                end
            end
        if (errors == 0) $display("[%s] PASS (sigma_err=%0b)", tc_name, sigma_err);
        else             $display("[%s] FAIL (%0d mismatches)", tc_name, errors);
    endtask

    // FP32 constants used in test cases
    localparam logic [DATA_W-1:0] FP_FOUR  = 32'h4080_0000;  //  4.0
    localparam logic [DATA_W-1:0] FP_PT5   = 32'h3F00_0000;  //  0.5
    localparam logic [DATA_W-1:0] FP_N_PT5 = 32'hBF00_0000;  // -0.5
    localparam logic [DATA_W-1:0] FP_TENTH = 32'h3DCCCCCD;   //  0.1
    localparam logic [DATA_W-1:0] FP_1P5   = 32'h3FC00000;   //  1.5

    logic signed [DATA_W-1:0] P_tc  [0:NN-1];
    logic signed [DATA_W-1:0] x_tc  [0:N-1];
    logic signed [DATA_W-1:0] ref_s [0:N_SIG*N-1];

    initial begin
        rst = 1'b1; start = 1'b0;
        repeat(4) @(posedge clk); #1; rst = 1'b0;
        @(posedge clk); #1;

        // TC1 — P=I, x=0, γ=1
        for (int ii=0; ii<NN; ii++) P_tc[ii] = `FP_ZERO;
        for (int ii=0; ii<N; ii++) begin P_tc[ii*N+ii] = `FP_ONE; x_tc[ii] = `FP_ZERO; end
        ldl_sigma_ref(P_tc, x_tc, `FP_ONE, ref_s);
        run_dut(P_tc, x_tc, `FP_ONE);
        compare_sigma("TC1_Identity", ref_s);

        // TC2 — P=4·I, x=0, γ=UKF_GAMMA
        for (int ii=0; ii<NN; ii++) P_tc[ii] = `FP_ZERO;
        for (int ii=0; ii<N; ii++) begin P_tc[ii*N+ii] = FP_FOUR; x_tc[ii] = `FP_ZERO; end
        ldl_sigma_ref(P_tc, x_tc, `UKF_GAMMA, ref_s);
        run_dut(P_tc, x_tc, `UKF_GAMMA);
        compare_sigma("TC2_4xIdentity", ref_s);

        // TC3 — SPD mixed, x≠0, γ=UKF_GAMMA
        for (int ii=0; ii<NN; ii++) P_tc[ii] = `FP_ZERO;
        P_tc[0*N+0] = `FP_TWO; P_tc[0*N+1] = `FP_ONE;
        P_tc[1*N+0] = `FP_ONE; P_tc[1*N+1] = `FP_TWO;
        P_tc[2*N+2] = `FP_ONE; P_tc[3*N+3] = FP_1P5; P_tc[4*N+4] = FP_PT5;
        x_tc[0] = FP_TENTH; x_tc[1] = FP_N_PT5;
        x_tc[2] = `FP_ZERO; x_tc[3] = FP_PT5;
        x_tc[4] = fp_neg(FP_TENTH);
        ldl_sigma_ref(P_tc, x_tc, `UKF_GAMMA, ref_s);
        run_dut(P_tc, x_tc, `UKF_GAMMA);
        compare_sigma("TC3_Mixed_SPD", ref_s);

        // TC4 — Symmetry: chi[k] + chi[N+k] == 2·x for all k
        begin
            int sym_err = 0;
            logic [DATA_W-1:0] vp, vn, xv;
            for (int sp = 1; sp <= N; sp++)
                for (int el = 0; el < N; el++) begin
                    xv = state_mem[`ADDR_SIGMA + el];
                    vp = state_mem[`ADDR_SIGMA + sp*N + el];
                    vn = state_mem[`ADDR_SIGMA + (N+sp)*N + el];
                    if (!within_tol(fp_add(vp, vn), fp_add(xv, xv))) begin
                        $display("[TC4_Symmetry] FAIL sp=%0d el=%0d", sp, el);
                        sym_err++;
                    end
                end
            if (sym_err == 0) $display("[TC4_Symmetry] PASS");
        end

        $display("--- All tests complete ---");
        $finish;
    end

    initial begin #500_000; $display("GLOBAL TIMEOUT"); $fatal; end

endmodule
