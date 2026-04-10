// ukf_scalar_ops.svh — Typed add/sub/neg for UKF datapath words
//
// IEEE-754 single-precision (USE_FP32) only.
// Q8.24 fixed-point support has been removed.
//
`ifndef UKF_SCALAR_OPS_SVH
`define UKF_SCALAR_OPS_SVH

function automatic logic signed [31:0] ukf_add;
    input logic signed [31:0] a, b;
    ukf_add = fp_add(a, b);
endfunction

function automatic logic signed [31:0] ukf_sub;
    input logic signed [31:0] a, b;
    ukf_sub = fp_sub(a, b);
endfunction

function automatic logic signed [31:0] ukf_neg;
    input logic signed [31:0] a;
    ukf_neg = fp_neg(a);
endfunction

`endif // UKF_SCALAR_OPS_SVH
