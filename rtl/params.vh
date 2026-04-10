`ifndef UKF_PARAMS_VH
`define UKF_PARAMS_VH
// ============================================================
// UKF Sensor Fusion IP — Global Parameter Definitions
//
// Arithmetic: IEEE-754 single-precision (float32) throughout.
// Q8.24 fixed-point has been removed.
// ============================================================

// Always FP32 — no conditional compilation needed in any module.
`define USE_FP32

// ---- Data widths -----------------------------------------------
`define DATA_W      32
`define FP_FRAC     24   // legacy parameter passed to cordic_fp32; not used for arithmetic
`define FP_INT       8   // legacy — kept so existing parameter declarations compile
`define ADDR_W       8   // state-memory word address width (256 words)

// ---- IEEE-754 single-precision bit patterns --------------------
`define FP_ZERO     32'h0000_0000   //  0.0
`define FP_ONE      32'h3F80_0000   //  1.0
`define FP_TWO      32'h4000_0000   //  2.0
`define FP_HALF     32'h3F00_0000   //  0.5
`define FP_QUARTER  32'h3E80_0000   //  0.25
`define FP_NEG_ONE  32'hBF80_0000   // -1.0
`define FP_PI       32'h4049_0FDB   //  π
`define FP_PI_2     32'h3FC9_0FDB   //  π/2
`define FP_NEG_PI   32'hC049_0FDB   // -π
`define FP_NEG_PI_2 32'hBFC9_0FDB   // -π/2
`define FP_MAX      32'h7F7F_FFFF   // max finite float32
`define FP_MIN      32'hFF7F_FFFF   // min finite float32
`define FP_EPSILON  32'h3586_37BD   // ≈ 1.0e-6
// Added to P diagonal after full Joseph update (mitigates FP32 near-indefinite P, large dt).
// 1e-3 was insufficient: ψ̇ diagonal could still go ~−1e−3 after Joseph → LDL j=4 fails.
`define FP_P_DIAG_LOAD 32'h3C23_D70A   // ≈ 1.0e-2

// ---- UKF dimensions -------------------------------------------
`define N_STATE     5    // [x, y, v, ψ, ψ̇]
`define N_SIGMA    11    // 2·N + 1

// ---- UKF tuning (α=0.1, β=2, κ=0) — matches tracking_ship Python ---
// λ = α²(N+κ) − N = 0.01×5 − 5 = −4.95
// Wm[0]   = λ/(N+λ) = −4.95/0.05 = −99
// Wc[0]   = Wm[0] + (1−α²+β) = −99 + 2.99 = −96.01
// Wm/c[i] = 1/(2(N+λ)) = 1/0.1 = 10   for i = 1…2N
// γ       = √(N+λ) = √0.05 ≈ 0.22361
`define UKF_LAMBDA  32'hC09E_6666   // −4.95
`define UKF_WM0     32'hC2C6_0000   // −99.0
`define UKF_WC0     32'hC2C0_0A3D   // −96.01
`define UKF_WMI     32'h4120_0000   //  10.0
`define UKF_WCI     32'h4120_0000   //  10.0
`define UKF_GAMMA   32'h3E64_E410   //  0.22361

// ---- Default sample time (AXI-writable via REG_DT 0x1C) --------
`define DT_DEFAULT  32'h3D23_D70A   // dt = 0.04 s  (IEEE 754)
`define DT_ONE      32'h3F80_0000   // dt = 1.0 s   (IEEE 754)
// Legacy aliases
`define DT_Q824_DEFAULT `DT_DEFAULT
`define DT_Q824_ONE     `DT_ONE

// ---- State memory address map (32-bit word offsets) ------------
//  x[5]           : words   0 –   4   (5 words)
//  P[5×5]         : words   5 –  29   (25 words, row-major)
//  Q[5×5]         : words  30 –  54   (25 words, row-major)
//  R_gps[2×2]     : words  55 –  58   (4 words)
//  R_imu[2×2]     : words  59 –  62   (4 words)
//  R_odom[1×1]    : word   63         (1 word)
//  sigma[11×5]    : words  64 – 118   (55 words, row-major)
//  sigma_pred[11×5]: words 119 – 173  (55 words)
//  x_pred[5]      : words 174 – 178   (5 words)
//  P_pred[5×5]    : words 179 – 203   (25 words)
//  L_UKF[5×5]     : words 204 – 228   (25 words, unit-lower LDL factor; upper=0)
//  D_UKF[5]       : words 229 – 233   (LDL diagonal; written by sigma_point_generator)
//  scratch free   : words 234 – 255   (22 words)
`define ADDR_X       8'd0
`define ADDR_P       8'd5
`define ADDR_Q       8'd30
`define ADDR_R_GPS   8'd55
`define ADDR_R_IMU   8'd59
`define ADDR_R_ODOM  8'd63
`define ADDR_SIGMA   8'd64
`define ADDR_SP      8'd119
`define ADDR_XPRED   8'd174
`define ADDR_PPRED   8'd179
`define ADDR_SCRATCH 8'd204
`define ADDR_L_UKF   8'd204
`define ADDR_D_UKF   8'd229

// ---- FSM state encoding ----------------------------------------
`define FSM_IDLE        4'd0
`define FSM_SIGMA_GEN   4'd1
`define FSM_PREDICT     4'd2
`define FSM_PRED_MEAN   4'd3
`define FSM_UPDATE_GPS  4'd4
`define FSM_UPDATE_IMU  4'd5
`define FSM_UPDATE_ODOM 4'd6
`define FSM_WRITEBACK   4'd7
`define FSM_ERROR       4'd8

// ---- Math-core operation codes ---------------------------------
`define MATH_ADD        4'd0
`define MATH_SUB        4'd1
`define MATH_MUL        4'd2
`define MATH_TRANS      4'd3
`define MATH_CHOL       4'd4
`define MATH_INV        4'd5
`define MATH_SCALE      4'd6   // scalar × matrix
`define MATH_OUTER      4'd7   // outer product (vec × vecᵀ)

`endif // UKF_PARAMS_VH
