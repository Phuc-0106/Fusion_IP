// =============================================================
// update_block.sv — UKF measurement update (Fig 10, 5-state, non-augmented)
//
// All FP through ukf_fp_engine. Joseph-form covariance update.
// =============================================================
`include "params.vh"
`include "fp32_math.svh"
`include "ukf_scalar_ops.svh"
`include "ukf_fp_pkg.svh"

module update_block #(
    parameter int DATA_W  = `DATA_W,
    parameter int FP_FRAC = `FP_FRAC,
    parameter int N       = `N_STATE
)(
    input  logic                     clk,
    input  logic                     rst,

    input  logic                     start,
    input  logic [2:0]               sensor_valid_map,
    output logic                     done,
    output logic                     upd_err,

    input  logic signed [DATA_W-1:0] meas_gps_x,
    input  logic signed [DATA_W-1:0] meas_gps_y,
    input  logic signed [DATA_W-1:0] meas_imu_psi,
    input  logic signed [DATA_W-1:0] meas_imu_dot,
    input  logic signed [DATA_W-1:0] meas_odom_v,

    output logic                     mem_rd_en,
    output logic [`ADDR_W-1:0]       mem_rd_addr,
    input  logic [DATA_W-1:0]        mem_rd_data,

    output logic                     mem_wr_en,
    output logic [`ADDR_W-1:0]       mem_wr_addr,
    output logic [DATA_W-1:0]        mem_wr_data,

    output logic [N*DATA_W-1:0]      update_result
);

    localparam NN         = N * N;
    localparam int MAT_IW = $clog2(NN) + 1;
    localparam M_MAX      = 2;

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

    logic signed [DATA_W-1:0] x_work [0:N-1];
    logic signed [DATA_W-1:0] P_work [0:NN-1];

    logic signed [DATA_W-1:0] z_meas  [0:M_MAX-1];
    logic signed [DATA_W-1:0] innov   [0:M_MAX-1];
    logic signed [DATA_W-1:0] S_inv   [0:M_MAX*M_MAX-1];
    // P·Hᵀ (N×M); must not alias K_gain — K is computed column-wise and overwrites K_gain per column.
    logic signed [DATA_W-1:0] P_HT    [0:N*M_MAX-1];
    logic signed [DATA_W-1:0] K_gain  [0:N*M_MAX-1];

    logic signed [DATA_W-1:0] IKH_mem [0:NN-1];
    logic signed [DATA_W-1:0] T1_mem  [0:NN-1];
    logic signed [DATA_W-1:0] T2_mem   [0:NN-1];
    logic signed [DATA_W-1:0] P_new_m  [0:NN-1];
    logic signed [DATA_W-1:0] dot_acc;
    logic signed [DATA_W-1:0] krk_acc;

    typedef enum logic [6:0] {
        UB_IDLE,
        UB_LOAD_X,
        UB_LOAD_P,
        UB_START_GPS,
        UB_R_GPS_A,
        UB_R_GPS_B,
        UB_START_IMU,
        UB_R_IMU_A,
        UB_R_IMU_B,
        UB_START_ODOM,
        UB_R_ODOM_CAP,
        UB_INN_ISS,
        UB_INN_CAP,
        UB_S2_CP,
        UB_S2_A00_ISS,
        UB_S2_A00_CAP,
        UB_S2_A11_ISS,
        UB_S2_A11_CAP,
        UB_S1_A_ISS,
        UB_S1_A_CAP,
        UB_S1_R_ISS,
        UB_S1_R_CAP,
        UB_IV_M0_ISS,
        UB_IV_M0_CAP,
        UB_IV_M1_ISS,
        UB_IV_M1_CAP,
        UB_IV_DS_ISS,
        UB_IV_DS_CAP,
        UB_IV_R_ISS,
        UB_IV_R_CAP,
        UB_IV_I00_ISS,
        UB_IV_I00_CAP,
        UB_IV_I01_ISS,
        UB_IV_I01_CAP,
        UB_IV_I01N_ISS,
        UB_IV_I01N_CAP,
        UB_IV_I10_ISS,
        UB_IV_I10_CAP,
        UB_IV_I10N_ISS,
        UB_IV_I10N_CAP,
        UB_IV_I11_ISS,
        UB_IV_I11_CAP,
        UB_CROSS_COV,
        UB_KG_MUL_ISS,
        UB_KG_MUL_CAP,
        UB_KG_ADD_ISS,
        UB_KG_ADD_CAP,
        UB_SU_KM_ISS,
        UB_SU_KM_CAP,
        UB_SU_KA_ISS,
        UB_SU_KA_CAP,
        UB_SU_XA_ISS,
        UB_SU_XA_CAP,
        UB_SU_ADV,
        UB_PJ_IKH0,
        UB_PJ_IKHM_ISS,
        UB_PJ_IKHM_CAP,
        UB_PJ_IKH_FIN,
        UB_PJ_IKH_FCAP,
        UB_PJ_T11,
        UB_PJ_T1M_ISS,
        UB_PJ_T1M_CAP,
        UB_PJ_T1A_ISS,
        UB_PJ_T1A_CAP,
        UB_PJ_T21,
        UB_PJ_T2M_ISS,
        UB_PJ_T2M_CAP,
        UB_PJ_T2A_ISS,
        UB_PJ_T2A_CAP,
        UB_PJ_K0,
        UB_PJ_KM1_ISS,
        UB_PJ_KM1_CAP,
        UB_PJ_KM2_ISS,
        UB_PJ_KM2_CAP,
        UB_PJ_KMAC_ISS,
        UB_PJ_KMAC_CAP,
        UB_PJ_PN_ISS,
        UB_PJ_PN_CAP,
        UB_PJ_SYA_ISS,
        UB_PJ_SYA_CAP,
        UB_PJ_SYH_ISS,
        UB_PJ_SYH_CAP,
        UB_PJ_SYE_ISS,
        UB_PJ_SYE_CAP,
        UB_PJ_SYADV,
        UB_NEXT_PASS,
        UB_P_DLD_ISS,
        UB_P_DLD_CAP,
        UB_WR_X,
        UB_WR_P,
        UB_DONE
    } ub_state_t;

    ub_state_t                ub_state;
    logic [3:0]               pass;
    logic [3:0]               elem_idx;
    logic [$clog2(NN):0]      mat_idx;

    logic [1:0]               M_cur;
    logic [2:0]               h_idx [0:M_MAX-1];
    logic signed [DATA_W-1:0] R_diag [0:M_MAX-1];

    logic [1:0]               inn_m;
    logic signed [DATA_W-1:0] s2_00, s2_01, s2_10, s2_11;
    logic signed [DATA_W-1:0] det_a, det_b, det_r, rdet_r;
    logic signed [DATA_W-1:0] fe_scratch;

    logic [2:0]               kg_rr, kg_mm, kg_jj;
    logic signed [DATA_W-1:0] kg_acc;

    logic [2:0]               su_rr, su_mm;
    logic signed [DATA_W-1:0] su_kv;

    logic [4:0]               pj_lin;
    logic [2:0]               pj_rr, pj_cc, pj_mm, pj_kk;
    logic signed [DATA_W-1:0] pj_kh;
    logic [4:0]               pj_sym;
    logic [2:0]               pj_sr, pj_sc;
    logic signed [DATA_W-1:0] pj_t0, pj_t1;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            ub_state   <= UB_IDLE;
            done       <= 1'b0;
            upd_err    <= 1'b0;
            mem_rd_en  <= 1'b0;
            mem_wr_en  <= 1'b0;
            pass       <= '0;
            elem_idx   <= '0;
            mat_idx    <= '0;
            fe_start   <= 1'b0;
            inn_m      <= '0;
            kg_rr      <= '0;
            kg_mm      <= '0;
            kg_jj      <= '0;
            kg_acc     <= '0;
            su_rr      <= '0;
            su_mm      <= '0;
            su_kv      <= '0;
            pj_lin     <= '0;
            pj_rr      <= '0;
            pj_cc      <= '0;
            pj_mm      <= '0;
            pj_kk      <= '0;
            pj_kh      <= '0;
            pj_sym     <= '0;
            dot_acc    <= '0;
            krk_acc    <= '0;
        end else begin
            done       <= 1'b0;
            mem_rd_en  <= 1'b0;
            mem_wr_en  <= 1'b0;
            fe_start   <= 1'b0;

            case (ub_state)
            UB_IDLE: begin
                if (start) begin
                    pass     <= '0;
                    elem_idx <= '0;
                    mat_idx  <= '0;
                    ub_state <= UB_LOAD_X;
                end
            end

            UB_LOAD_X: begin
                mem_rd_en   <= 1'b1;
                mem_rd_addr <= `ADDR_XPRED + {{(`ADDR_W-4){1'b0}}, elem_idx};
                if (elem_idx > 0)
                    x_work[elem_idx-1] <= $signed(mem_rd_data);
                elem_idx <= elem_idx + 1;
                if (elem_idx == N[3:0]) begin
                    x_work[N-1] <= $signed(mem_rd_data);
                    elem_idx    <= '0;
                    mat_idx     <= '0;
                    ub_state    <= UB_LOAD_P;
                end
            end

            UB_LOAD_P: begin
                mem_rd_en   <= 1'b1;
                mem_rd_addr <= `ADDR_PPRED + {{(`ADDR_W-MAT_IW){1'b0}}, mat_idx};
                if (mat_idx > 0)
                    P_work[mat_idx-1] <= $signed(mem_rd_data);
                mat_idx <= mat_idx + 1;
                if (mat_idx == NN[$clog2(NN):0]) begin
                    P_work[NN-1] <= $signed(mem_rd_data);
                    mat_idx      <= '0;
                    ub_state     <= UB_START_GPS;
                end
            end

            // R_diag from state_mem (ADDR_R_GPS / ADDR_R_IMU / ADDR_R_ODOM), diagonal entries
            // only — matches diagonal R in generate_golden / tracking_ship.
            UB_START_GPS: begin
                if (sensor_valid_map[2]) begin
                    M_cur     <= 2;
                    h_idx[0]  <= 3'd0;
                    h_idx[1]  <= 3'd1;
                    z_meas[0] <= meas_gps_x;
                    z_meas[1] <= meas_gps_y;
                    mem_rd_en   <= 1'b1;
                    mem_rd_addr <= `ADDR_R_GPS + 8'd0;
                    ub_state    <= UB_R_GPS_A;
                end else
                    ub_state <= UB_START_IMU;
            end

            UB_R_GPS_A: begin
                R_diag[0]   <= $signed(mem_rd_data);
                mem_rd_en   <= 1'b1;
                mem_rd_addr <= `ADDR_R_GPS + 8'd3;
                ub_state    <= UB_R_GPS_B;
            end

            UB_R_GPS_B: begin
                R_diag[1]   <= $signed(mem_rd_data);
                inn_m       <= '0;
                ub_state    <= UB_INN_ISS;
            end

            UB_START_IMU: begin
                if (sensor_valid_map[1]) begin
                    M_cur     <= 2;
                    h_idx[0]  <= 3'd3;
                    h_idx[1]  <= 3'd4;
                    z_meas[0] <= meas_imu_psi;
                    z_meas[1] <= meas_imu_dot;
                    mem_rd_en   <= 1'b1;
                    mem_rd_addr <= `ADDR_R_IMU + 8'd0;
                    ub_state    <= UB_R_IMU_A;
                end else
                    ub_state <= UB_START_ODOM;
            end

            UB_R_IMU_A: begin
                R_diag[0]   <= $signed(mem_rd_data);
                mem_rd_en   <= 1'b1;
                mem_rd_addr <= `ADDR_R_IMU + 8'd3;
                ub_state    <= UB_R_IMU_B;
            end

            UB_R_IMU_B: begin
                R_diag[1]   <= $signed(mem_rd_data);
                inn_m       <= '0;
                ub_state    <= UB_INN_ISS;
            end

            UB_START_ODOM: begin
                if (sensor_valid_map[0]) begin
                    M_cur     <= 1;
                    h_idx[0]  <= 3'd2;
                    z_meas[0] <= meas_odom_v;
                    mem_rd_en   <= 1'b1;
                    mem_rd_addr <= `ADDR_R_ODOM;
                    ub_state    <= UB_R_ODOM_CAP;
                end else
                    ub_state <= UB_WR_X;
            end

            UB_R_ODOM_CAP: begin
                R_diag[0] <= $signed(mem_rd_data);
                inn_m     <= '0;
                ub_state  <= UB_INN_ISS;
            end

            UB_INN_ISS: begin
                fe_start <= 1'b1;
                fe_op    <= UKF_FP_SUB;
                fe_a     <= z_meas[inn_m];
                fe_b     <= x_work[h_idx[inn_m]];
                ub_state <= UB_INN_CAP;
            end
            UB_INN_CAP: begin
                if (fe_rdy) begin
                    innov[inn_m] <= fe_y;
                    if (inn_m == M_cur - 1) begin
                        if (M_cur == 2)
                            ub_state <= UB_S2_CP;
                        else
                            ub_state <= UB_S1_A_ISS;
                    end else begin
                        inn_m    <= inn_m + 1;
                        ub_state <= UB_INN_ISS;
                    end
                end
            end

            UB_S2_CP: begin
                s2_01 <= P_work[h_idx[0]*N + h_idx[1]];
                s2_10 <= P_work[h_idx[1]*N + h_idx[0]];
                ub_state <= UB_S2_A00_ISS;
            end

            UB_S2_A00_ISS: begin
                fe_start <= 1'b1;
                fe_op    <= UKF_FP_ADD;
                fe_a     <= P_work[h_idx[0]*N + h_idx[0]];
                fe_b     <= R_diag[0];
                ub_state <= UB_S2_A00_CAP;
            end
            UB_S2_A00_CAP: begin
                if (fe_rdy) begin
                    s2_00   <= fe_y;
                    ub_state <= UB_S2_A11_ISS;
                end
            end

            UB_S2_A11_ISS: begin
                fe_start <= 1'b1;
                fe_op    <= UKF_FP_ADD;
                fe_a     <= P_work[h_idx[1]*N + h_idx[1]];
                fe_b     <= R_diag[1];
                ub_state <= UB_S2_A11_CAP;
            end
            UB_S2_A11_CAP: begin
                if (fe_rdy) begin
                    s2_11   <= fe_y;
                    ub_state <= UB_IV_M0_ISS;
                end
            end

            UB_S1_A_ISS: begin
                fe_start <= 1'b1;
                fe_op    <= UKF_FP_ADD;
                fe_a     <= P_work[h_idx[0]*N + h_idx[0]];
                fe_b     <= R_diag[0];
                ub_state <= UB_S1_A_CAP;
            end
            UB_S1_A_CAP: begin
                if (fe_rdy) begin
                    fe_scratch <= fe_y;
                    ub_state   <= UB_S1_R_ISS;
                end
            end
            UB_S1_R_ISS: begin
                fe_start <= 1'b1;
                fe_op    <= UKF_FP_RECIP;
                fe_a     <= fe_scratch;
                fe_b     <= fe_scratch;
                ub_state <= UB_S1_R_CAP;
            end
            UB_S1_R_CAP: begin
                if (fe_rdy) begin
                    S_inv[0] <= fe_y;
                    S_inv[1] <= '0;
                    S_inv[2] <= '0;
                    S_inv[3] <= `FP_ONE;
                    ub_state <= UB_CROSS_COV;
                end
            end

            UB_IV_M0_ISS: begin
                fe_start <= 1'b1;
                fe_op    <= UKF_FP_MUL;
                fe_a     <= s2_00;
                fe_b     <= s2_11;
                ub_state <= UB_IV_M0_CAP;
            end
            UB_IV_M0_CAP: begin
                if (fe_rdy) begin
                    det_a   <= fe_y;
                    ub_state <= UB_IV_M1_ISS;
                end
            end

            UB_IV_M1_ISS: begin
                fe_start <= 1'b1;
                fe_op    <= UKF_FP_MUL;
                fe_a     <= s2_01;
                fe_b     <= s2_10;
                ub_state <= UB_IV_M1_CAP;
            end
            UB_IV_M1_CAP: begin
                if (fe_rdy) begin
                    det_b   <= fe_y;
                    ub_state <= UB_IV_DS_ISS;
                end
            end

            UB_IV_DS_ISS: begin
                fe_start <= 1'b1;
                fe_op    <= UKF_FP_SUB;
                fe_a     <= det_a;
                fe_b     <= det_b;
                ub_state <= UB_IV_DS_CAP;
            end
            UB_IV_DS_CAP: begin
                if (fe_rdy) begin
                    if (!fp_abs_gt_eps(fe_y, `FP_EPSILON))
                        det_r <= `FP_EPSILON;
                    else
                        det_r <= fe_y;
                    ub_state <= UB_IV_R_ISS;
                end
            end

            UB_IV_R_ISS: begin
                fe_start <= 1'b1;
                fe_op    <= UKF_FP_RECIP;
                fe_a     <= det_r;
                fe_b     <= det_r;
                ub_state <= UB_IV_R_CAP;
            end
            UB_IV_R_CAP: begin
                if (fe_rdy) begin
                    rdet_r  <= fe_y;
                    ub_state <= UB_IV_I00_ISS;
                end
            end

            UB_IV_I00_ISS: begin
                fe_start <= 1'b1;
                fe_op    <= UKF_FP_MUL;
                fe_a     <= s2_11;
                fe_b     <= rdet_r;
                ub_state <= UB_IV_I00_CAP;
            end
            UB_IV_I00_CAP: begin
                if (fe_rdy) begin
                    S_inv[0] <= fe_y;
                    ub_state <= UB_IV_I01_ISS;
                end
            end

            UB_IV_I01_ISS: begin
                fe_start <= 1'b1;
                fe_op    <= UKF_FP_MUL;
                fe_a     <= s2_01;
                fe_b     <= rdet_r;
                ub_state <= UB_IV_I01_CAP;
            end
            UB_IV_I01_CAP: begin
                if (fe_rdy) begin
                    fe_scratch <= fe_y;
                    ub_state   <= UB_IV_I01N_ISS;
                end
            end
            UB_IV_I01N_ISS: begin
                fe_start <= 1'b1;
                fe_op    <= UKF_FP_NEG;
                fe_a     <= fe_scratch;
                fe_b     <= fe_scratch;
                ub_state <= UB_IV_I01N_CAP;
            end
            UB_IV_I01N_CAP: begin
                if (fe_rdy) begin
                    S_inv[1] <= fe_y;
                    ub_state <= UB_IV_I10_ISS;
                end
            end

            UB_IV_I10_ISS: begin
                fe_start <= 1'b1;
                fe_op    <= UKF_FP_MUL;
                fe_a     <= s2_10;
                fe_b     <= rdet_r;
                ub_state <= UB_IV_I10_CAP;
            end
            UB_IV_I10_CAP: begin
                if (fe_rdy) begin
                    fe_scratch <= fe_y;
                    ub_state   <= UB_IV_I10N_ISS;
                end
            end
            UB_IV_I10N_ISS: begin
                fe_start <= 1'b1;
                fe_op    <= UKF_FP_NEG;
                fe_a     <= fe_scratch;
                fe_b     <= fe_scratch;
                ub_state <= UB_IV_I10N_CAP;
            end
            UB_IV_I10N_CAP: begin
                if (fe_rdy) begin
                    S_inv[2] <= fe_y;
                    ub_state <= UB_IV_I11_ISS;
                end
            end

            UB_IV_I11_ISS: begin
                fe_start <= 1'b1;
                fe_op    <= UKF_FP_MUL;
                fe_a     <= s2_00;
                fe_b     <= rdet_r;
                ub_state <= UB_IV_I11_CAP;
            end
            UB_IV_I11_CAP: begin
                if (fe_rdy) begin
                    S_inv[3] <= fe_y;
                    ub_state <= UB_CROSS_COV;
                end
            end

            UB_CROSS_COV: begin
                for (int rr = 0; rr < N; rr++)
                    for (int mm = 0; mm < M_MAX; mm++) begin
                        if (mm < M_cur)
                            P_HT[rr*M_MAX+mm] <= P_work[rr*N+h_idx[mm]];
                        else
                            P_HT[rr*M_MAX+mm] <= '0;
                    end
                kg_rr  <= '0;
                kg_mm  <= '0;
                kg_jj  <= '0;
                kg_acc <= '0;
                ub_state <= UB_KG_MUL_ISS;
            end

            UB_KG_MUL_ISS: begin
                fe_start <= 1'b1;
                fe_op    <= UKF_FP_MUL;
                fe_a     <= P_HT[kg_rr*M_MAX + kg_jj];
                fe_b     <= S_inv[kg_jj*M_MAX + kg_mm];
                ub_state <= UB_KG_MUL_CAP;
            end
            UB_KG_MUL_CAP: begin
                if (fe_rdy) begin
                    fe_scratch <= fe_y;
                    ub_state   <= UB_KG_ADD_ISS;
                end
            end
            UB_KG_ADD_ISS: begin
                fe_start <= 1'b1;
                fe_op    <= UKF_FP_ADD;
                fe_a     <= kg_acc;
                fe_b     <= fe_scratch;
                ub_state <= UB_KG_ADD_CAP;
            end
            UB_KG_ADD_CAP: begin
                if (fe_rdy) begin
                    kg_acc <= fe_y;
                    if (kg_jj == M_MAX - 1) begin
                        K_gain[kg_rr*M_MAX + kg_mm] <= fe_y;
                        if (kg_mm == M_cur - 1) begin
                            if (kg_rr == N[2:0] - 1) begin
                                su_rr  <= '0;
                                su_mm  <= '0;
                                su_kv  <= '0;
                                ub_state <= UB_SU_KM_ISS;
                            end else begin
                                kg_rr  <= kg_rr + 1;
                                kg_mm  <= '0;
                                kg_jj  <= '0;
                                kg_acc <= '0;
                                ub_state <= UB_KG_MUL_ISS;
                            end
                        end else begin
                            kg_mm  <= kg_mm + 1;
                            kg_jj  <= '0;
                            kg_acc <= '0;
                            ub_state <= UB_KG_MUL_ISS;
                        end
                    end else begin
                        kg_jj  <= kg_jj + 1;
                        ub_state <= UB_KG_MUL_ISS;
                    end
                end
            end

            UB_SU_KM_ISS: begin
                if (su_mm < M_cur) begin
                    fe_start <= 1'b1;
                    fe_op    <= UKF_FP_MUL;
                    fe_a     <= K_gain[su_rr*M_MAX + su_mm];
                    fe_b     <= innov[su_mm];
                    ub_state <= UB_SU_KM_CAP;
                end else
                    ub_state <= UB_SU_XA_ISS;
            end
            UB_SU_KM_CAP: begin
                if (fe_rdy) begin
                    fe_scratch <= fe_y;
                    ub_state   <= UB_SU_KA_ISS;
                end
            end
            UB_SU_KA_ISS: begin
                fe_start <= 1'b1;
                fe_op    <= UKF_FP_ADD;
                fe_a     <= su_kv;
                fe_b     <= fe_scratch;
                ub_state <= UB_SU_KA_CAP;
            end
            UB_SU_KA_CAP: begin
                if (fe_rdy) begin
                    su_kv  <= fe_y;
                    su_mm  <= su_mm + 1;
                    ub_state <= UB_SU_KM_ISS;
                end
            end

            UB_SU_XA_ISS: begin
                fe_start <= 1'b1;
                fe_op    <= UKF_FP_ADD;
                fe_a     <= x_work[su_rr];
                fe_b     <= su_kv;
                ub_state <= UB_SU_XA_CAP;
            end
            UB_SU_XA_CAP: begin
                if (fe_rdy) begin
                    x_work[su_rr] <= fe_y;
                    ub_state      <= UB_SU_ADV;
                end
            end
            UB_SU_ADV: begin
                if (su_rr == N[2:0] - 1) begin
                    pj_lin <= '0;
                    pj_mm  <= '0;
                    ub_state <= UB_PJ_IKH0;
                end else begin
                    su_rr  <= su_rr + 1;
                    su_mm  <= '0;
                    su_kv  <= '0;
                    ub_state <= UB_SU_KM_ISS;
                end
            end

            UB_PJ_IKH0: begin
                pj_rr  <= pj_lin / N[2:0];
                pj_cc  <= pj_lin % N[2:0];
                pj_mm  <= '0;
                pj_kh  <= '0;
                ub_state <= UB_PJ_IKHM_ISS;
            end

            UB_PJ_IKHM_ISS: begin
                if (pj_mm >= M_cur)
                    ub_state <= UB_PJ_IKH_FIN;
                else if (pj_cc != h_idx[pj_mm]) begin
                    pj_mm    <= pj_mm + 1;
                    ub_state <= UB_PJ_IKHM_ISS;
                end else begin
                    fe_start <= 1'b1;
                    fe_op    <= UKF_FP_ADD;
                    fe_a     <= pj_kh;
                    fe_b     <= K_gain[pj_rr*M_MAX + pj_mm];
                    ub_state <= UB_PJ_IKHM_CAP;
                end
            end
            UB_PJ_IKHM_CAP: begin
                if (fe_rdy) begin
                    pj_kh  <= fe_y;
                    pj_mm  <= pj_mm + 1;
                    ub_state <= UB_PJ_IKHM_ISS;
                end
            end

            UB_PJ_IKH_FIN: begin
                if (pj_rr == pj_cc) begin
                    fe_start <= 1'b1;
                    fe_op    <= UKF_FP_SUB;
                    fe_a     <= `FP_ONE;
                    fe_b     <= pj_kh;
                    ub_state <= UB_PJ_IKH_FCAP;
                end else begin
                    fe_start <= 1'b1;
                    fe_op    <= UKF_FP_NEG;
                    fe_a     <= pj_kh;
                    fe_b     <= pj_kh;
                    ub_state <= UB_PJ_IKH_FCAP;
                end
            end
            UB_PJ_IKH_FCAP: begin
                if (fe_rdy) begin
                    IKH_mem[pj_lin] <= fe_y;
                    if (pj_lin == NN[$clog2(NN):0] - 1) begin
                        pj_lin  <= '0;
                        ub_state <= UB_PJ_T11;
                    end else begin
                        pj_lin  <= pj_lin + 1;
                        ub_state <= UB_PJ_IKH0;
                    end
                end
            end

            UB_PJ_T11: begin
                pj_rr   <= pj_lin / N[2:0];
                pj_cc   <= pj_lin % N[2:0];
                pj_kk   <= '0;
                dot_acc <= '0;
                ub_state <= UB_PJ_T1M_ISS;
            end
            UB_PJ_T1M_ISS: begin
                fe_start <= 1'b1;
                fe_op    <= UKF_FP_MUL;
                fe_a     <= IKH_mem[pj_rr * N + pj_kk];
                fe_b     <= P_work[pj_kk * N + pj_cc];
                ub_state <= UB_PJ_T1M_CAP;
            end
            UB_PJ_T1M_CAP: begin
                if (fe_rdy) begin
                    fe_scratch <= fe_y;
                    ub_state   <= UB_PJ_T1A_ISS;
                end
            end
            UB_PJ_T1A_ISS: begin
                fe_start <= 1'b1;
                fe_op    <= UKF_FP_ADD;
                fe_a     <= dot_acc;
                fe_b     <= fe_scratch;
                ub_state <= UB_PJ_T1A_CAP;
            end
            UB_PJ_T1A_CAP: begin
                if (fe_rdy) begin
                    dot_acc <= fe_y;
                    if (pj_kk == N[2:0] - 1) begin
                        T1_mem[pj_lin] <= fe_y;
                        if (pj_lin == NN[$clog2(NN):0] - 1) begin
                            pj_lin  <= '0;
                            ub_state <= UB_PJ_T21;
                        end else begin
                            pj_lin  <= pj_lin + 1;
                            ub_state <= UB_PJ_T11;
                        end
                    end else begin
                        pj_kk   <= pj_kk + 1;
                        ub_state <= UB_PJ_T1M_ISS;
                    end
                end
            end

            UB_PJ_T21: begin
                pj_rr   <= pj_lin / N[2:0];
                pj_cc   <= pj_lin % N[2:0];
                pj_kk   <= '0;
                dot_acc <= '0;
                ub_state <= UB_PJ_T2M_ISS;
            end
            UB_PJ_T2M_ISS: begin
                fe_start <= 1'b1;
                fe_op    <= UKF_FP_MUL;
                fe_a     <= T1_mem[pj_rr * N + pj_kk];
                fe_b     <= IKH_mem[pj_cc * N + pj_kk];
                ub_state <= UB_PJ_T2M_CAP;
            end
            UB_PJ_T2M_CAP: begin
                if (fe_rdy) begin
                    fe_scratch <= fe_y;
                    ub_state   <= UB_PJ_T2A_ISS;
                end
            end
            UB_PJ_T2A_ISS: begin
                fe_start <= 1'b1;
                fe_op    <= UKF_FP_ADD;
                fe_a     <= dot_acc;
                fe_b     <= fe_scratch;
                ub_state <= UB_PJ_T2A_CAP;
            end
            UB_PJ_T2A_CAP: begin
                if (fe_rdy) begin
                    dot_acc <= fe_y;
                    if (pj_kk == N[2:0] - 1) begin
                        T2_mem[pj_lin] <= fe_y;
                        if (pj_lin == NN[$clog2(NN):0] - 1) begin
                            pj_lin  <= '0;
                            ub_state <= UB_PJ_K0;
                        end else begin
                            pj_lin  <= pj_lin + 1;
                            ub_state <= UB_PJ_T21;
                        end
                    end else begin
                        pj_kk   <= pj_kk + 1;
                        ub_state <= UB_PJ_T2M_ISS;
                    end
                end
            end

            UB_PJ_K0: begin
                pj_rr   <= pj_lin / N[2:0];
                pj_cc   <= pj_lin % N[2:0];
                pj_mm   <= '0;
                krk_acc <= '0;
                ub_state <= UB_PJ_KM1_ISS;
            end
            UB_PJ_KM1_ISS: begin
                if (pj_mm >= M_cur)
                    ub_state <= UB_PJ_PN_ISS;
                else begin
                    fe_start <= 1'b1;
                    fe_op    <= UKF_FP_MUL;
                    fe_a     <= K_gain[pj_rr * M_MAX + pj_mm];
                    fe_b     <= R_diag[pj_mm];
                    ub_state <= UB_PJ_KM1_CAP;
                end
            end
            UB_PJ_KM1_CAP: begin
                if (fe_rdy) begin
                    fe_scratch <= fe_y;
                    ub_state   <= UB_PJ_KM2_ISS;
                end
            end
            UB_PJ_KM2_ISS: begin
                fe_start <= 1'b1;
                fe_op    <= UKF_FP_MUL;
                fe_a     <= fe_scratch;
                fe_b     <= K_gain[pj_cc * M_MAX + pj_mm];
                ub_state <= UB_PJ_KM2_CAP;
            end
            UB_PJ_KM2_CAP: begin
                if (fe_rdy) begin
                    fe_scratch <= fe_y;
                    ub_state   <= UB_PJ_KMAC_ISS;
                end
            end
            UB_PJ_KMAC_ISS: begin
                fe_start <= 1'b1;
                fe_op    <= UKF_FP_ADD;
                fe_a     <= krk_acc;
                fe_b     <= fe_scratch;
                ub_state <= UB_PJ_KMAC_CAP;
            end
            UB_PJ_KMAC_CAP: begin
                if (fe_rdy) begin
                    krk_acc <= fe_y;
                    pj_mm   <= pj_mm + 1;
                    ub_state <= UB_PJ_KM1_ISS;
                end
            end

            UB_PJ_PN_ISS: begin
                fe_start <= 1'b1;
                fe_op    <= UKF_FP_ADD;
                fe_a     <= T2_mem[pj_lin];
                fe_b     <= krk_acc;
                ub_state <= UB_PJ_PN_CAP;
            end
            UB_PJ_PN_CAP: begin
                if (fe_rdy) begin
                    P_new_m[pj_lin] <= fe_y;
                    if (pj_lin == NN[$clog2(NN):0] - 1) begin
                        pj_sym <= '0;
                        ub_state <= UB_PJ_SYA_ISS;
                    end else begin
                        pj_lin <= pj_lin + 1;
                        ub_state <= UB_PJ_K0;
                    end
                end
            end

            UB_PJ_SYA_ISS: begin
                pj_sr    <= pj_sym / N[2:0];
                pj_sc    <= pj_sym % N[2:0];
                fe_start <= 1'b1;
                fe_op    <= UKF_FP_ADD;
                fe_a     <= P_new_m[(pj_sym / N[2:0]) * N + (pj_sym % N[2:0])];
                fe_b     <= P_new_m[(pj_sym % N[2:0]) * N + (pj_sym / N[2:0])];
                ub_state <= UB_PJ_SYA_CAP;
            end
            UB_PJ_SYA_CAP: begin
                if (fe_rdy) begin
                    pj_t0    <= fe_y;
                    ub_state <= UB_PJ_SYH_ISS;
                end
            end
            UB_PJ_SYH_ISS: begin
                fe_start <= 1'b1;
                fe_op    <= UKF_FP_MUL;
                fe_a     <= `FP_HALF;
                fe_b     <= pj_t0;
                ub_state <= UB_PJ_SYH_CAP;
            end
            UB_PJ_SYH_CAP: begin
                if (fe_rdy) begin
                    pj_t1 <= fe_y;
                    if (pj_sr == pj_sc)
                        ub_state <= UB_PJ_SYE_ISS;
                    else begin
                        P_work[pj_sr * N + pj_sc] <= fe_y;
                        ub_state <= UB_PJ_SYADV;
                    end
                end
            end
            UB_PJ_SYE_ISS: begin
                fe_start <= 1'b1;
                fe_op    <= UKF_FP_ADD;
                fe_a     <= pj_t1;
                fe_b     <= `FP_EPSILON;
                ub_state <= UB_PJ_SYE_CAP;
            end
            UB_PJ_SYE_CAP: begin
                if (fe_rdy) begin
                    P_work[pj_sr * N + pj_sc] <= fe_y;
                    ub_state <= UB_PJ_SYADV;
                end
            end
            UB_PJ_SYADV: begin
                if (pj_sym == NN[$clog2(NN):0] - 1)
                    ub_state <= UB_NEXT_PASS;
                else begin
                    pj_sym <= pj_sym + 1;
                    ub_state <= UB_PJ_SYA_ISS;
                end
            end

            UB_NEXT_PASS: begin
                case (pass)
                    4'd0: begin pass <= 4'd1; ub_state <= UB_START_IMU;  end
                    4'd1: begin pass <= 4'd2; ub_state <= UB_START_ODOM; end
                    default: begin
                        elem_idx <= '0;
                        ub_state <= UB_P_DLD_ISS;
                    end
                endcase
            end

            // P += FP_P_DIAG_LOAD on diagonal (SPD regularization after Joseph, FP32)
            UB_P_DLD_ISS: begin
                fe_start <= 1'b1;
                fe_op    <= UKF_FP_ADD;
                fe_a     <= P_work[elem_idx * N + elem_idx];
                fe_b     <= `FP_P_DIAG_LOAD;
                ub_state <= UB_P_DLD_CAP;
            end
            UB_P_DLD_CAP: begin
                if (fe_rdy) begin
                    P_work[elem_idx * N + elem_idx] <= fe_y;
                    if (elem_idx == N[2:0] - 1) begin
                        elem_idx <= '0;
                        ub_state <= UB_WR_X;
                    end else begin
                        elem_idx <= elem_idx + 1;
                        ub_state <= UB_P_DLD_ISS;
                    end
                end
            end

            UB_WR_X: begin
                mem_wr_en   <= 1'b1;
                mem_wr_addr <= `ADDR_X + {{(`ADDR_W-4){1'b0}}, elem_idx};
                mem_wr_data <= x_work[elem_idx];
                update_result[elem_idx * DATA_W +: DATA_W] <= x_work[elem_idx];
                elem_idx <= elem_idx + 1;
                if (elem_idx == N[3:0] - 1) begin
                    mat_idx  <= '0;
                    ub_state <= UB_WR_P;
                end
            end

            UB_WR_P: begin
                mem_wr_en   <= 1'b1;
                mem_wr_addr <= `ADDR_P + {{(`ADDR_W-MAT_IW){1'b0}}, mat_idx};
                mem_wr_data <= P_work[mat_idx];
                mat_idx <= mat_idx + 1;
                if (mat_idx == NN - 1)
                    ub_state <= UB_DONE;
            end

            UB_DONE: begin
                done     <= 1'b1;
                ub_state <= UB_IDLE;
            end

            default: ub_state <= UB_IDLE;
            endcase
        end
    end

endmodule
