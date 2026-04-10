// =============================================================
// predict_block.sv — CTRV Model Prediction for All Sigma Points
//
// Applies the Constant Turn Rate and Velocity (CTRV) motion
// model to each of the 2N+1 = 11 sigma points.
//
// CTRV equations  (dt = sample time):
//   If |ψ̇| > ε  (turning):
//     x'    = x + (v/ψ̇)·(sin(ψ + ψ̇·dt) − sin(ψ))
//     y'    = y + (v/ψ̇)·(−cos(ψ + ψ̇·dt) + cos(ψ))
//     v'    = v
//     ψ'    = ψ + ψ̇·dt
//     ψ̇'   = ψ̇
//
//   If |ψ̇| ≤ ε  (straight-line):
//     x'    = x + v·cos(ψ)·dt
//     y'    = y + v·sin(ψ)·dt
//     v'    = v
//     ψ'    = ψ + ψ̇·dt   (match ukf_predictor ctrv / CTRV model; do not freeze ψ)
//     ψ̇'   = ψ̇
//
// For each sigma point:
//   1. Load σ[i] from state memory (5 elements)
//   2. Call CORDIC to compute sin/cos of ψ and ψ+ψ̇·dt
//   3. Compute updated state
//   4. Write predicted sigma point to memory at ADDR_SP + i*N
//
// After processing all 11 sigma points, compute:
//   x̂_pred  = Σ Wm[i] · χ_pred[i]   (ψ component: atan2(sin, cos) wrap, same as ukf_predictor)
//   P_pred  = Σ Wc[i] · (χ_pred[i]−x̂_pred)(χ_pred[i]−x̂_pred)ᵀ + Q   (ψ residual wrapped)
//
// Done signal is asserted when P_pred and x̂_pred are written.
// =============================================================
`include "params.vh"
`include "fp32_math.svh"
`include "ukf_scalar_ops.svh"
`include "ukf_fp_pkg.svh"

module predict_block #(
    parameter int DATA_W  = `DATA_W,
    parameter int FP_FRAC = `FP_FRAC,
    parameter int N       = `N_STATE,
    parameter int N_SIG   = `N_SIGMA
)(
    input  logic                     clk,
    input  logic                     rst,

    // ---- Trigger ----
    input  logic                     start,
    output logic                     done,

    // ---- UKF parameters ----
    input  logic signed [DATA_W-1:0] dt,       // FP32 sample time
    input  logic signed [DATA_W-1:0] wm0,      // Wm[0]
    input  logic signed [DATA_W-1:0] wmi,      // Wm[i>0]
    input  logic signed [DATA_W-1:0] wc0,      // Wc[0]
    input  logic signed [DATA_W-1:0] wci,      // Wc[i>0]

    // ---- State memory read port (port B) ----
    output logic                     mem_rd_en,
    output logic [`ADDR_W-1:0]       mem_rd_addr,
    input  logic [DATA_W-1:0]        mem_rd_data,

    // ---- State memory write port ----
    output logic                     mem_wr_en,
    output logic [`ADDR_W-1:0]       mem_wr_addr,
    output logic [DATA_W-1:0]        mem_wr_data,

    // ---- Result buses to controller ----
    output logic [N*DATA_W-1:0]      x_pred_bus,      // predicted mean (packed)
    output logic                     pred_point_done  // one pulse per sigma point processed
);

    localparam NN         = N * N;
    localparam int MAT_IW = $clog2(NN) + 1; // width of mat_idx / matrix element index
    localparam ACC_W      = 2 * DATA_W;

    // ----------------------------------------------------------
    // FP32 sin/cos via CORDIC
    // ----------------------------------------------------------
    logic                        cord_start;
    logic signed [DATA_W-1:0]    cord_angle;
    logic signed [DATA_W-1:0]    cord_cos, cord_sin;
    logic                        cord_done;

    cordic_fp32 #(
        .DATA_W  (DATA_W),
        .FP_FRAC (FP_FRAC),
        .ITERS   (16)
    ) u_cordic (
        .clk     (clk),
        .rst     (rst),
        .start   (cord_start),
        .angle   (cord_angle),
        .cos_out (cord_cos),
        .sin_out (cord_sin),
        .done    (cord_done)
    );

    logic                     fe_start;
    ukf_fp_op_e               fe_op;
    logic signed [DATA_W-1:0] fe_a, fe_b;
    logic signed [DATA_W-1:0] fe_y;
    logic                     fe_rdy;

    ukf_fp_engine #(.DATA_W(DATA_W)) u_fe (
        .clk    (clk),
        .rst    (rst),
        .start  (fe_start),
        .op     (fe_op),
        .op_a   (fe_a),
        .op_b   (fe_b),
        .result (fe_y),
        .acc    (),
        .rdy    (fe_rdy)
    );

    // ----------------------------------------------------------
    // Local state registers
    // ----------------------------------------------------------
    logic signed [DATA_W-1:0] sp [0:N-1];       // current sigma point
    logic signed [DATA_W-1:0] sp_pred [0:N-1];  // predicted sigma point
    // Accumulate predicted mean and covariance
    logic signed [DATA_W-1:0] xp_acc  [0:N-1];
    logic signed [DATA_W-1:0] pp_acc  [0:NN-1];

    // ----------------------------------------------------------
    // FSM
    // ----------------------------------------------------------
    typedef enum logic [5:0] {
        PB_IDLE,
        PB_LOAD_SP,     // load one sigma point from memory
        PB_WAIT_LOAD,   // pipeline bubble for memory read
        PB_CORD_PSI,    // CORDIC for sin(ψ), cos(ψ)
        PB_WAIT_PSI,
        PB_PT_MUL,      // FE: ψ̇·dt
        PB_PT_MULW,
        PB_PT_ADD,      // FE: ψ + ψ̇·dt
        PB_PT_ADDW,
        PB_WAIT_PSI2,   // CORDIC for sin(ψ+ψ̇·dt), cos(ψ+ψ̇·dt)
        PB_CTRV_ISS,    // issue FP op for CTRV
        PB_CTRV_CAP,    // capture FE result / advance CTRV micro-sequence
        PB_WR_SP,       // write predicted sigma point to memory
        PB_MEAN_MUL,    // Fig 9: weighted mean MAC (FE)
        PB_MEAN_MULW,
        PB_MEAN_ADD,
        PB_MEAN_ADDW,
        PB_ACCUM_COV,   // load χ̃ row from ADDR_SP for covariance pass
        PB_COV_DS_ISS,  // diff element
        PB_COV_DS_CAP,
        PB_COV_PM_ISS,  // MUL diff_rr * diff_cc
        PB_COV_PM_CAP,
        PB_COV_WM_ISS,  // MUL wc * prod
        PB_COV_WM_CAP,
        PB_COV_PA_ISS,  // ADD into pp_acc
        PB_COV_PA_CAP,
        PB_LOAD_Q,      // read Q element
        PB_ADDQ_ISS,    // pp_acc += Q via FE
        PB_ADDQ_CAP,
        PB_SYM_A_ISS,   // symmetrize P (Fig 9 style)
        PB_SYM_A_CAP,
        PB_SYM_H_ISS,
        PB_SYM_H_CAP,
        PB_SYM_E_ISS,
        PB_SYM_E_CAP,
        PB_SYM_ADV,
        PB_WR_XPRED,    // write x_pred to memory
        PB_WR_PPRED,    // write P_pred to memory
        PB_DONE
    } pb_state_t;

    pb_state_t            pb_state;
    logic [3:0]           sig_idx;    // current sigma point index (0..10)
    logic [2:0]           elem_idx;   // element within state vector
    logic [$clog2(NN):0]  mat_idx;    // element within N×N matrix

    // CORDIC results cached
    logic signed [DATA_W-1:0] sin_psi,  cos_psi;
    logic signed [DATA_W-1:0] sin_psi2, cos_psi2;

    logic                     ctrv_turn;
    logic [4:0]               ctrv_step;
    logic signed [DATA_W-1:0] ctrv_r0, ctrv_r1, ctrv_r2, ctrv_r3;

    logic signed [DATA_W-1:0] wm_hold;
    logic [2:0]                mean_jj;
    logic signed [DATA_W-1:0] fe_scratch;
    logic [2:0]                cov_jj, cov_rr, cov_cc;
    logic signed [DATA_W-1:0] diff_mem [0:N-1];
    logic signed [DATA_W-1:0] wc_hold;
    logic signed [DATA_W-1:0] t_cov1;
    logic [4:0]                sym_lin;
    logic [2:0]                sym_rr, sym_cc;
    logic signed [DATA_W-1:0] t_sym0, t_sym1;

    // ----------------------------------------------------------
    // Sequential FSM
    // ----------------------------------------------------------
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            pb_state       <= PB_IDLE;
            done           <= 1'b0;
            pred_point_done<= 1'b0;
            mem_rd_en      <= 1'b0;
            mem_wr_en      <= 1'b0;
            cord_start     <= 1'b0;
            fe_start       <= 1'b0;
            sig_idx        <= '0;
            elem_idx       <= '0;
            mat_idx        <= '0;
            ctrv_step      <= '0;
            mean_jj        <= '0;
            cov_jj         <= '0;
            cov_rr         <= '0;
            cov_cc         <= '0;
            sym_lin        <= '0;
            wm_hold        <= '0;
            wc_hold        <= '0;
            fe_scratch     <= '0;
            t_cov1         <= '0;
            t_sym0         <= '0;
            t_sym1         <= '0;
            for (int ii=0; ii<N; ii++) begin
                xp_acc[ii] <= '0;
                sp[ii]     <= '0;
                sp_pred[ii]<= '0;
            end
            for (int ii=0; ii<NN; ii++)
                pp_acc[ii] <= '0;
        end else begin
            done            <= 1'b0;
            pred_point_done <= 1'b0;
            cord_start      <= 1'b0;
            mem_rd_en       <= 1'b0;
            mem_wr_en       <= 1'b0;
            fe_start        <= 1'b0;

            case (pb_state)
            // -----------------------------------------------
            PB_IDLE: begin
                if (start) begin
                    sig_idx  <= '0;
                    elem_idx <= '0;
                    // Clear accumulators
                    for (int ii=0; ii<N; ii++)  xp_acc[ii] <= '0;
                    for (int ii=0; ii<NN; ii++) pp_acc[ii] <= '0;
                    pb_state <= PB_LOAD_SP;
                end
            end

            // -----------------------------------------------
            // Load sigma point sig_idx from memory (N elements)
            // Address: ADDR_SIGMA + sig_idx*N + elem_idx
            // -----------------------------------------------
            PB_LOAD_SP: begin
                mem_rd_en   <= 1'b1;
                mem_rd_addr <= `ADDR_SIGMA
                               + sig_idx * N[`ADDR_W-1:0]
                               + {{(`ADDR_W-4){1'b0}}, elem_idx};

                pb_state <= PB_WAIT_LOAD;
            end

            PB_WAIT_LOAD: begin
                // Capture data from synchronous read
                sp[elem_idx] <= $signed(mem_rd_data);

                elem_idx <= elem_idx + 1;
                if (elem_idx == N[2:0] - 1) begin
                    elem_idx <= '0;
                    // Issue CORDIC for ψ  (sp[3])
                    cord_start <= 1'b1;
                    cord_angle <= sp[3]; // will be overwritten after load
                    pb_state   <= PB_CORD_PSI;
                end else begin
                    pb_state <= PB_LOAD_SP;
                end
            end

            // -----------------------------------------------
            // CORDIC: sin(ψ), cos(ψ)
            // -----------------------------------------------
            PB_CORD_PSI: begin
                cord_start <= 1'b1;
                cord_angle <= sp[3];  // ψ = sp[3]
                pb_state   <= PB_WAIT_PSI;
            end

            PB_WAIT_PSI: begin
                if (cord_done) begin
                    sin_psi <= cord_sin;
                    cos_psi <= cord_cos;
                    pb_state <= PB_PT_MUL;
                end
            end

            PB_PT_MUL: begin
                fe_start <= 1'b1;
                fe_op    <= UKF_FP_MUL;
                fe_a     <= sp[4];
                fe_b     <= dt;
                pb_state <= PB_PT_MULW;
            end
            PB_PT_MULW: begin
                if (fe_rdy) begin
                    ctrv_r0  <= fe_y;
                    pb_state <= PB_PT_ADD;
                end
            end
            PB_PT_ADD: begin
                fe_start <= 1'b1;
                fe_op    <= UKF_FP_ADD;
                fe_a     <= sp[3];
                fe_b     <= ctrv_r0;
                pb_state <= PB_PT_ADDW;
            end
            PB_PT_ADDW: begin
                if (fe_rdy) begin
                    cord_angle <= fe_y;
                    cord_start <= 1'b1;
                    pb_state   <= PB_WAIT_PSI2;
                end
            end

            PB_WAIT_PSI2: begin
                if (cord_done) begin
                    sin_psi2  <= cord_sin;
                    cos_psi2  <= cord_cos;
                    ctrv_turn <= fp_abs_gt_eps(sp[4], `FP_EPSILON);
                    ctrv_step <= '0;
                    pb_state  <= PB_CTRV_ISS;
                end
            end

            // -----------------------------------------------
            // CTRV via ukf_fp_engine (one op per ISS/CAP pair)
            // -----------------------------------------------
            PB_CTRV_ISS: begin
                if (ctrv_turn) begin
                    unique case (ctrv_step)
                    5'd0: begin
                        fe_start <= 1'b1;
                        fe_op    <= UKF_FP_RECIP;
                        fe_a     <= sp[4];
                        fe_b     <= sp[4];
                        pb_state <= PB_CTRV_CAP;
                    end
                    5'd1: begin
                        fe_start <= 1'b1;
                        fe_op    <= UKF_FP_MUL;
                        fe_a     <= sp[2];
                        fe_b     <= ctrv_r0;
                        pb_state <= PB_CTRV_CAP;
                    end
                    5'd2: begin
                        fe_start <= 1'b1;
                        fe_op    <= UKF_FP_SUB;
                        fe_a     <= sin_psi2;
                        fe_b     <= sin_psi;
                        pb_state <= PB_CTRV_CAP;
                    end
                    5'd3: begin
                        fe_start <= 1'b1;
                        fe_op    <= UKF_FP_MUL;
                        fe_a     <= ctrv_r1;
                        fe_b     <= ctrv_r2;
                        pb_state <= PB_CTRV_CAP;
                    end
                    5'd4: begin
                        fe_start <= 1'b1;
                        fe_op    <= UKF_FP_ADD;
                        fe_a     <= sp[0];
                        fe_b     <= ctrv_r3;
                        pb_state <= PB_CTRV_CAP;
                    end
                    5'd5: begin
                        fe_start <= 1'b1;
                        fe_op    <= UKF_FP_SUB;
                        fe_a     <= cos_psi;
                        fe_b     <= cos_psi2;
                        pb_state <= PB_CTRV_CAP;
                    end
                    5'd6: begin
                        fe_start <= 1'b1;
                        fe_op    <= UKF_FP_MUL;
                        fe_a     <= ctrv_r1;
                        fe_b     <= ctrv_r2;
                        pb_state <= PB_CTRV_CAP;
                    end
                    5'd7: begin
                        fe_start <= 1'b1;
                        fe_op    <= UKF_FP_ADD;
                        fe_a     <= sp[1];
                        fe_b     <= ctrv_r3;
                        pb_state <= PB_CTRV_CAP;
                    end
                    5'd8: begin
                        sp_pred[2] <= sp[2];
                        ctrv_step  <= 5'd9;
                        pb_state   <= PB_CTRV_ISS;
                    end
                    5'd9: begin
                        fe_start <= 1'b1;
                        fe_op    <= UKF_FP_MUL;
                        fe_a     <= sp[4];
                        fe_b     <= dt;
                        pb_state <= PB_CTRV_CAP;
                    end
                    5'd10: begin
                        fe_start <= 1'b1;
                        fe_op    <= UKF_FP_ADD;
                        fe_a     <= sp[3];
                        fe_b     <= ctrv_r0;
                        pb_state <= PB_CTRV_CAP;
                    end
                    5'd11: begin
                        sp_pred[4] <= sp[4];
                        elem_idx   <= '0;
                        pb_state   <= PB_WR_SP;
                    end
                    default: pb_state <= PB_IDLE;
                    endcase
                end else begin
                    unique case (ctrv_step)
                    5'd0: begin
                        fe_start <= 1'b1;
                        fe_op    <= UKF_FP_MUL;
                        fe_a     <= sp[2];
                        fe_b     <= cos_psi;
                        pb_state <= PB_CTRV_CAP;
                    end
                    5'd1: begin
                        fe_start <= 1'b1;
                        fe_op    <= UKF_FP_MUL;
                        fe_a     <= ctrv_r0;
                        fe_b     <= dt;
                        pb_state <= PB_CTRV_CAP;
                    end
                    5'd2: begin
                        fe_start <= 1'b1;
                        fe_op    <= UKF_FP_ADD;
                        fe_a     <= sp[0];
                        fe_b     <= ctrv_r1;
                        pb_state <= PB_CTRV_CAP;
                    end
                    5'd3: begin
                        fe_start <= 1'b1;
                        fe_op    <= UKF_FP_MUL;
                        fe_a     <= sp[2];
                        fe_b     <= sin_psi;
                        pb_state <= PB_CTRV_CAP;
                    end
                    5'd4: begin
                        fe_start <= 1'b1;
                        fe_op    <= UKF_FP_MUL;
                        fe_a     <= ctrv_r0;
                        fe_b     <= dt;
                        pb_state <= PB_CTRV_CAP;
                    end
                    5'd5: begin
                        fe_start <= 1'b1;
                        fe_op    <= UKF_FP_ADD;
                        fe_a     <= sp[1];
                        fe_b     <= ctrv_r1;
                        pb_state <= PB_CTRV_CAP;
                    end
                    5'd6: begin
                        fe_start <= 1'b1;
                        fe_op    <= UKF_FP_MUL;
                        fe_a     <= sp[4];
                        fe_b     <= dt;
                        pb_state <= PB_CTRV_CAP;
                    end
                    5'd7: begin
                        fe_start <= 1'b1;
                        fe_op    <= UKF_FP_ADD;
                        fe_a     <= sp[3];
                        fe_b     <= ctrv_r0;
                        pb_state <= PB_CTRV_CAP;
                    end
                    5'd8: begin
                        sp_pred[0] <= ctrv_r2;
                        sp_pred[1] <= ctrv_r3;
                        sp_pred[2] <= sp[2];
                        sp_pred[4] <= sp[4];
                        elem_idx   <= '0;
                        pb_state   <= PB_WR_SP;
                    end
                    default: pb_state <= PB_IDLE;
                    endcase
                end
            end

            PB_CTRV_CAP: begin
                if (fe_rdy) begin
                if (ctrv_turn) begin
                    unique case (ctrv_step)
                    5'd0: begin
                        ctrv_r0   <= fe_y;
                        ctrv_step <= 5'd1;
                        pb_state  <= PB_CTRV_ISS;
                    end
                    5'd1: begin
                        ctrv_r1   <= fe_y;
                        ctrv_step <= 5'd2;
                        pb_state  <= PB_CTRV_ISS;
                    end
                    5'd2: begin
                        ctrv_r2   <= fe_y;
                        ctrv_step <= 5'd3;
                        pb_state  <= PB_CTRV_ISS;
                    end
                    5'd3: begin
                        ctrv_r3   <= fe_y;
                        ctrv_step <= 5'd4;
                        pb_state  <= PB_CTRV_ISS;
                    end
                    5'd4: begin
                        sp_pred[0] <= fe_y;
                        ctrv_step  <= 5'd5;
                        pb_state   <= PB_CTRV_ISS;
                    end
                    5'd5: begin
                        ctrv_r2   <= fe_y;
                        ctrv_step <= 5'd6;
                        pb_state  <= PB_CTRV_ISS;
                    end
                    5'd6: begin
                        ctrv_r3   <= fe_y;
                        ctrv_step <= 5'd7;
                        pb_state  <= PB_CTRV_ISS;
                    end
                    5'd7: begin
                        sp_pred[1] <= fe_y;
                        ctrv_step  <= 5'd8;
                        pb_state   <= PB_CTRV_ISS;
                    end
                    5'd9: begin
                        ctrv_r0   <= fe_y;
                        ctrv_step <= 5'd10;
                        pb_state  <= PB_CTRV_ISS;
                    end
                    5'd10: begin
                        sp_pred[3] <= fe_y;
                        ctrv_step  <= 5'd11;
                        pb_state   <= PB_CTRV_ISS;
                    end
                    default: pb_state <= PB_IDLE;
                    endcase
                end else begin
                    unique case (ctrv_step)
                    5'd0: begin
                        ctrv_r0   <= fe_y;
                        ctrv_step <= 5'd1;
                        pb_state  <= PB_CTRV_ISS;
                    end
                    5'd1: begin
                        ctrv_r1   <= fe_y;
                        ctrv_step <= 5'd2;
                        pb_state  <= PB_CTRV_ISS;
                    end
                    5'd2: begin
                        ctrv_r2   <= fe_y;
                        ctrv_step <= 5'd3;
                        pb_state  <= PB_CTRV_ISS;
                    end
                    5'd3: begin
                        ctrv_r0   <= fe_y;
                        ctrv_step <= 5'd4;
                        pb_state  <= PB_CTRV_ISS;
                    end
                    5'd4: begin
                        ctrv_r1   <= fe_y;
                        ctrv_step <= 5'd5;
                        pb_state  <= PB_CTRV_ISS;
                    end
                    5'd5: begin
                        ctrv_r3   <= fe_y;
                        ctrv_step <= 5'd6;
                        pb_state  <= PB_CTRV_ISS;
                    end
                    5'd6: begin
                        ctrv_r0   <= fe_y;
                        ctrv_step <= 5'd7;
                        pb_state  <= PB_CTRV_ISS;
                    end
                    5'd7: begin
                        sp_pred[3] <= fe_y;
                        ctrv_step  <= 5'd8;
                        pb_state   <= PB_CTRV_ISS;
                    end
                    default: pb_state <= PB_IDLE;
                    endcase
                end
                end
            end

            // -----------------------------------------------
            // Write predicted sigma point to ADDR_SP area
            // -----------------------------------------------
            PB_WR_SP: begin
                mem_wr_en   <= 1'b1;
                mem_wr_addr <= `ADDR_SP
                               + sig_idx * N[`ADDR_W-1:0]
                               + {{(`ADDR_W-4){1'b0}}, elem_idx};
                mem_wr_data <= sp_pred[elem_idx];

                elem_idx <= elem_idx + 1;
                if (elem_idx == N[2:0] - 1) begin
                    elem_idx        <= '0;
                    pred_point_done <= 1'b1;
                    wm_hold         <= (sig_idx == 0) ? wm0 : wmi;
                    mean_jj         <= '0;
                    pb_state        <= PB_MEAN_MUL;
                end
            end

            // -----------------------------------------------
            // Weighted mean: xp_acc[j] += Wm·sp_pred[j] (Fig 9, FE)
            // -----------------------------------------------
            PB_MEAN_MUL: begin
                fe_start <= 1'b1;
                fe_op    <= UKF_FP_MUL;
                fe_a     <= wm_hold;
                fe_b     <= sp_pred[mean_jj];
                pb_state <= PB_MEAN_MULW;
            end
            PB_MEAN_MULW: begin
                if (fe_rdy) begin
                    fe_scratch <= fe_y;
                    pb_state   <= PB_MEAN_ADD;
                end
            end
            PB_MEAN_ADD: begin
                fe_start <= 1'b1;
                fe_op    <= UKF_FP_ADD;
                fe_a     <= xp_acc[mean_jj];
                fe_b     <= fe_scratch;
                pb_state <= PB_MEAN_ADDW;
            end
            PB_MEAN_ADDW: begin
                if (fe_rdy) begin
                    if (mean_jj == 3'd3) begin
                        xp_acc[3] <= fp_norm_angle_bits(fe_y);
                        if (sig_idx == N_SIG[3:0] - 1)
                            x_pred_bus[3 * DATA_W +: DATA_W] <= fp_norm_angle_bits(fe_y);
                    end else begin
                        xp_acc[mean_jj] <= fe_y;
                        if (sig_idx == N_SIG[3:0] - 1)
                            x_pred_bus[mean_jj * DATA_W +: DATA_W] <= fe_y;
                    end
                    if (mean_jj == N[2:0] - 1) begin
                        if (sig_idx == N_SIG[3:0] - 1) begin
                            sig_idx  <= '0;
                            elem_idx <= '0;
                            mat_idx  <= '0;
                            pb_state <= PB_ACCUM_COV;
                        end else begin
                            sig_idx  <= sig_idx + 1;
                            pb_state <= PB_LOAD_SP;
                        end
                    end else begin
                        mean_jj  <= mean_jj + 1;
                        pb_state <= PB_MEAN_MUL;
                    end
                end
            end

            // -----------------------------------------------
            // Covariance: load χ̃ then FE residual + weighted outer sum
            // -----------------------------------------------
            PB_ACCUM_COV: begin
                mem_rd_en   <= 1'b1;
                mem_rd_addr <= `ADDR_SP
                               + sig_idx * N[`ADDR_W-1:0]
                               + {{(`ADDR_W-4){1'b0}}, elem_idx};

                if (elem_idx > 0)
                    sp[elem_idx-1] <= $signed(mem_rd_data);

                elem_idx <= elem_idx + 1;
                if (elem_idx == N[2:0]) begin
                    sp[N-1]  <= $signed(mem_rd_data);
                    elem_idx <= '0;
                    cov_jj   <= '0;
                    pb_state <= PB_COV_DS_ISS;
                end
            end

            PB_COV_DS_ISS: begin
                fe_start <= 1'b1;
                fe_op    <= UKF_FP_SUB;
                fe_a     <= sp[cov_jj];
                fe_b     <= xp_acc[cov_jj];
                pb_state <= PB_COV_DS_CAP;
            end
            PB_COV_DS_CAP: begin
                if (fe_rdy) begin
                    if (cov_jj == 3'd3)
                        diff_mem[3] <= fp_norm_angle_bits(fe_y);
                    else
                        diff_mem[cov_jj] <= fe_y;
                    if (cov_jj == N[2:0] - 1) begin
                        wc_hold <= (sig_idx == 0) ? wc0 : wci;
                        cov_rr  <= '0;
                        cov_cc  <= '0;
                        pb_state <= PB_COV_PM_ISS;
                    end else begin
                        cov_jj  <= cov_jj + 1;
                        pb_state <= PB_COV_DS_ISS;
                    end
                end
            end

            PB_COV_PM_ISS: begin
                fe_start <= 1'b1;
                fe_op    <= UKF_FP_MUL;
                fe_a     <= diff_mem[cov_rr];
                fe_b     <= diff_mem[cov_cc];
                pb_state <= PB_COV_PM_CAP;
            end
            PB_COV_PM_CAP: begin
                if (fe_rdy) begin
                    fe_scratch <= fe_y;
                    pb_state   <= PB_COV_WM_ISS;
                end
            end
            PB_COV_WM_ISS: begin
                fe_start <= 1'b1;
                fe_op    <= UKF_FP_MUL;
                fe_a     <= wc_hold;
                fe_b     <= fe_scratch;
                pb_state <= PB_COV_WM_CAP;
            end
            PB_COV_WM_CAP: begin
                if (fe_rdy) begin
                    t_cov1   <= fe_y;
                    pb_state <= PB_COV_PA_ISS;
                end
            end
            PB_COV_PA_ISS: begin
                fe_start <= 1'b1;
                fe_op    <= UKF_FP_ADD;
                fe_a     <= pp_acc[cov_rr * N + cov_cc];
                fe_b     <= t_cov1;
                pb_state <= PB_COV_PA_CAP;
            end
            PB_COV_PA_CAP: begin
                if (fe_rdy) begin
                    pp_acc[cov_rr * N + cov_cc] <= fe_y;
                    if (cov_rr == N[2:0] - 1 && cov_cc == N[2:0] - 1) begin
                        if (sig_idx == N_SIG[3:0] - 1) begin
                            mat_idx  <= '0;
                            pb_state <= PB_LOAD_Q;
                        end else begin
                            sig_idx  <= sig_idx + 1;
                            elem_idx <= '0;
                            pb_state <= PB_ACCUM_COV;
                        end
                    end else if (cov_cc == N[2:0] - 1) begin
                        cov_cc <= '0;
                        cov_rr <= cov_rr + 1;
                        pb_state <= PB_COV_PM_ISS;
                    end else begin
                        cov_cc <= cov_cc + 1;
                        pb_state <= PB_COV_PM_ISS;
                    end
                end
            end

            // -----------------------------------------------
            // Add process noise Q (read from state memory)
            // -----------------------------------------------
            PB_LOAD_Q: begin
                mem_rd_en   <= 1'b1;
                mem_rd_addr <= `ADDR_Q + {{(`ADDR_W-MAT_IW){1'b0}}, mat_idx};
                pb_state    <= PB_ADDQ_ISS;
            end

            PB_ADDQ_ISS: begin
                fe_start <= 1'b1;
                fe_op    <= UKF_FP_ADD;
                fe_a     <= pp_acc[mat_idx];
                fe_b     <= $signed(mem_rd_data);
                pb_state <= PB_ADDQ_CAP;
            end
            PB_ADDQ_CAP: begin
                if (fe_rdy) begin
                    pp_acc[mat_idx] <= fe_y;
                    if (mat_idx == NN - 1) begin
                        sym_lin <= '0;
                        pb_state <= PB_SYM_A_ISS;
                    end else begin
                        mat_idx <= mat_idx + 1;
                        pb_state <= PB_LOAD_Q;
                    end
                end
            end

            // -----------------------------------------------
            // Symmetrize P_pred: 0.5·(P+Pᵀ)+ε·I via FE
            // -----------------------------------------------
            PB_SYM_A_ISS: begin
                sym_rr   <= sym_lin / N[2:0];
                sym_cc   <= sym_lin % N[2:0];
                fe_start <= 1'b1;
                fe_op    <= UKF_FP_ADD;
                fe_a     <= pp_acc[(sym_lin / N[2:0]) * N + (sym_lin % N[2:0])];
                fe_b     <= pp_acc[(sym_lin % N[2:0]) * N + (sym_lin / N[2:0])];
                pb_state <= PB_SYM_A_CAP;
            end
            PB_SYM_A_CAP: begin
                if (fe_rdy) begin
                    t_sym0   <= fe_y;
                    pb_state <= PB_SYM_H_ISS;
                end
            end
            PB_SYM_H_ISS: begin
                fe_start <= 1'b1;
                fe_op    <= UKF_FP_MUL;
                fe_a     <= `FP_HALF;
                fe_b     <= t_sym0;
                pb_state <= PB_SYM_H_CAP;
            end
            PB_SYM_H_CAP: begin
                if (fe_rdy) begin
                    t_sym1 <= fe_y;
                    if (sym_rr == sym_cc)
                        pb_state <= PB_SYM_E_ISS;
                    else begin
                        pp_acc[sym_rr * N + sym_cc] <= fe_y;
                        pb_state <= PB_SYM_ADV;
                    end
                end
            end
            PB_SYM_E_ISS: begin
                fe_start <= 1'b1;
                fe_op    <= UKF_FP_ADD;
                fe_a     <= t_sym1;
                fe_b     <= `FP_EPSILON;
                pb_state <= PB_SYM_E_CAP;
            end
            PB_SYM_E_CAP: begin
                if (fe_rdy) begin
                    pp_acc[sym_rr * N + sym_cc] <= fe_y;
                    pb_state <= PB_SYM_ADV;
                end
            end
            PB_SYM_ADV: begin
                if (sym_lin == NN[$clog2(NN):0] - 1) begin
                    elem_idx <= '0;
                    pb_state <= PB_WR_XPRED;
                end else begin
                    sym_lin  <= sym_lin + 1;
                    pb_state <= PB_SYM_A_ISS;
                end
            end

            // -----------------------------------------------
            // Write x_pred to memory ADDR_XPRED
            // -----------------------------------------------
            PB_WR_XPRED: begin
                mem_wr_en   <= 1'b1;
                mem_wr_addr <= `ADDR_XPRED + {{(`ADDR_W-4){1'b0}}, elem_idx};
                mem_wr_data <= xp_acc[elem_idx];

                elem_idx <= elem_idx + 1;
                if (elem_idx == N[2:0] - 1) begin
                    mat_idx  <= '0;
                    pb_state <= PB_WR_PPRED;
                end
            end

            // -----------------------------------------------
            // Write P_pred to memory ADDR_PPRED
            // -----------------------------------------------
            PB_WR_PPRED: begin
                mem_wr_en   <= 1'b1;
                mem_wr_addr <= `ADDR_PPRED + {{(`ADDR_W-MAT_IW){1'b0}}, mat_idx};
                mem_wr_data <= pp_acc[mat_idx];

                mat_idx <= mat_idx + 1;
                if (mat_idx == NN - 1)
                    pb_state <= PB_DONE;
            end

            // -----------------------------------------------
            PB_DONE: begin
                done     <= 1'b1;
                pb_state <= PB_IDLE;
            end
            endcase
        end
    end

endmodule
