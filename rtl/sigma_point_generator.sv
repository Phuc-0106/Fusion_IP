// =============================================================
// sigma_point_generator.sv — UKF Sigma Point Generator
//
// --- Toán (F-form LDL, N trạng thái, thường N=5) ----------------
//   F[i,j] = P[i,j] − Σ_{k<j} L[i,k]·F[j,k]   với F[j,k] = L[j,k]·D[k]
//   D[j]   = F[j,j]   (pivot: nếu ≤0 → clamp FP_EPSILON, bật sigma_err)
//   L[i,j] = F[i,j]/D[j]  (i>j),  L[j,j] = 1
//
// --- Kiến trúc tổng quát (khối chức năng) -----------------------
//
//     ┌─────────────┐     ┌──────────────────────────────────────┐
//     │  P_reg      │     │  (N−1) × pe_mul  [PE lane k=0..N-2] │
//  ┌──│  L_reg      │────▶│  op_a,op_b → product_k               │
//  │  │  D_reg      │     │  fj_lane: L[j,k]×D[k]  hoặc          │
//  │  │  fj_buf[k]  │◀────│  MAC: L[i,k]×fj_buf[k]               │
//  │  └─────────────┘     └──────────────┬───────────────────────┘
//  │                                     │ tree_leaf[k]=product_k
//  │                      ┌──────────────▼───────────────────────┐
//  │                      │ ukf_fp_add_reduce_tree (cây cộng)  │
//  │                      │ sample → Σ_k (lane hợp lệ) → tree_sum
//  │                      └──────────────┬───────────────────────┘
//  │                                     │ mac_sum_r ← tree_sum
//  │  ┌──────────────────────────────────▼───────────────────────┐
//  │  │ ukf_fp_engine (KHÔNG có acc nội bộ)                        │
//  │  │  SUB: f_ij_r = P[i,j] − mac_sum_r   (tính F[i,j] tương đương) │
//  │  │  DIV: L[i,j] = f_ij_r / D[j]        (i>j)                 │
//  │  │  SQRT/MUL/ADD/SUB: pha sigma (α=γ√D, χ = x ± α·L)        │
//  │  └──────────────────────────────────────────────────────────┘
//  └──────────────────────────────────────────────────────────────
//
// Luồng dữ liệu theo cột j:
//   1) Tiền xử lý F[j,·]: S_FJ_PE → S_FJ_WAIT → S_FJ_CAP (WAIT: pe_mul 1-cycle)
//      Mỗi PE: fj_buf[k] ← L[j,k]·D[k] (chỉ k<j; lane khác ×0).
//   2) Với từng hàng i (bắt đầu i=j cho đường chéo):
//      S_MAC_PE → S_MAC_WAIT → S_MAC_TR → S_MAC_TW: mac_sum_r ← Σ_k L[i,k]·fj_buf[k].
//   3) S_SUB_* : f_ij_r ← P[i,j] − mac_sum_r  (= F[i,j]).
//   4a) i=j: S_PIV gán D[j]←f_ij_r, L[j,j]←1; S_WR_D / S_WR_LJJ ghi RAM.
//   4b) i>j: S_DIV_* → l_ij_save; S_L_ST / S_L_MEM ghi L[i,j] vào L_reg+RAM.
//   5) S_ROW_NEXT / S_ADV_J: tăng i hoặc sang cột j+1.
//
// --- Sơ đồ FSM (tóm tắt) ----------------------------------------
//
//   IDLE ─start→ LOAD_X ─→ LOAD_P ─→ CLR_L ─→ COL_ENTRY ─┬─ j>0 → FJ_PE→FJ_WAIT→FJ_CAP─┐
//                                                          │                    │
//                                                          └─ j=0 → SUB (F_00)  │
//                                                                               ▼
//                                                         MAC_PE→MAC_WAIT→MAC_TR→MAC_TW (Σ)
//                                                                               ▼
//                                                         SUB_ISS→SUB_WAIT (F_ij)
//                                                               ├─ i=j → PIV→WR_D→WR_LJJ→ROW_NEXT
//                                                               └─ i>j → DIV→L_ST→L_MEM→ROW_NEXT
//   ROW_NEXT: còn hàng dưới chéo? → MAC_PE hoặc ADV_J
//   ADV_J:   hết cột? → WX0 (χ0) → vòng SIG_* (σ ±) → DONE → IDLE
//
// P @ ADDR_P; L @ ADDR_L_UKF; D @ ADDR_D_UKF; σ @ ADDR_SIGMA.
// =============================================================
`include "params.vh"
`include "fp32_math.svh"
`include "ukf_fp_pkg.svh"

module sigma_point_generator #(
    parameter int DATA_W  = `DATA_W,
    parameter int FP_FRAC = `FP_FRAC,
    parameter int N       = `N_STATE,
    parameter int N_SIG   = `N_SIGMA
)(
    input  logic                     clk,
    input  logic                     rst,

    input  logic                     start,
    output logic                     done,
    output logic                     sigma_err,

    output logic                     mem_rd_en,
    output logic [`ADDR_W-1:0]       mem_rd_addr,
    input  logic [DATA_W-1:0]        mem_rd_data,

    output logic                     mem_wr_en,
    output logic [`ADDR_W-1:0]       mem_wr_addr,
    output logic [DATA_W-1:0]        mem_wr_data,

    input  logic signed [DATA_W-1:0] gamma
);

    localparam NN            = N * N;
    localparam int MAT_IW    = $clog2(NN) + 1;
    // Số lane nhân song song cho mỗi lần MAC / preload fj: luôn N−1 (với N=5 → 4).
    localparam int NLANE_MAC = N - 1;

    // --- idx / địa chỉ RAM cho ma trận L (hàng-chỉ-số), D, σ ----------------

    function automatic int unsigned idx_rc(input int unsigned r, input int unsigned c);
        idx_rc = r * N + c;
    endfunction

    function automatic logic [`ADDR_W-1:0] addr_L_word(input int unsigned r, input int unsigned c);
        addr_L_word = `ADDR_L_UKF + idx_rc(r, c)[`ADDR_W-1:0];
    endfunction

    function automatic logic [`ADDR_W-1:0] addr_D_word(input int unsigned j);
        addr_D_word = `ADDR_D_UKF + j[`ADDR_W-1:0];
    endfunction

    function automatic [`ADDR_W-1:0] addr_sigma_plus(input logic [2:0] sp, input logic [2:0] el);
        addr_sigma_plus = `ADDR_SIGMA + (sp * N[`ADDR_W-1:0]) + el;
    endfunction

    // --- ukf_fp_engine: chỉ phép đơn (MUL/SUB/DIV/SQRT/ADD); không tích lũy nội bộ ---

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

    // --- Thanh ghi ma trận / vector (nguồn LDL và sigma) ----------------------
    // P_reg: bản sao P từ RAM (chỉ đọc từ ADDR_P). L_reg, D_reg: thừa số LDL + sigma.

    logic signed [DATA_W-1:0] P_reg [0:NN-1];
    logic signed [DATA_W-1:0] L_reg [0:NN-1];
    logic signed [DATA_W-1:0] D_reg [0:N-1];

    // fj_buf[k] ≈ F[j,k] = L[j,k]·D[k] cho cột j hiện tại (k < j); dùng làm op_b cho MAC hàng i.

    logic signed [DATA_W-1:0] fj_buf [0:N-1];

    logic signed [DATA_W-1:0] x_vec    [0:N-1];
    // mac_sum_r: tích lũy tường minh Σ_k L[i,k]·F[j,k] (ra từ cây cộng), không nằm trong FP engine.

    logic signed [DATA_W-1:0] mac_sum_r;
    logic signed [DATA_W-1:0] f_ij_r;
    logic signed [DATA_W-1:0] d_tmp;
    logic signed [DATA_W-1:0] alpha_reg;
    logic signed [DATA_W-1:0] sig_op_a, sig_op_b;
    logic signed [DATA_W-1:0] s_elem;
    // f_ij_r: kết quả P[i,j]−mac_sum (= F[i,j]); l_ij_save: L[i,j] sau DIV.

    logic signed [DATA_W-1:0] l_ij_save;

    // j_col: chỉ số cột LDL; i_row: hàng đang xử lý (đường chéo i=j rồi i=j+1..N-1).

    logic [2:0] j_col, i_row, sig_i, elem_idx;
    logic [4:0] clr_idx;
    logic [3:0] load_cnt;
    logic [$clog2(NN):0] mem_cnt;
    logic       sig_neg_phase;

    // --- Datapath song song: PE nhân + cây cộng -------------------------------
    // pe_par_en: xung bắt nhân (1 chu kỳ); fj_lane_phase=1 → nhân L[j,k]·D[k], =0 → L[i,k]·fj_buf[k].
    // tree_sample: chốt lá vào ukf_fp_add_reduce_tree; tree_sum_valid → cập nhật mac_sum_r.

    logic                     pe_par_en;
    logic                     fj_lane_phase;
    logic                     tree_sample;
    logic signed [DATA_W-1:0] tree_sum;
    logic                     tree_sum_valid;
    logic signed [DATA_W-1:0] pe_par_prod [0:NLANE_MAC-1];
    logic signed [DATA_W-1:0] tree_leaf   [0:NLANE_MAC-1];

    always_comb begin
        for (int t = 0; t < NLANE_MAC; t++)
            tree_leaf[t] = pe_par_prod[t];
    end

    // Mỗi pe_mul: 1 chu kỳ trễ; valid_l=(gk<j_col) zero hóa lane không dùng cho cột j hiện tại.

    genvar gi;
    generate
    for (gi = 0; gi < NLANE_MAC; gi++) begin : g_pe
        logic signed [DATA_W-1:0] op_ai, op_bi;
        logic                     op_vi;
        logic unsigned [2:0]    gk;

        always_comb begin
            gk = unsigned'(gi);
            if (fj_lane_phase) begin
                op_ai = L_reg[idx_rc(j_col, gk)];
                op_bi = D_reg[gk];
            end else begin
                op_ai = L_reg[idx_rc(i_row, gk)];
                op_bi = fj_buf[gk];
            end
            op_vi = gk < j_col;
        end

        pe_mul #(.DATA_W(DATA_W)) u_pe (
            .clk     (clk),
            .rst     (rst),
            .en      (pe_par_en),
            .valid_l (op_vi),
            .op_a    (op_ai),
            .op_b    (op_bi),
            .product (pe_par_prod[gi]),
            .rdy     ()
        );
    end
    endgenerate

    // Cây cộng FP có độ trễ cố định; FSM chờ tree_sum_valid trước khi SUB.

    ukf_fp_add_reduce_tree #(
        .NUM_IN (NLANE_MAC),
        .DATA_W (DATA_W)
    ) u_mac_tree (
        .clk        (clk),
        .rst        (rst),
        .sample     (tree_sample),
        .leaf_in    (tree_leaf),
        .sum_out    (tree_sum),
        .sum_valid  (tree_sum_valid)
    );

    // --- Trạng thái FSM --------------------------------------------------------
    // Nạp: IDLE,LOAD_X,LOAD_P,CLR_L | LDL cột j: COL_ENTRY,FJ_*,MAC_*,SUB_*,PIV,WR_*,DIV,L_*,ROW,ADV_J
    // Sigma: WX0, SIG_SQ/GMA/OP/MUL/PADD hoặc NSUB, DONE

    typedef enum logic [5:0] {
        S_IDLE,
        S_LOAD_X,
        S_LOAD_P,
        S_CLR_L,
        S_COL_ENTRY,
        S_FJ_PE,
        S_FJ_WAIT,
        S_FJ_CAP,
        S_MAC_PE,
        S_MAC_WAIT,
        S_MAC_TR,
        S_MAC_TW,
        S_SUB_ISS,
        S_SUB_WAIT,
        S_PIV,
        S_WR_D,
        S_WR_LJJ,
        S_ROW_NEXT,
        S_DIV_ISS,
        S_DIV_WAIT,
        S_L_ST,
        S_L_MEM,
        S_ADV_J,
        S_WX0,
        S_SIG_SQ_ISS,
        S_SIG_SQ_WAIT,
        S_SIG_GMA_ISS,
        S_SIG_GMA_WAIT,
        S_SIG_OP_LD,
        S_SIG_MUL_ISS,
        S_SIG_MUL_WAIT,
        S_SIG_PADD_ISS,
        S_SIG_PADD_WAIT,
        S_SIG_NSUB_ISS,
        S_SIG_NSUB_WAIT,
        S_DONE
    } sg_state_t;

    sg_state_t sg_state;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            sg_state       <= S_IDLE;
            done           <= 1'b0;
            sigma_err      <= 1'b0;
            mem_rd_en      <= 1'b0;
            mem_wr_en      <= 1'b0;
            load_cnt       <= '0;
            mem_cnt        <= '0;
            clr_idx        <= '0;
            j_col          <= 3'd0;
            i_row          <= 3'd0;
            sig_i          <= 3'd0;
            elem_idx       <= 3'd0;
            sig_neg_phase  <= 1'b0;
            fe_start       <= 1'b0;
            sig_op_a       <= '0;
            sig_op_b       <= '0;
            mac_sum_r      <= `FP_ZERO;
            pe_par_en      <= 1'b0;
            fj_lane_phase  <= 1'b0;
            tree_sample    <= 1'b0;
        end else begin
            mem_rd_en      <= 1'b0;
            mem_wr_en      <= 1'b0;
            done           <= 1'b0;
            fe_start       <= 1'b0;
            pe_par_en      <= 1'b0;
            tree_sample    <= 1'b0;

            // -- Mỗi nhánh case: chuyển trạng thái / xung điều khiển một chu kỳ --

            case (sg_state)
            S_IDLE: begin
                if (start) begin
                    load_cnt      <= '0;
                    mem_cnt       <= '0;
                    clr_idx       <= '0;
                    sigma_err     <= 1'b0;
                    sig_neg_phase <= 1'b0;
                    sg_state      <= S_LOAD_X;
                end
            end

            // Đọc vector trạng thái x từ ADDR_X vào x_vec (dùng khi ghi điểm sigma χ0 và χ±).

            S_LOAD_X: begin
                mem_rd_en   <= 1'b1;
                mem_rd_addr <= `ADDR_X + {{(`ADDR_W-4){1'b0}}, load_cnt};
                if (load_cnt > 0)
                    x_vec[load_cnt - 1] <= $signed(mem_rd_data);
                load_cnt <= load_cnt + 1;
                if (load_cnt == N[3:0]) begin
                    x_vec[N-1] <= $signed(mem_rd_data);
                    load_cnt   <= '0;
                    mem_cnt    <= '0;
                    sg_state   <= S_LOAD_P;
                end
            end

            // Đọc hiệp phương sai P (row-major) từ ADDR_P vào P_reg.

            S_LOAD_P: begin
                mem_rd_en   <= 1'b1;
                mem_rd_addr <= `ADDR_P + {{(`ADDR_W-MAT_IW){1'b0}}, mem_cnt};
                if (mem_cnt > 0)
                    P_reg[mem_cnt - 1] <= $signed(mem_rd_data);
                mem_cnt <= mem_cnt + 1;
                if (mem_cnt == NN[$clog2(NN):0]) begin
                    P_reg[NN-1] <= $signed(mem_rd_data);
                    clr_idx     <= '0;
                    j_col       <= 3'd0;
                    sg_state    <= S_CLR_L;
                end
            end

            // Xoá L trong thanh ghi + đồng bộ vùng ADDR_L_UKF trong RAM (ma trận L mới).

            S_CLR_L: begin
                L_reg[clr_idx] <= `FP_ZERO;
                mem_wr_en      <= 1'b1;
                mem_wr_addr    <= `ADDR_L_UKF + {{(`ADDR_W-MAT_IW){1'b0}}, clr_idx};
                mem_wr_data    <= `FP_ZERO;
                if (clr_idx == (NN[4:0] - 1'b1))
                    sg_state <= S_COL_ENTRY;
                clr_idx        <= clr_idx + 1;
            end

            // Vào cột j: nếu j>0 cần fj_buf trước; j=0 không có k<j nên bỏ MAC, F_00 = P_00.

            S_COL_ENTRY: begin
                if (j_col > 3'd0) begin
                    fj_lane_phase <= 1'b1;
                    sg_state      <= S_FJ_PE;
                end else begin
                    i_row <= j_col;
                    mac_sum_r <= `FP_ZERO;
                    if (j_col == 3'd0)
                        sg_state <= S_SUB_ISS;
                    else
                        sg_state <= S_MAC_PE;
                end
            end

            // Preload F[j,k]: en PE một xung; chờ S_FJ_WAIT để product ổn định rồi chốt S_FJ_CAP.

            S_FJ_PE: begin
                pe_par_en     <= 1'b1;
                fj_lane_phase <= 1'b1;
                sg_state      <= S_FJ_WAIT;
            end
            // Một CK không en: tránh cùng posedge với cập nhật product trong pe_mul.

            S_FJ_WAIT: begin
                fj_lane_phase <= 1'b1;
                sg_state      <= S_FJ_CAP;
            end
            // Ghi fj_buf; i_row=j sẵn cho bước đường chéo F[j,j].

            S_FJ_CAP: begin
                fj_lane_phase <= 1'b0;
                for (int pp = 0; pp < NLANE_MAC; pp++) begin
                    if (pp < j_col)
                        fj_buf[pp] <= pe_par_prod[pp];
                    else
                        fj_buf[pp] <= `FP_ZERO;
                end
                i_row     <= j_col;
                mac_sum_r <= `FP_ZERO;
                sg_state  <= S_MAC_PE;
            end

            S_MAC_PE: begin
                fj_lane_phase <= 1'b0;
                pe_par_en     <= 1'b1;
                sg_state      <= S_MAC_WAIT;
            end
            // Một CK không en: leaf tree_sample không trùng posedge với gán product.

            S_MAC_WAIT: begin
                fj_lane_phase <= 1'b0;
                sg_state      <= S_MAC_TR;
            end
            // Chốt product vào reduce tree (một xung sample).

            S_MAC_TR: begin
                tree_sample <= 1'b1;
                sg_state    <= S_MAC_TW;
            end
            // Chờ pipeline cây; khi sum_valid: mac_sum_r = Σ (đã pad lane thừa bằng 0).

            S_MAC_TW: begin
                if (tree_sum_valid) begin
                    mac_sum_r <= tree_sum;
                    sg_state  <= S_SUB_ISS;
                end
            end

            // Tính F[i,j] tường minh: f_ij_r ← P[i,j] − mac_sum_r (SUB trên FP engine).

            S_SUB_ISS: begin
                fe_start <= 1'b1;
                fe_op    <= UKF_FP_SUB;
                fe_a     <= P_reg[idx_rc(i_row, j_col)];
                fe_b     <= mac_sum_r;
                sg_state <= S_SUB_WAIT;
            end
            // Chờ FP engine; f_ij_r lưu F[i,j] để pivot (i=j) hoặc chia L[i,j] (i>j).

            S_SUB_WAIT: begin
                if (fe_rdy) begin
                    f_ij_r <= fe_y;
                    sg_state <= (i_row == j_col) ? S_PIV : S_DIV_ISS;
                end
            end

            S_PIV: begin
                if (fp32_le_zero(f_ij_r)) begin
                    D_reg[j_col] <= `FP_EPSILON;
                    sigma_err    <= 1'b1;
                end else
                    D_reg[j_col] <= f_ij_r;
                L_reg[idx_rc(j_col, j_col)] <= `FP_ONE;
                sg_state <= S_WR_D;
            end

            S_WR_D: begin
                mem_wr_en   <= 1'b1;
                mem_wr_addr <= addr_D_word(j_col);
                mem_wr_data <= D_reg[j_col];
                sg_state    <= S_WR_LJJ;
            end

            S_WR_LJJ: begin
                mem_wr_en   <= 1'b1;
                mem_wr_addr <= addr_L_word(j_col, j_col);
                mem_wr_data <= `FP_ONE;
                sg_state    <= S_ROW_NEXT;
            end

            // Hàng dưới chéo: i++ hoặc hết cột → ADV_J; mac_sum_r xóa trước MAC mới.

            S_ROW_NEXT: begin
                if (i_row == N[2:0] - 1)
                    sg_state <= S_ADV_J;
                else begin
                    i_row     <= i_row + 1'b1;
                    mac_sum_r <= `FP_ZERO;
                    if (j_col == 3'd0)
                        sg_state <= S_SUB_ISS;
                    else
                        sg_state <= S_MAC_PE;
                end
            end

            // i>j: L[i,j] = F[i,j] / D[j] (chia FP engine, tránh chia cho 0).

            S_DIV_ISS: begin
                begin
                    logic signed [DATA_W-1:0] djj;
                    djj = D_reg[j_col];
                    if (!fp_abs_gt_eps(djj, `FP_EPSILON))
                        djj = `FP_EPSILON;
                    fe_start <= 1'b1;
                    fe_op    <= UKF_FP_DIV;
                    fe_a     <= f_ij_r;
                    fe_b     <= djj;
                end
                sg_state <= S_DIV_WAIT;
            end
            S_DIV_WAIT: begin
                if (fe_rdy) begin
                    l_ij_save <= fe_y;
                    sg_state  <= S_L_ST;
                end
            end

            S_L_ST: begin
                L_reg[idx_rc(i_row, j_col)] <= l_ij_save;
                sg_state <= S_L_MEM;
            end

            S_L_MEM: begin
                mem_wr_en   <= 1'b1;
                mem_wr_addr <= addr_L_word(i_row, j_col);
                mem_wr_data <= l_ij_save;
                sg_state    <= S_ROW_NEXT;
            end

            // Hết LDL: ghi χ0 = x, rồi lặp sigma theo cột j (α=γ√D[j], ±α·L[:,j]).

            S_ADV_J: begin
                if (j_col == N[2:0] - 1) begin
                    elem_idx <= 3'd0;
                    sg_state <= S_WX0;
                end else begin
                    j_col    <= j_col + 1'b1;
                    sg_state <= S_COL_ENTRY;
                end
            end

            // Điểm sigma thứ 0 (hàng đầu bảng σ): copy x_vec → ADDR_SIGMA.

            S_WX0: begin
                mem_wr_en   <= 1'b1;
                mem_wr_addr <= `ADDR_SIGMA + {{(`ADDR_W-4){1'b0}}, elem_idx};
                mem_wr_data <= x_vec[elem_idx];
                if (elem_idx == N[2:0] - 1) begin
                    sig_i         <= 3'd0;
                    sig_neg_phase <= 1'b0;
                    sg_state      <= S_SIG_SQ_ISS;
                end else
                    elem_idx <= elem_idx + 1'b1;
            end

            // Vòng sigma mỗi cột j: √D[j] → nhân γ → nhân α·L[i,j] → cộng/trừ với x (χ⁺ rồi χ⁻).

            S_SIG_SQ_ISS: begin
                fe_start <= 1'b1;
                fe_op    <= UKF_FP_SQRT;
                fe_a     <= D_reg[sig_i];
                fe_b     <= `FP_ZERO;
                sg_state <= S_SIG_SQ_WAIT;
            end
            S_SIG_SQ_WAIT: begin
                if (fe_rdy) begin
                    d_tmp    <= fe_y;
                    sg_state <= S_SIG_GMA_ISS;
                end
            end

            S_SIG_GMA_ISS: begin
                fe_start <= 1'b1;
                fe_op    <= UKF_FP_MUL;
                fe_a     <= gamma;
                fe_b     <= d_tmp;
                sg_state <= S_SIG_GMA_WAIT;
            end
            S_SIG_GMA_WAIT: begin
                if (fe_rdy) begin
                    alpha_reg <= fe_y;
                    elem_idx  <= 3'd0;
                    sg_state  <= S_SIG_OP_LD;
                end
            end

            S_SIG_OP_LD: begin
                sig_op_a <= alpha_reg;
                sig_op_b <= L_reg[idx_rc(elem_idx, sig_i)];
                sg_state <= S_SIG_MUL_ISS;
            end

            S_SIG_MUL_ISS: begin
                fe_start <= 1'b1;
                fe_op    <= UKF_FP_MUL;
                fe_a     <= sig_op_a;
                fe_b     <= sig_op_b;
                sg_state <= S_SIG_MUL_WAIT;
            end
            S_SIG_MUL_WAIT: begin
                if (fe_rdy) begin
                    s_elem   <= fe_y;
                    sg_state <= sig_neg_phase ? S_SIG_NSUB_ISS : S_SIG_PADD_ISS;
                end
            end

            S_SIG_PADD_ISS: begin
                fe_start <= 1'b1;
                fe_op    <= UKF_FP_ADD;
                fe_a     <= x_vec[elem_idx];
                fe_b     <= s_elem;
                sg_state <= S_SIG_PADD_WAIT;
            end
            S_SIG_PADD_WAIT: begin
                if (fe_rdy) begin
                    mem_wr_en   <= 1'b1;
                    mem_wr_addr <= addr_sigma_plus(sig_i + 1'b1, elem_idx);
                    mem_wr_data <= fe_y;
                    if (elem_idx == N[2:0] - 1) begin
                        elem_idx <= 3'd0;
                        if (sig_i == N[2:0] - 1) begin
                            sig_i         <= 3'd0;
                            sig_neg_phase <= 1'b1;
                            sg_state      <= S_SIG_SQ_ISS;
                        end else begin
                            sig_i    <= sig_i + 1'b1;
                            sg_state <= S_SIG_SQ_ISS;
                        end
                    end else begin
                        elem_idx <= elem_idx + 1'b1;
                        sg_state <= S_SIG_OP_LD;
                    end
                end
            end

            S_SIG_NSUB_ISS: begin
                fe_start <= 1'b1;
                fe_op    <= UKF_FP_SUB;
                fe_a     <= x_vec[elem_idx];
                fe_b     <= s_elem;
                sg_state <= S_SIG_NSUB_WAIT;
            end
            S_SIG_NSUB_WAIT: begin
                if (fe_rdy) begin
                    mem_wr_en   <= 1'b1;
                    mem_wr_addr <= addr_sigma_plus(N + sig_i + 1'b1, elem_idx);
                    mem_wr_data <= fe_y;
                    if (elem_idx == N[2:0] - 1) begin
                        elem_idx <= 3'd0;
                        if (sig_i == N[2:0] - 1)
                            sg_state <= S_DONE;
                        else begin
                            sig_i    <= sig_i + 1'b1;
                            sg_state <= S_SIG_SQ_ISS;
                        end
                    end else begin
                        elem_idx <= elem_idx + 1'b1;
                        sg_state <= S_SIG_OP_LD;
                    end
                end
            end

            S_DONE: begin
                done     <= 1'b1;
                sg_state <= S_IDLE;
            end

            default: sg_state <= S_IDLE;
            endcase
        end
    end

endmodule
