// Fusion IP UKF Reference Model / Predictor
// Matches RTL parameters: alpha=0.1, beta=2, kappa=0, state=[x,y,v,psi,psidot]
// Variable dt passed per cycle (matches AXI REG_DT)

package fusion_predictor_pkg;
    import uvm_pkg::*;
    import fusion_pkg::*;
    `include "uvm_macros.svh"

    class ukf_predictor extends uvm_object;
        `uvm_object_utils(ukf_predictor)

        localparam int NS = 5;
        localparam int NSIG = 2 * NS + 1; // 11

        // alpha=0.1, beta=2, kappa=0 — matches tracking_ship Python
        localparam real ALPHA  = 0.1;
        localparam real BETA   = 2.0;
        localparam real KAPPA  = 0.0;
        localparam real LAMBDA = -4.95;  // alpha^2*(N+kappa) - N
        localparam real GAMMA  = 0.22360679774997896; // sqrt(N+LAMBDA)=sqrt(0.05)
        localparam real DT_DEFAULT = 0.04;           // reset / nominal only
        localparam real DT_WHEN_INVALID = 1.0;     // match tracking_ship main.py if dt<=0

        real x[NS];
        real P[NS][NS];
        real Q[NS][NS];

        real R_gps[2][2];
        real R_imu[2][2];
        real R_odom;

        real Wm[NSIG];
        real Wc[NSIG];

        real current_dt;

        ukf_output last_output;

        // 1: S = H P H' + R, T = P H', z_hat = x[h_idx] — matches rtl/update_block.sv (linear h).
        // 0: S, T from full sigma loop (textbook UKF update).
        bit use_linear_h_update;

        function new(string name = "ukf_predictor");
            super.new(name);
            init_ukf();
        endfunction

        virtual function void init_ukf();
            int i, j;

            for (i = 0; i < NS; i++) x[i] = 0.0;

            for (i = 0; i < NS; i++)
                for (j = 0; j < NS; j++) begin
                    P[i][j] = (i == j) ? 1.0 : 0.0;
                    Q[i][j] = (i == j) ? 0.01 : 0.0;
                end

            for (i = 0; i < 2; i++)
                for (j = 0; j < 2; j++) begin
                    R_gps[i][j] = (i == j) ? 0.1 : 0.0;
                    R_imu[i][j] = (i == j) ? 0.1 : 0.0;
                end
            R_odom = 0.1;

            // Wm[0] = lambda/(N+lambda) = -4.95/0.05 = -99
            Wm[0] = -99.0;
            // Wc[0] = Wm[0] + (1 - alpha^2 + beta) = -99 + 2.99 = -96.01
            Wc[0] = -96.01;
            for (i = 1; i < NSIG; i++) begin
                // 1/(2*(N+lambda)) = 1/0.1 = 10
                Wm[i] = 10.0;
                Wc[i] = 10.0;
            end

            current_dt = DT_DEFAULT;
            use_linear_h_update = 1'b1;
            last_output = ukf_output::type_id::create("last_output");
        endfunction

        function void ctrv(real sp[NS], ref real out[NS], real dt);
            real px, py, v, psi, psi_dot;
            px = sp[0]; py = sp[1]; v = sp[2]; psi = sp[3]; psi_dot = sp[4];

            if (psi_dot > -1e-6 && psi_dot < 1e-6) begin
                out[0] = px + v * $cos(psi) * dt;
                out[1] = py + v * $sin(psi) * dt;
            end else begin
                out[0] = px + (v / psi_dot) * ($sin(psi + psi_dot * dt) - $sin(psi));
                out[1] = py + (v / psi_dot) * (-$cos(psi + psi_dot * dt) + $cos(psi));
            end
            out[2] = v;
            out[3] = psi + psi_dot * dt;
            out[4] = psi_dot;
        endfunction

        function real norm_angle(real a);
            return $atan2($sin(a), $cos(a));
        endfunction

        // -----------------------------------------------------------------
        // LDLᵀ decomposition  P = L · D · Lᵀ
        //   L — unit lower-triangular (1s on diagonal)
        //   D — diagonal pivots (strictly positive for PD matrix)
        //
        // Algorithm (column-by-column, mirrors RTL SG_LDL_DIAG/SG_LDL_OFF):
        //   D[j] = P[j][j] − Σ_{k<j} L[j][k]² · D[k]
        //   L[i][j] = ( P[i][j] − Σ_{k<j} L[i][k]·L[j][k]·D[k] ) / D[j]
        //
        // Replaces the old standard Cholesky (cholesky()) to keep this
        // reference model aligned with the LDLᵀ RTL in sigma_point_generator.sv.
        // Sigma points are computed using γ·√D[j]·col_j(L), which equals
        // γ·col_j(L_chol) — result is mathematically identical to LLᵀ.
        // -----------------------------------------------------------------
        function void ldl_decomp(real A[NS][NS],
                                 ref real Lout[NS][NS],
                                 ref real Dout[NS]);
            int i, j, k;
            real s;
            for (i = 0; i < NS; i++)
                for (j = 0; j < NS; j++)
                    Lout[i][j] = (i == j) ? 1.0 : 0.0;

            for (j = 0; j < NS; j++) begin
                // Diagonal pivot
                s = A[j][j];
                for (k = 0; k < j; k++)
                    s -= Lout[j][k] * Lout[j][k] * Dout[k];
                Dout[j] = (s > 1e-12) ? s : 1e-12;   // clamp (mirrors FP_EPSILON)

                // Off-diagonal elements for rows below j
                for (i = j + 1; i < NS; i++) begin
                    s = A[i][j];
                    for (k = 0; k < j; k++)
                        s -= Lout[i][k] * Lout[j][k] * Dout[k];
                    Lout[i][j] = (Dout[j] != 0.0) ? s / Dout[j] : 0.0;
                end
            end
        endfunction

        // gen_sigma — build 2N+1 sigma points from LDLᵀ factorisation of P.
        // Scaled column j = GAMMA · √D[j] · col_j(L)  (matches RTL SG_SCALE_COL).
        function void gen_sigma(ref real sp[NSIG][NS]);
            real Lf[NS][NS];
            real Df[NS];
            real s;
            int i, j;

            ldl_decomp(P, Lf, Df);

            for (j = 0; j < NS; j++)
                sp[0][j] = x[j];

            for (i = 0; i < NS; i++) begin
                s = GAMMA * $sqrt(Df[i]);          // scale for column i
                for (j = 0; j < NS; j++) begin
                    real col_elem;
                    col_elem = (j == i) ? 1.0 : ((j > i) ? Lf[j][i] : 0.0);
                    sp[i + 1][j]      = x[j] + s * col_elem;
                    sp[NS + i + 1][j] = x[j] - s * col_elem;
                end
            end
        endfunction

        function void predict_step(real dt);
            real sp[NSIG][NS];
            real sp_pred[NSIG][NS];
            real x_pred[NS];
            real P_pred[NS][NS];
            real d[NS];
            int i, j, k;
            real sw, cw;

            gen_sigma(sp);

            for (i = 0; i < NSIG; i++)
                ctrv(sp[i], sp_pred[i], dt);

            // Weighted mean: linear for x,y,v,psi_dot; vector mean for heading (circular mean)
            for (j = 0; j < NS; j++) begin
                if (j != 3) begin
                    x_pred[j] = 0.0;
                    for (i = 0; i < NSIG; i++)
                        x_pred[j] += Wm[i] * sp_pred[i][j];
                end
            end
            sw = 0.0;
            cw = 0.0;
            for (i = 0; i < NSIG; i++) begin
                sw += Wm[i] * $sin(sp_pred[i][3]);
                cw += Wm[i] * $cos(sp_pred[i][3]);
            end
            x_pred[3] = $atan2(sw, cw);

            for (i = 0; i < NS; i++)
                for (j = 0; j < NS; j++)
                    P_pred[i][j] = Q[i][j];

            for (k = 0; k < NSIG; k++) begin
                for (i = 0; i < NS; i++)
                    d[i] = sp_pred[k][i] - x_pred[i];
                d[3] = norm_angle(d[3]);
                for (i = 0; i < NS; i++)
                    for (j = 0; j < NS; j++)
                        P_pred[i][j] += Wc[k] * d[i] * d[j];
            end

            for (i = 0; i < NS; i++) begin
                x[i] = x_pred[i];
                for (j = 0; j < NS; j++)
                    P[i][j] = P_pred[i][j];
            end
        endfunction

        // P_pred from explicit σ (e.g. DUT ADDR_SIGMA after sigma_point_generator).
        // Same ctrv / Wm / Wc / Q / norm_angle as predict_step; does not touch x or P.
        function void predict_P_from_sigma_chi(input real chi[NSIG][NS], input real dt,
                                               ref real P_pred_out[NS][NS]);
            real sp_pred[NSIG][NS];
            real x_pred[NS];
            real d[NS];
            int i, j, k;
            real sw, cw;

            for (i = 0; i < NSIG; i++)
                ctrv(chi[i], sp_pred[i], dt);

            for (j = 0; j < NS; j++) begin
                if (j != 3) begin
                    x_pred[j] = 0.0;
                    for (i = 0; i < NSIG; i++)
                        x_pred[j] += Wm[i] * sp_pred[i][j];
                end
            end
            sw = 0.0;
            cw = 0.0;
            for (i = 0; i < NSIG; i++) begin
                sw += Wm[i] * $sin(sp_pred[i][3]);
                cw += Wm[i] * $cos(sp_pred[i][3]);
            end
            x_pred[3] = $atan2(sw, cw);

            for (i = 0; i < NS; i++)
                for (j = 0; j < NS; j++)
                    P_pred_out[i][j] = Q[i][j];

            for (k = 0; k < NSIG; k++) begin
                for (i = 0; i < NS; i++)
                    d[i] = sp_pred[k][i] - x_pred[i];
                d[3] = norm_angle(d[3]);
                for (i = 0; i < NS; i++)
                    for (j = 0; j < NS; j++)
                        P_pred_out[i][j] += Wc[k] * d[i] * d[j];
            end
        endfunction

        // Covariance: Joseph form P <- (I-KH) P (I-KH)^T + K R K^T (matches update_block.sv),
        // then symmetrize; small diagonal bump per pass (~FP_EPSILON). step() adds FP_P_DIAG_LOAD once.
        function void update(real z[], int h_idx[], int dim_z, real R[][]);
            real sp[NSIG][NS];
            real Z_sp[NSIG][5];
            real z_pred[5];
            real S[5][5], T[5][5], K[5][5];
            real S_inv[5][5];
            real dz[5], dx[NS], innov[5];
            real IKH[NS][NS];
            real T1[NS][NS];
            real ikh_ij, s_acc, krk;
            int i, j, k, m_i, a, b;

            if (use_linear_h_update) begin
                // Linear observation: H picks state rows h_idx[0..dim_z-1]
                for (i = 0; i < dim_z; i++)
                    for (j = 0; j < dim_z; j++)
                        S[i][j] = R[i][j] + P[h_idx[i]][h_idx[j]];

                for (i = 0; i < NS; i++)
                    for (j = 0; j < dim_z; j++)
                        T[i][j] = P[i][h_idx[j]];

                for (j = 0; j < dim_z; j++)
                    z_pred[j] = x[h_idx[j]];
            end else begin
                gen_sigma(sp);

                for (i = 0; i < NSIG; i++)
                    for (j = 0; j < dim_z; j++)
                        Z_sp[i][j] = sp[i][h_idx[j]];

                for (j = 0; j < dim_z; j++) begin
                    z_pred[j] = 0.0;
                    for (i = 0; i < NSIG; i++)
                        z_pred[j] += Wm[i] * Z_sp[i][j];
                end

                for (i = 0; i < dim_z; i++)
                    for (j = 0; j < dim_z; j++) begin
                        S[i][j] = R[i][j];
                        T[i][j] = 0.0;
                    end

                for (i = 0; i < NS; i++)
                    for (j = 0; j < dim_z; j++)
                        T[i][j] = 0.0;

                for (k = 0; k < NSIG; k++) begin
                    for (j = 0; j < dim_z; j++)
                        dz[j] = Z_sp[k][j] - z_pred[j];
                    for (i = 0; i < NS; i++)
                        dx[i] = sp[k][i] - x[i];
                    dx[3] = norm_angle(dx[3]);

                    for (i = 0; i < dim_z; i++)
                        for (j = 0; j < dim_z; j++)
                            S[i][j] += Wc[k] * dz[i] * dz[j];
                    for (i = 0; i < NS; i++)
                        for (j = 0; j < dim_z; j++)
                            T[i][j] += Wc[k] * dx[i] * dz[j];
                end
            end

            if (dim_z == 1) begin
                S_inv[0][0] = (S[0][0] != 0.0) ? 1.0 / S[0][0] : 0.0;
            end else if (dim_z == 2) begin
                real det;
                det = S[0][0] * S[1][1] - S[0][1] * S[1][0];
                if (det != 0.0) begin
                    S_inv[0][0] =  S[1][1] / det;
                    S_inv[0][1] = -S[0][1] / det;
                    S_inv[1][0] = -S[1][0] / det;
                    S_inv[1][1] =  S[0][0] / det;
                end
            end

            for (i = 0; i < NS; i++)
                for (j = 0; j < dim_z; j++) begin
                    K[i][j] = 0.0;
                    for (k = 0; k < dim_z; k++)
                        K[i][j] += T[i][k] * S_inv[k][j];
                end

            for (j = 0; j < dim_z; j++)
                innov[j] = z[j] - z_pred[j];
            for (j = 0; j < dim_z; j++)
                if (h_idx[j] == 3)
                    innov[j] = norm_angle(innov[j]);

            for (i = 0; i < NS; i++)
                for (j = 0; j < dim_z; j++)
                    x[i] += K[i][j] * innov[j];
            x[3] = norm_angle(x[3]);

            // IKH[i][j] = delta_ij - sum_m K[i,m] * H[m,j], H[m,j] = (j == h_idx[m])
            for (i = 0; i < NS; i++)
                for (j = 0; j < NS; j++) begin
                    ikh_ij = (i == j) ? 1.0 : 0.0;
                    for (m_i = 0; m_i < dim_z; m_i++)
                        if (j == h_idx[m_i])
                            ikh_ij -= K[i][m_i];
                    IKH[i][j] = ikh_ij;
                end

            // T1 = IKH * P
            for (i = 0; i < NS; i++)
                for (j = 0; j < NS; j++) begin
                    s_acc = 0.0;
                    for (k = 0; k < NS; k++)
                        s_acc += IKH[i][k] * P[k][j];
                    T1[i][j] = s_acc;
                end

            // P = T1 * IKH^T  (i.e. sum_k T1[i][k] * IKH[j][k])
            for (i = 0; i < NS; i++)
                for (j = 0; j < NS; j++) begin
                    s_acc = 0.0;
                    for (k = 0; k < NS; k++)
                        s_acc += T1[i][k] * IKH[j][k];
                    P[i][j] = s_acc;
                end

            // + K R K^T
            for (i = 0; i < NS; i++)
                for (j = 0; j < NS; j++) begin
                    krk = 0.0;
                    for (a = 0; a < dim_z; a++)
                        for (b = 0; b < dim_z; b++)
                            krk += K[i][a] * R[a][b] * K[j][b];
                    P[i][j] += krk;
                end

            // Symmetrize into T1 (in-place 0.5*(P+P') would corrupt before j loop finishes)
            for (i = 0; i < NS; i++)
                for (j = 0; j < NS; j++)
                    T1[i][j] = 0.5 * (P[i][j] + P[j][i]);
            for (i = 0; i < NS; i++)
                for (j = 0; j < NS; j++)
                    P[i][j] = T1[i][j];
            for (i = 0; i < NS; i++)
                P[i][i] += 1.0e-6;
        endfunction

        function void update_gps(real gps_x, real gps_y);
            real z[2];
            int  h[2];
            real R[2][2];
            z[0] = gps_x; z[1] = gps_y;
            h[0] = 0; h[1] = 1;
            R[0][0] = R_gps[0][0]; R[0][1] = R_gps[0][1];
            R[1][0] = R_gps[1][0]; R[1][1] = R_gps[1][1];
            update(z, h, 2, R);
        endfunction

        function void update_imu(real psi, real psi_dot);
            real z[2];
            int  h[2];
            real R[2][2];
            z[0] = psi; z[1] = psi_dot;
            h[0] = 3; h[1] = 4;
            R[0][0] = R_imu[0][0]; R[0][1] = R_imu[0][1];
            R[1][0] = R_imu[1][0]; R[1][1] = R_imu[1][1];
            update(z, h, 2, R);
        endfunction

        function void update_odom(real v);
            real z[1];
            int  h[1];
            real R[1][1];
            z[0] = v;
            h[0] = 2;
            R[0][0] = R_odom;
            update(z, h, 1, R);
        endfunction

        // One complete UKF cycle; dt_bits is FP32 from AXI register
        virtual function void step(
            logic [63:0] gps_data,
            logic        gps_valid,
            logic [95:0] imu_data,
            logic        imu_valid,
            logic [31:0] odom_data,
            logic        odom_valid,
            logic [31:0] dt_bits
        );
            real gps_x, gps_y, imu_psi, imu_dot, vel;

            current_dt = dut_to_real(dt_bits);
            if (current_dt <= 0.0) current_dt = DT_WHEN_INVALID;

            predict_step(current_dt);

            if (gps_valid) begin
                gps_x = dut_to_real(gps_data[63:32]);
                gps_y = dut_to_real(gps_data[31:0]);
                update_gps(gps_x, gps_y);
            end

            if (imu_valid) begin
                imu_psi = dut_to_real(imu_data[95:64]);
                imu_dot = dut_to_real(imu_data[63:32]);
                update_imu(imu_psi, imu_dot);
            end

            if (odom_valid) begin
                vel = dut_to_real(odom_data);
                update_odom(vel);
            end

            // Match update_block UB_P_DLD_ISS after at least one measurement update pass
            if (gps_valid || imu_valid || odom_valid)
                for (int ii = 0; ii < NS; ii++)
                    P[ii][ii] += 0.01;

            last_output.x       = x[0];
            last_output.y       = x[1];
            last_output.v       = x[2];
            last_output.psi     = x[3];
            last_output.psi_dot = x[4];
        endfunction

        virtual function ukf_output get_output();
            return last_output;
        endfunction

        // Force x,P to DUT posterior (e.g. from scoreboard latch after each UKF). Next step() then
        // starts from the same FP32-rounded state as DUT RAM, not a drifting float-only chain.
        function void apply_dut_posterior_xP(input real xd[NS], input real Pd[NS][NS]);
            for (int i = 0; i < NS; i++)
                x[i] = xd[i];
            for (int i = 0; i < NS; i++)
                for (int j = 0; j < NS; j++)
                    P[i][j] = Pd[i][j];
            last_output.x       = x[0];
            last_output.y       = x[1];
            last_output.v       = x[2];
            last_output.psi     = x[3];
            last_output.psi_dot = x[4];
        endfunction

        // Words 0..63 = DUT state_mem map: x[5], P[25], Q[25], R_gps[4], R_imu[4], R_odom[1]
        // (params.vh ADDR_X..ADDR_R_ODOM). Call once after $readmemh so PRIMARY matches DUT tuning.
        function void import_state_mem_snapshot(logic [31:0] w[0:63]);
            int k, i, j;
            k = 0;
            for (i = 0; i < NS; i++)
                x[i] = dut_to_real(w[k++]);
            for (i = 0; i < NS; i++)
                for (j = 0; j < NS; j++)
                    P[i][j] = dut_to_real(w[k++]);
            for (i = 0; i < NS; i++)
                for (j = 0; j < NS; j++)
                    Q[i][j] = dut_to_real(w[k++]);
            for (i = 0; i < 2; i++)
                for (j = 0; j < 2; j++)
                    R_gps[i][j] = dut_to_real(w[k++]);
            for (i = 0; i < 2; i++)
                for (j = 0; j < 2; j++)
                    R_imu[i][j] = dut_to_real(w[k++]);
            R_odom = dut_to_real(w[k++]);
            // R_* kept from snapshot — update_block reads same ADDR_R_* diagonals into R_diag.
            last_output.x       = x[0];
            last_output.y       = x[1];
            last_output.v       = x[2];
            last_output.psi     = x[3];
            last_output.psi_dot = x[4];
        endfunction

        // ---- Debug helpers (UKF_DEBUG_P scoreboard dumps) ----------------
        function void copy_P(ref real Pout[NS][NS]);
            for (int i = 0; i < NS; i++)
                for (int j = 0; j < NS; j++)
                    Pout[i][j] = P[i][j];
        endfunction

        function void copy_Q(ref real Qout[NS][NS]);
            for (int i = 0; i < NS; i++)
                for (int j = 0; j < NS; j++)
                    Qout[i][j] = Q[i][j];
        endfunction

        function real max_symmetry_abs(input real A[NS][NS]);
            real e, d;
            e = 0.0;
            for (int i = 0; i < NS; i++)
                for (int j = 0; j < i; j++) begin
                    d = A[i][j] - A[j][i];
                    if (d < 0.0) d = -d;
                    if (d > e) e = d;
                end
            return e;
        endfunction

        // LDL diagonal pivots D[j] without the 1e-12 clamp (detect would-be sigma_err)
        function void ldl_diag_raw(input real A[NS][NS], ref real D_raw[NS],
                                   output real min_D_raw);
            real Lloc[NS][NS];
            real s;
            int i, j, k;
            min_D_raw = 1.0e30;
            for (i = 0; i < NS; i++)
                for (j = 0; j < NS; j++)
                    Lloc[i][j] = (i == j) ? 1.0 : 0.0;

            for (j = 0; j < NS; j++) begin
                s = A[j][j];
                for (k = 0; k < j; k++)
                    s -= Lloc[j][k] * Lloc[j][k] * D_raw[k];
                D_raw[j] = s;
                if (s < min_D_raw) min_D_raw = s;
                for (i = j + 1; i < NS; i++) begin
                    s = A[i][j];
                    for (k = 0; k < j; k++)
                        s -= Lloc[i][k] * Lloc[j][k] * D_raw[k];
                    Lloc[i][j] = (D_raw[j] != 0.0) ? s / D_raw[j] : 0.0;
                end
            end
        endfunction

        function string sprint_P5(input real M[NS][NS], string tag);
            string s, t;
            s = tag;
            for (int i = 0; i < NS; i++) begin
                s = {s, "\n    "};
                for (int j = 0; j < NS; j++) begin
                    $sformat(t, " %10.4f", M[i][j]);
                    s = {s, t};
                end
            end
            return s;
        endfunction

        function string sprint_model_QR_dt();
            string t;
            $sformat(t,
                "RM Q_diag[0]=%.6f R_gps_diag=%.6f %.6f R_imu_diag=%.6f %.6f R_odom=%.6f current_dt=%.6f",
                Q[0][0], R_gps[0][0], R_gps[1][1], R_imu[0][0], R_imu[1][1], R_odom, current_dt);
            return t;
        endfunction
    endclass : ukf_predictor

endpackage : fusion_predictor_pkg
