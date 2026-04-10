// ukf_fp_pkg.svh — Opcodes for ukf_fp_engine / PE (63883-style datapath)
`ifndef UKF_FP_PKG_SVH
`define UKF_FP_PKG_SVH

typedef enum logic [3:0] {
    UKF_FP_NOP    = 4'd0,
    UKF_FP_MUL    = 4'd1,
    UKF_FP_ADD    = 4'd2,
    UKF_FP_SUB    = 4'd3,
    UKF_FP_NEG    = 4'd4,
    UKF_FP_DIV    = 4'd5,
    UKF_FP_SQRT   = 4'd6,
    UKF_FP_RECIP  = 4'd7
} ukf_fp_op_e;

`endif
