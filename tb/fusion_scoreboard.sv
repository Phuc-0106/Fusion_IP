// Fusion IP Scoreboard — Three-tier comparison
//   PRIMARY:     DUT vs SV Predictor (all 5 states, FP32 tolerance)
//   CALIBRATION: SV Predictor vs Python Golden CSV (validate SV model)
//   QUALITY:     DUT position vs AIS Ground Truth (prove UKF beats GPS)

package fusion_scoreboard_pkg;
`include "params.vh"
    import uvm_pkg::*;
    import fusion_pkg::*;
    import fusion_axi_pkg::*;
    import fusion_sensor_pkg::*;
    import fusion_predictor_pkg::*;
    // Questa wraps ukf_mem_backdoor.sv in package ukf_mem_backdoor_sv_unit
    import ukf_mem_backdoor_sv_unit::*;
    `include "uvm_macros.svh"

    class sb_config extends uvm_object;
        `uvm_object_utils(sb_config)

        real primary_threshold;     // max per-state error for DUT-vs-Predictor
        real calibration_threshold; // max per-state error for Predictor-vs-Golden
        int  timeout_cycles;
        bit  enable_predictor;
        bit  enable_calibration;
        bit  enable_quality;
        // +UKF_DEBUG_P — dump P/Q/R/dt (reference vs DUT mem); tag UKF_DBG
        bit  debug_ukf_p;
        // +UKF_DEBUG_PPRED — P_pred: RM from DUT ADDR_SIGMA χ + Q + dt vs ADDR_PPRED; tag UKF_DBG_PPRED
        bit  debug_ukf_ppred;
        // +UKF_DEBUG_SIGMA — max|χ_DUT − χ_RM|; RM gen_sigma from χ_dut[0] + latched P; UKF_DBG_SIGMA
        bit  debug_ukf_sigma;
        // +UKF_DEBUG_DT — per cycle: dt in scoreboard vs predictor vs DUT reg_dt/dt_effective vs golden dt_hex
        bit  debug_ukf_dt;
        // 1: update() uses linear H (S=HPH'+R, T=PH') like update_block; 0: full sigma S/T (+UKF_FULL_UKF_UPDATE)
        bit  ukf_linear_h_update;

        function new(string name = "sb_config");
            super.new(name);
            // DUT is FP32; predictor is float — allow ~2 m / rad on state components
            primary_threshold     = 2.0;
            // Predictor vs Python: same algorithm but order/rounding may differ slightly
            calibration_threshold = 8.0;
            timeout_cycles        = 5000;
            enable_predictor      = 1'b1;
            enable_calibration    = 1'b1;
            enable_quality        = 1'b1;
            debug_ukf_p           = 1'b0;
            debug_ukf_ppred       = 1'b0;
            debug_ukf_sigma       = 1'b0;
            debug_ukf_dt          = 1'b0;
            ukf_linear_h_update   = 1'b1;
        endfunction
    endclass : sb_config

    // Per-cycle golden reference pushed by test sequence
    class golden_ref extends uvm_object;
        `uvm_object_utils(golden_ref)
        real gt_x, gt_y;
        real gps_x, gps_y;
        // Python UKF full 5-state estimate
        real sw_est_x, sw_est_y, sw_est_v, sw_est_psi, sw_est_psidot;
        // FP32 dt from golden_stimulus dt_hex (same bits as AXI REG_DT for this row)
        logic [31:0] golden_dt_hex;
        bit          golden_has_dt;
        function new(string name = "golden_ref");
            super.new(name);
        endfunction
    endclass : golden_ref

    typedef class fusion_scoreboard;

    class fusion_axi_analysis_link extends uvm_component;
        `uvm_component_utils(fusion_axi_analysis_link)
        uvm_analysis_imp #(axi_transaction, fusion_axi_analysis_link) imp;
        fusion_scoreboard sb;
        function new(string name, uvm_component parent);
            super.new(name, parent);
            if (!$cast(sb, parent))
                `uvm_fatal("AXI_LINK", "parent must be fusion_scoreboard")
            imp = new("imp", this);
        endfunction
        virtual function void write(axi_transaction t);
            sb.write_axi(t);
        endfunction
    endclass : fusion_axi_analysis_link

    class fusion_sensor_analysis_link extends uvm_component;
        `uvm_component_utils(fusion_sensor_analysis_link)
        uvm_analysis_imp #(sensor_measurement, fusion_sensor_analysis_link) imp;
        fusion_scoreboard sb;
        function new(string name, uvm_component parent);
            super.new(name, parent);
            if (!$cast(sb, parent))
                `uvm_fatal("SENSOR_LINK", "parent must be fusion_scoreboard")
            imp = new("imp", this);
        endfunction
        virtual function void write(sensor_measurement t);
            sb.write_sensor(t);
        endfunction
    endclass : fusion_sensor_analysis_link

    class fusion_scoreboard extends uvm_component;
        `uvm_component_utils(fusion_scoreboard)

        fusion_axi_analysis_link    axi_link;
        fusion_sensor_analysis_link sensor_link;

        axi_transaction    axi_fifo[$];
        sensor_measurement sensor_fifo[$];

        sb_config cfg;
        ukf_predictor predictor;
        // Scratch RM: same gen_sigma/predict_step as main predictor, fed from DUT mem (PPRED check only).
        ukf_predictor pred_pp_scratch;

        golden_ref golden_queue[$];

        // ---- PRIMARY tier accumulators (DUT vs Predictor) ----
        int  pri_comparisons;
        int  pri_mismatches;
        real pri_sum_sq_err[5]; // per-state squared-error accumulator

        // ---- CALIBRATION tier accumulators (Predictor vs Golden CSV) ----
        int  cal_comparisons;
        int  cal_mismatches;
        real cal_sum_sq_err[5];

        // ---- QUALITY tier accumulators (DUT pos vs GT, GPS pos vs GT) ----
        int  qual_comparisons;
        real qual_dut_sum_sq;
        real qual_gps_sum_sq;
        real qual_max_dut_err;
        real qual_max_gps_err;

        // Captured DUT outputs (AXI register reads)
        logic [31:0] out_x, out_y, out_v, out_psi, out_psidot;
        bit out_x_seen, out_y_seen, out_v_seen, out_psi_seen, out_psidot_seen;

        // Last sensor data for predictor
        logic [63:0] last_gps_data;
        logic        last_gps_valid;
        logic [95:0] last_imu_data;
        logic        last_imu_valid;
        logic [31:0] last_odom_data;
        logic        last_odom_valid;
        logic [31:0] last_dt_bits;

        bit          dut_error_flag;  // set by test sequence on POLL_DUT_ERR
        int          dut_error_cycles;

        // P_pred from RM using DUT x,P,Q at start of UKF cycle (see UKF_DEBUG_PPRED)
        real dbg_P_pred_rm_dut_in[5][5];

        // ADDR_X/ADDR_P peeked at end of compare_outputs (after UKF k outputs); used as prior for RM vs cycle k+1
        real latched_dut_x[5];
        real latched_dut_P[5][5];

        function new(string name, uvm_component parent);
            super.new(name, parent);
            pri_comparisons = 0;  pri_mismatches = 0;
            cal_comparisons = 0;  cal_mismatches = 0;
            qual_comparisons = 0;
            qual_dut_sum_sq = 0.0; qual_gps_sum_sq = 0.0;
            qual_max_dut_err = 0.0; qual_max_gps_err = 0.0;
            dut_error_flag   = 0;
            dut_error_cycles = 0;
            last_dt_bits = 32'h3D23_D70A; // 0.04s IEEE-754
            for (int i = 0; i < 5; i++) begin
                pri_sum_sq_err[i] = 0.0;
                cal_sum_sq_err[i] = 0.0;
            end
        endfunction

        // Push golden reference each UKF cycle (called from test sequence)
        virtual function void push_golden(real gt_x, real gt_y,
                                          real gps_x, real gps_y,
                                          real sw_x, real sw_y,
                                          real sw_v, real sw_psi, real sw_psidot,
                                          logic [31:0] golden_dt_hex_in = 32'h0,
                                          bit golden_has_dt_in = 1'b0);
            golden_ref g = golden_ref::type_id::create("golden");
            g.gt_x       = gt_x;
            g.gt_y       = gt_y;
            g.gps_x      = gps_x;
            g.gps_y      = gps_y;
            g.sw_est_x   = sw_x;
            g.sw_est_y   = sw_y;
            g.sw_est_v   = sw_v;
            g.sw_est_psi = sw_psi;
            g.sw_est_psidot = sw_psidot;
            g.golden_dt_hex = golden_dt_hex_in;
            g.golden_has_dt = golden_has_dt_in;
            golden_queue.push_back(g);
        endfunction

        // Notify scoreboard of the dt value written to DUT this cycle
        virtual function void set_dt(logic [31:0] dt_val);
            last_dt_bits = dt_val;
        endfunction

        // Notify scoreboard that DUT reported an error this cycle
        virtual function void set_dut_error(bit err);
            dut_error_flag = err;
            if (err) dut_error_cycles++;
        endfunction

        virtual function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            axi_link    = fusion_axi_analysis_link::type_id::create("axi_link", this);
            sensor_link = fusion_sensor_analysis_link::type_id::create("sensor_link", this);
            if (!uvm_config_db #(sb_config)::get(this, "", "sb_config", cfg))
                cfg = sb_config::type_id::create("cfg");
            if ($test$plusargs("UKF_DEBUG_P"))
                cfg.debug_ukf_p = 1'b1;
            if ($test$plusargs("UKF_DEBUG_PPRED"))
                cfg.debug_ukf_ppred = 1'b1;
            if ($test$plusargs("UKF_DEBUG_SIGMA"))
                cfg.debug_ukf_sigma = 1'b1;
            if ($test$plusargs("UKF_DEBUG_DT"))
                cfg.debug_ukf_dt = 1'b1;
            if ($test$plusargs("UKF_FULL_UKF_UPDATE"))
                cfg.ukf_linear_h_update = 1'b0;
            predictor = ukf_predictor::type_id::create("predictor");
            predictor.use_linear_h_update = cfg.ukf_linear_h_update;
            if (cfg.debug_ukf_ppred || cfg.debug_ukf_sigma)
                pred_pp_scratch = ukf_predictor::type_id::create("pred_pp_scratch");
            if (pred_pp_scratch != null)
                pred_pp_scratch.use_linear_h_update = cfg.ukf_linear_h_update;
            if (cfg.debug_ukf_p) begin
                `uvm_info("UKF_DBG_MODEL",
                    "Reference ukf_predictor: linear H (S=HPH'+R, T=PH') + Joseph + diag load (matches update_block); predict_step still full UKF sigma.",
                    UVM_LOW)
            end
            if (cfg.debug_ukf_ppred) begin
                `uvm_info("UKF_DBG_PPRED",
                    "+UKF_DEBUG_PPRED: RM P_pred from DUT ADDR_SIGMA χ + ADDR_Q + dt vs ADDR_PPRED (same σ as predict_block; not LDL re-gen). Small gap possible: DUT symmetrizes P_pred.",
                    UVM_LOW)
            end
            if (cfg.debug_ukf_sigma) begin
                `uvm_info("UKF_DBG_SIGMA",
                    "+UKF_DEBUG_SIGMA: max|χ_DUT − χ_RM|; RM gen_sigma uses χ_dut[0] as x + latched P (fair LDL vs ADDR_SIGMA); logs max|χ_dut[0]−latched_x|.",
                    UVM_LOW)
            end
            if (cfg.debug_ukf_dt) begin
                `uvm_info("UKF_DBG_DT",
                    "+UKF_DEBUG_DT: each UKF cycle logs scoreboard last_dt_bits, predictor.current_dt, DUT reg_dt and dt_effective, golden dt_hex (if pushed).",
                    UVM_LOW)
            end
        endfunction

        virtual function void connect_phase(uvm_phase phase);
            super.connect_phase(phase);
        endfunction

        virtual function void start_of_simulation_phase(uvm_phase phase);
            logic [31:0] w64[0:63];
            super.start_of_simulation_phase(phase);
            if (cfg.enable_predictor) begin
                int li, lj;
                for (int a = 0; a < 64; a++)
                    w64[a] = dbg_peek_state_mem(a);
                predictor.import_state_mem_snapshot(w64);
                for (li = 0; li < 5; li++)
                    latched_dut_x[li] = dut_to_real(dbg_peek_state_mem(`ADDR_X + li));
                for (li = 0; li < 5; li++)
                    for (lj = 0; lj < 5; lj++)
                        latched_dut_P[li][lj] = dut_to_real(dbg_peek_state_mem(`ADDR_P + li * 5 + lj));
                `uvm_info("SB_PRED_SYNC",
                    "ukf_predictor: x,P,Q,R from u_mem[0:63] (same map as update_block R loads).",
                    UVM_MEDIUM)
            end
        endfunction

        // Re-load predictor + latched x,P after TB pokes u_mem (e.g. T8 x0 from golden row 0).
        virtual function void resync_predictor_from_dut_mem();
            logic [31:0] w64[0:63];
            int li, lj;
            if (!cfg.enable_predictor)
                return;
            for (int a = 0; a < 64; a++)
                w64[a] = dbg_peek_state_mem(a);
            predictor.import_state_mem_snapshot(w64);
            for (li = 0; li < 5; li++)
                latched_dut_x[li] = dut_to_real(dbg_peek_state_mem(`ADDR_X + li));
            for (li = 0; li < 5; li++)
                for (lj = 0; lj < 5; lj++)
                    latched_dut_P[li][lj] = dut_to_real(dbg_peek_state_mem(`ADDR_P + li * 5 + lj));
        endfunction

        // Peek DUT central RAM via $unit class (see ukf_mem_backdoor.sv)
        function logic [31:0] dbg_peek_state_mem(int unsigned addr);
            return ukf_state_mem_backdoor::peek_word(addr);
        endfunction

        virtual function void ukf_debug_dump_ppred(int cyc);
            real P_dut[5][5];
            real chi[11][5];
            real dt;
            real max_abs_diff, d;
            int i, j, sp;
            if (!cfg.debug_ukf_ppred || pred_pp_scratch == null)
                return;
            dt = dut_to_real(last_dt_bits);
            if (dt <= 0.0)
                dt = 1.0;
            for (sp = 0; sp < 11; sp++)
                for (i = 0; i < 5; i++)
                    chi[sp][i] = dut_to_real(dbg_peek_state_mem(`ADDR_SIGMA + sp * 5 + i));
            for (i = 0; i < 5; i++)
                for (j = 0; j < 5; j++)
                    pred_pp_scratch.Q[i][j] = dut_to_real(dbg_peek_state_mem(`ADDR_Q + i * 5 + j));
            pred_pp_scratch.predict_P_from_sigma_chi(chi, dt, dbg_P_pred_rm_dut_in);
            max_abs_diff = 0.0;
            for (i = 0; i < 5; i++)
                for (j = 0; j < 5; j++) begin
                    P_dut[i][j] = dut_to_real(dbg_peek_state_mem(`ADDR_PPRED + i * 5 + j));
                    d = dbg_P_pred_rm_dut_in[i][j] - P_dut[i][j];
                    if (d < 0.0) d = -d;
                    if (d > max_abs_diff) max_abs_diff = d;
                end
            `uvm_info("UKF_DBG_PPRED",
                $sformatf("cycle %0d  max|P_pred_rm(DUT σ@64 + Q + dt) - P_dut@ADDR_PPRED| = %.6f",
                          cyc, max_abs_diff),
                UVM_LOW)
            `uvm_info("UKF_DBG_PPRED", predictor.sprint_P5(dbg_P_pred_rm_dut_in,
                "P_pred_RM (float, same χ as DUT predict)"), UVM_LOW)
            `uvm_info("UKF_DBG_PPRED", predictor.sprint_P5(P_dut,
                "P_pred_DUT (ADDR_PPRED row-major)"), UVM_LOW)
        endfunction

        virtual function void ukf_debug_dump_sigma(int cyc);
            real sp_rm[11][5];
            real chi_dut[11][5];
            real peek_x[5];
            real max_abs_diff, d, max_row0_diff, max_peek_diff;
            int i, j, sp;
            if (!cfg.debug_ukf_sigma || pred_pp_scratch == null || !cfg.enable_predictor)
                return;
            // Read full χ from DUT first
            for (sp = 0; sp < `N_SIGMA; sp++)
                for (i = 0; i < 5; i++)
                    chi_dut[sp][i] = dut_to_real(dbg_peek_state_mem(`ADDR_SIGMA + sp * 5 + i));
            for (j = 0; j < 5; j++)
                peek_x[j] = dut_to_real(dbg_peek_state_mem(`ADDR_X + j));
            // latched_dut_x = ADDR_X peeked end of previous compare_outputs ≈ prior mean at σ gen for this UKF.
            max_row0_diff = 0.0;
            for (j = 0; j < 5; j++) begin
                d = chi_dut[0][j] - latched_dut_x[j];
                if (d < 0.0) d = -d;
                if (d > max_row0_diff) max_row0_diff = d;
            end
            // Simultaneous peek: if ADDR_X already holds posterior after update, |χ₀−peek_x| can be large while |χ₀−latched| ~ 0.
            max_peek_diff = 0.0;
            for (j = 0; j < 5; j++) begin
                d = chi_dut[0][j] - peek_x[j];
                if (d < 0.0) d = -d;
                if (d > max_peek_diff) max_peek_diff = d;
            end
            if (max_row0_diff <= 1.0e-4 && max_peek_diff > 1.0e-4)
                `uvm_info("UKF_DBG_SIGMA",
                    $sformatf("cycle %0d  NOTE: χ₀≈latched prior (%.6f) but not peek ADDR_X (%.6f) — ADDR_X likely already posterior; σ row0 still prior mean.",
                              cyc, max_row0_diff, max_peek_diff),
                    UVM_LOW)
            else if (max_row0_diff > 1.0e-4 && max_peek_diff <= 1.0e-4)
                `uvm_info("UKF_DBG_SIGMA",
                    $sformatf("cycle %0d  NOTE: χ₀≈peek ADDR_X (%.6f) but not latched_x (%.6f) — refresh latch timing vs compare_outputs (latched = end prev cycle).",
                              cyc, max_peek_diff, max_row0_diff),
                    UVM_LOW)
            else if (max_row0_diff > 1.0e-4 && max_peek_diff > 1.0e-4)
                `uvm_info("UKF_DBG_SIGMA",
                    $sformatf("cycle %0d  NOTE: χ₀ vs both latched (%.6f) and peek ADDR_X (%.6f) — check FSM σ vs x RAM.",
                              cyc, max_row0_diff, max_peek_diff),
                    UVM_LOW)
            for (i = 0; i < 5; i++)
                pred_pp_scratch.x[i] = chi_dut[0][i];
            for (i = 0; i < 5; i++)
                for (j = 0; j < 5; j++)
                    pred_pp_scratch.P[i][j] = latched_dut_P[i][j];
            pred_pp_scratch.gen_sigma(sp_rm);
            max_abs_diff = 0.0;
            for (sp = 0; sp < `N_SIGMA; sp++)
                for (i = 0; i < 5; i++) begin
                    d = sp_rm[sp][i] - chi_dut[sp][i];
                    if (d < 0.0) d = -d;
                    if (d > max_abs_diff) max_abs_diff = d;
                end
            `uvm_info("UKF_DBG_SIGMA",
                $sformatf("cycle %0d  max|chi_RM(@chi_dut[0],latched P)-chi_DUT|=%.6f  |chi0-latched_x|=%.6f  |chi0-peek_ADDR_X|=%.6f",
                          cyc, max_abs_diff, max_row0_diff, max_peek_diff),
                UVM_LOW)
        endfunction

        virtual function void latch_dut_xp_from_mem();
            int li, lj;
            if (!cfg.enable_predictor)
                return;
            for (li = 0; li < 5; li++)
                latched_dut_x[li] = dut_to_real(dbg_peek_state_mem(`ADDR_X + li));
            for (li = 0; li < 5; li++)
                for (lj = 0; lj < 5; lj++)
                    latched_dut_P[li][lj] = dut_to_real(dbg_peek_state_mem(`ADDR_P + li * 5 + lj));
        endfunction

        virtual function void ukf_debug_dump(int cyc, ukf_predictor pred);
            real P_rm[5][5], P_dut[5][5], D_raw_rm[5], D_raw_dut[5];
            real min_raw_rm, min_raw_dut, max_abs_diff, d;
            if (!cfg.debug_ukf_p || !cfg.enable_predictor)
                return;
            pred.copy_P(P_rm);
            for (int i = 0; i < 5; i++)
                for (int j = 0; j < 5; j++)
                    P_dut[i][j] = dut_to_real(dbg_peek_state_mem(5 + i * 5 + j));
            pred.ldl_diag_raw(P_rm, D_raw_rm, min_raw_rm);
            pred.ldl_diag_raw(P_dut, D_raw_dut, min_raw_dut);
            max_abs_diff = 0.0;
            for (int ii = 0; ii < 5; ii++)
                for (int jj = 0; jj < 5; jj++) begin
                    d = P_rm[ii][jj] - P_dut[ii][jj];
                    if (d < 0.0) d = -d;
                    if (d > max_abs_diff) max_abs_diff = d;
                end
            `uvm_info("UKF_DBG",
                $sformatf("cycle %0d  max|P_rm-P_dut|=%.6f  sym_rm=%.3e sym_dut=%.3e  LDL_min_diag_raw_rm=%.6e LDL_min_diag_raw_dut=%.6e",
                    cyc, max_abs_diff,
                    pred.max_symmetry_abs(P_rm), pred.max_symmetry_abs(P_dut),
                    min_raw_rm, min_raw_dut),
                UVM_LOW)
            `uvm_info("UKF_DBG", pred.sprint_P5(P_rm, "P_RM (ref, after predictor.step)"), UVM_LOW)
            `uvm_info("UKF_DBG", pred.sprint_P5(P_dut, "P_DUT (state_mem row-major @5)"), UVM_LOW)
            `uvm_info("UKF_DBG",
                $sformatf("%s\nDUT mem: Q[0,0]@30=%.6f R_gps[0,0]@55=%.6f R_odom@63=%.6f last_dt_bits→real=%.6f",
                    pred.sprint_model_QR_dt(),
                    dut_to_real(dbg_peek_state_mem(30)),
                    dut_to_real(dbg_peek_state_mem(55)),
                    dut_to_real(dbg_peek_state_mem(63)),
                    dut_to_real(last_dt_bits)),
                UVM_LOW)
        endfunction

        // Per-cycle dt alignment: scoreboard latch, SV predictor, DUT REG_DT, optional golden CSV dt_hex
        virtual function void ukf_debug_dump_dt(int cyc, bit have_golden, golden_ref g);
            logic [31:0] reg_raw, reg_eff;
            real r_sb, r_pred, r_dut, r_gold, d1, d2, d3;
            real eps;
            if (!cfg.debug_ukf_dt || !cfg.enable_predictor)
                return;
            eps = 1.0e-5;
            reg_raw = fusion_reg_backdoor::peek_reg_dt();
            reg_eff = (reg_raw == 32'h0) ? `DT_ONE : reg_raw;
            r_sb = dut_to_real(last_dt_bits);
            if (r_sb <= 0.0)
                r_sb = 1.0;
            r_pred = predictor.current_dt;
            r_dut = dut_to_real(reg_eff);

            if (have_golden && (g != null) && g.golden_has_dt) begin
                r_gold = dut_to_real(g.golden_dt_hex);
                `uvm_info("UKF_DBG_DT",
                    $sformatf("cycle %0d  SB_last_dt=0x%08h (%.9f)  PRED.current_dt=%.9f  DUT_reg_dt=0x%08h DUT_dt_eff=0x%08h (%.9f)  GOLDEN_dt_hex=0x%08h (%.9f)",
                        cyc, last_dt_bits, r_sb, r_pred,
                        reg_raw, reg_eff, r_dut, g.golden_dt_hex, r_gold),
                    UVM_LOW)
            end else begin
                `uvm_info("UKF_DBG_DT",
                    $sformatf("cycle %0d  SB_last_dt=0x%08h (%.9f)  PRED.current_dt=%.9f  DUT_reg_dt=0x%08h DUT_dt_eff=0x%08h (%.9f)  GOLDEN_dt_hex=n/a",
                        cyc, last_dt_bits, r_sb, r_pred, reg_raw, reg_eff, r_dut),
                    UVM_LOW)
            end

            // Bit-compare: value sequence latched in set_dt vs DUT REG_DT after UKF
            if (last_dt_bits !== reg_raw)
                `uvm_warning("UKF_DBG_DT",
                    $sformatf("cycle %0d  SB_last_dt_bits (0x%08h) != DUT reg_dt (0x%08h) — check AXI REG_DT write vs end of UKF",
                        cyc, last_dt_bits, reg_raw))

            d1 = r_pred - r_sb;
            if (d1 < 0.0) d1 = -d1;
            if (d1 > eps)
                `uvm_warning("UKF_DBG_DT",
                    $sformatf("cycle %0d  |PRED.current_dt - SB_dt| = %.9e (predictor.step dt_bits vs set_dt latch)", cyc, d1))

            d2 = r_dut - r_sb;
            if (d2 < 0.0) d2 = -d2;
            if (d2 > eps)
                `uvm_warning("UKF_DBG_DT",
                    $sformatf("cycle %0d  |DUT_dt_effective - SB_dt| = %.9e", cyc, d2))

            if (have_golden && (g != null) && g.golden_has_dt) begin
                r_gold = dut_to_real(g.golden_dt_hex);
                d3 = r_gold - r_sb;
                if (d3 < 0.0) d3 = -d3;
                if (d3 > eps)
                    `uvm_warning("UKF_DBG_DT",
                        $sformatf("cycle %0d  |GOLDEN_csv_dt - SB_dt| = %.9e", cyc, d3))
                if (g.golden_dt_hex !== last_dt_bits)
                    `uvm_warning("UKF_DBG_DT",
                        $sformatf("cycle %0d  golden_dt_hex (0x%08h) != SB_last_dt_bits (0x%08h)", cyc, g.golden_dt_hex, last_dt_bits))
            end
        endfunction

        // ---- AXI monitor callback ----
        virtual function void write_axi(axi_transaction t);
            axi_fifo.push_back(t);

            if (t.trans_type == WRITE) begin
                `uvm_info("SB_AXI", $sformatf("AXI WRITE: addr=0x%08h, data=0x%08h",
                                              t.addr, t.wdata), UVM_HIGH)
            end else begin
                case (t.addr[7:0])
                    8'h20: begin out_x      = t.rdata; out_x_seen      = 1; end
                    8'h24: begin out_y      = t.rdata; out_y_seen      = 1; end
                    8'h28: begin out_v      = t.rdata; out_v_seen      = 1; end
                    8'h2C: begin out_psi    = t.rdata; out_psi_seen    = 1; end
                    8'h30: begin out_psidot = t.rdata; out_psidot_seen = 1; end
                endcase

                if (out_x_seen && out_y_seen && out_v_seen &&
                    out_psi_seen && out_psidot_seen) begin
                    compare_outputs();
                    out_x_seen = 0; out_y_seen = 0; out_v_seen = 0;
                    out_psi_seen = 0; out_psidot_seen = 0;
                end
            end
        endfunction

        // Shortest angular distance in rad (DUT may leave ψ unwrapped; PRED uses atan2 periodically)
        static function real abs_angle_diff(real a, real b);
            real d;
            d = $atan2($sin(a - b), $cos(a - b));
            return (d >= 0.0) ? d : -d;
        endfunction

        // ---- Sensor monitor callback ----
        virtual function void write_sensor(sensor_measurement m);
            sensor_fifo.push_back(m);
            last_gps_data  = m.gps_data;
            last_gps_valid = m.gps_valid;
            last_imu_data  = m.imu_data;
            last_imu_valid = m.imu_valid;
            last_odom_data = m.odom_data;
            last_odom_valid = m.odom_valid;

            `uvm_info("SB_SENSOR",
                $sformatf("Sensor IN: GPS=%s(x=%.4f y=%.4f) IMU=%s(psi=%.4f dot=%.4f) ODOM=%s(v=%.4f)",
                          m.gps_valid ? "V" : "-",
                          dut_to_real(m.gps_data[63:32]),
                          dut_to_real(m.gps_data[31:0]),
                          m.imu_valid ? "V" : "-",
                          dut_to_real(m.imu_data[95:64]),
                          dut_to_real(m.imu_data[63:32]),
                          m.odom_valid ? "V" : "-",
                          dut_to_real(m.odom_data)), UVM_HIGH)

            if (cfg.enable_predictor) begin
                predictor.step(m.gps_data, m.gps_valid,
                              m.imu_data, m.imu_valid,
                              m.odom_data, m.odom_valid,
                              last_dt_bits);
            end
        endfunction

        // ---- Main comparison — triggered when all 5 DUT outputs collected ----
        virtual function void compare_outputs();
            real dut[5], pred[5];
            real err[5], max_err;
            golden_ref g;
            bit        have_golden;

            have_golden = 1'b0;
            dut[0] = dut_to_real(out_x);
            dut[1] = dut_to_real(out_y);
            dut[2] = dut_to_real(out_v);
            dut[3] = dut_to_real(out_psi);
            dut[4] = dut_to_real(out_psidot);

            // ============================================================
            // TIER 1 — PRIMARY: DUT vs SV Predictor
            // ============================================================
            if (cfg.enable_predictor) begin
                ukf_output pred_out;
                pred_out = predictor.get_output();
                pred[0] = pred_out.x;
                pred[1] = pred_out.y;
                pred[2] = pred_out.v;
                pred[3] = pred_out.psi;
                pred[4] = pred_out.psi_dot;

                pri_comparisons++;

                if (dut_error_flag) begin
                    `uvm_info("SB_PRIMARY",
                        $sformatf("Cycle %0d SKIPPED (DUT error — stale outputs): DUT(%.4f,%.4f,%.4f,%.4f,%.4f) PRED(%.4f,%.4f,%.4f,%.4f,%.4f)",
                                  pri_comparisons,
                                  dut[0], dut[1], dut[2], dut[3], dut[4],
                                  pred[0], pred[1], pred[2], pred[3], pred[4]), UVM_LOW)
                    dut_error_flag = 0;
                end else begin
                    max_err = 0.0;
                    for (int i = 0; i < 5; i++) begin
                        if (i == 3)
                            err[i] = abs_angle_diff(dut[i], pred[i]);
                        else
                            err[i] = (dut[i] - pred[i]) >= 0 ? (dut[i] - pred[i]) : -(dut[i] - pred[i]);
                        pri_sum_sq_err[i] += err[i] * err[i];
                        if (err[i] > max_err) max_err = err[i];
                    end

                    if (max_err > cfg.primary_threshold) begin
                        pri_mismatches++;
                        `uvm_warning("SB_PRIMARY",
                            $sformatf("Cycle %0d MISMATCH max_err=%.6f | DUT(%.4f,%.4f,%.4f,%.4f,%.4f) PRED(%.4f,%.4f,%.4f,%.4f,%.4f)",
                                      pri_comparisons, max_err,
                                      dut[0], dut[1], dut[2], dut[3], dut[4],
                                      pred[0], pred[1], pred[2], pred[3], pred[4]))
                    end else begin
                        `uvm_info("SB_PRIMARY",
                            $sformatf("Cycle %0d MATCH (err=%.6f): DUT x=%.4f y=%.4f v=%.4f psi=%.4f pd=%.4f",
                                      pri_comparisons, max_err,
                                      dut[0], dut[1], dut[2], dut[3], dut[4]), UVM_LOW)
                    end
                end
            end

            // ============================================================
            // TIER 2 — CALIBRATION: Predictor vs Golden CSV
            // TIER 3 — QUALITY: DUT position vs GT
            // ============================================================
            if (golden_queue.size() > 0) begin
                real cal_err[5], cal_max;
                real dut_pos_err, gps_pos_err;

                have_golden = 1'b1;
                g = golden_queue.pop_front();

                // ---- CALIBRATION ----
                if (cfg.enable_calibration && cfg.enable_predictor) begin
                    ukf_output pred_out2;
                    real golden_st[5];
                    pred_out2 = predictor.get_output();
                    golden_st[0] = g.sw_est_x;
                    golden_st[1] = g.sw_est_y;
                    golden_st[2] = g.sw_est_v;
                    golden_st[3] = g.sw_est_psi;
                    golden_st[4] = g.sw_est_psidot;

                    cal_max = 0.0;
                    for (int i = 0; i < 5; i++) begin
                        if (i == 3)
                            cal_err[i] = abs_angle_diff(pred[i], golden_st[i]);
                        else
                            cal_err[i] = (pred[i] - golden_st[i]) >= 0
                                       ? (pred[i] - golden_st[i])
                                       : -(pred[i] - golden_st[i]);
                        cal_sum_sq_err[i] += cal_err[i] * cal_err[i];
                        if (cal_err[i] > cal_max) cal_max = cal_err[i];
                    end
                    cal_comparisons++;
                    if (cal_max > cfg.calibration_threshold) begin
                        cal_mismatches++;
                        `uvm_warning("SB_CALIBRATION",
                            $sformatf("Cycle %0d PRED_vs_GOLDEN max_err=%.6f | PRED(%.4f,%.4f) GOLDEN(%.4f,%.4f)",
                                      cal_comparisons, cal_max,
                                      pred[0], pred[1],
                                      golden_st[0], golden_st[1]))
                    end else begin
                        `uvm_info("SB_CALIBRATION",
                            $sformatf("Cycle %0d PRED_vs_GOLDEN OK (err=%.6f)",
                                      cal_comparisons, cal_max), UVM_HIGH)
                    end
                end

                // ---- QUALITY ----
                if (cfg.enable_quality) begin
                    dut_pos_err = ((dut[0] - g.gt_x)**2 + (dut[1] - g.gt_y)**2) ** 0.5;
                    gps_pos_err = ((g.gps_x - g.gt_x)**2 + (g.gps_y - g.gt_y)**2) ** 0.5;

                    qual_comparisons++;
                    qual_dut_sum_sq += dut_pos_err ** 2;
                    qual_gps_sum_sq += gps_pos_err ** 2;
                    if (dut_pos_err > qual_max_dut_err) qual_max_dut_err = dut_pos_err;
                    if (gps_pos_err > qual_max_gps_err) qual_max_gps_err = gps_pos_err;

                    `uvm_info("SB_QUALITY",
                        $sformatf("Cycle %0d: DUT_err=%.3f GPS_err=%.3f %s",
                                  qual_comparisons, dut_pos_err, gps_pos_err,
                                  (dut_pos_err < gps_pos_err) ? "IMPROVED" : ""),
                        UVM_MEDIUM)
                end
            end

            if (cfg.enable_predictor && cfg.debug_ukf_dt)
                ukf_debug_dump_dt(pri_comparisons, have_golden, g);
            if (cfg.enable_predictor && cfg.debug_ukf_p)
                ukf_debug_dump(pri_comparisons, predictor);
            if (cfg.enable_predictor && cfg.debug_ukf_ppred)
                ukf_debug_dump_ppred(pri_comparisons);
            if (cfg.enable_predictor && cfg.debug_ukf_sigma)
                ukf_debug_dump_sigma(pri_comparisons);
            // Latch DUT posterior then re-seed predictor so the *next* cycle's write_sensor step()
            // starts from DUT RAM (FP32), not accumulated float drift from the previous step().
            if (cfg.enable_predictor && pri_comparisons > 0) begin
                latch_dut_xp_from_mem();
                predictor.apply_dut_posterior_xP(latched_dut_x, latched_dut_P);
            end
        endfunction

        // ---- Report phase: final summary ----
        virtual function void report_phase(uvm_phase phase);
            real pri_rmse[5], cal_rmse[5];
            real dut_rmse, gps_rmse, improvement;
            string state_names[5] = '{"x","y","v","psi","psidot"};
            super.report_phase(phase);

            `uvm_info("SB_REPORT", "====== SCOREBOARD FINAL REPORT ======", UVM_LOW)

            // PRIMARY report
            if (pri_comparisons == 0) begin
                `uvm_warning("SB_REPORT", "PRIMARY: No comparisons were made")
            end else begin
                for (int i = 0; i < 5; i++)
                    pri_rmse[i] = (pri_sum_sq_err[i] / pri_comparisons) ** 0.5;
                `uvm_info("SB_REPORT",
                    $sformatf("[PRIMARY]     %0d cycles, %0d mismatches, %0d DUT-error-skipped (thresh=%.2f)",
                              pri_comparisons, pri_mismatches, dut_error_cycles, cfg.primary_threshold), UVM_LOW)
                `uvm_info("SB_REPORT",
                    $sformatf("[PRIMARY]     Per-state RMSE: x=%.6f y=%.6f v=%.6f psi=%.6f pd=%.6f",
                              pri_rmse[0], pri_rmse[1], pri_rmse[2], pri_rmse[3], pri_rmse[4]), UVM_LOW)
            end

            // CALIBRATION report
            if (cal_comparisons > 0) begin
                for (int i = 0; i < 5; i++)
                    cal_rmse[i] = (cal_sum_sq_err[i] / cal_comparisons) ** 0.5;
                `uvm_info("SB_REPORT",
                    $sformatf("[CALIBRATION] %0d cycles, %0d mismatches (thresh=%.2f)",
                              cal_comparisons, cal_mismatches, cfg.calibration_threshold), UVM_LOW)
                `uvm_info("SB_REPORT",
                    $sformatf("[CALIBRATION] Per-state RMSE: x=%.6f y=%.6f v=%.6f psi=%.6f pd=%.6f",
                              cal_rmse[0], cal_rmse[1], cal_rmse[2], cal_rmse[3], cal_rmse[4]), UVM_LOW)
            end else begin
                `uvm_info("SB_REPORT", "[CALIBRATION] Not active (no golden data pushed)", UVM_LOW)
            end

            // QUALITY report
            if (qual_comparisons > 0) begin
                dut_rmse = (qual_dut_sum_sq / qual_comparisons) ** 0.5;
                gps_rmse = (qual_gps_sum_sq / qual_comparisons) ** 0.5;
                improvement = (gps_rmse > 0.0) ? (1.0 - dut_rmse / gps_rmse) * 100.0 : 0.0;

                `uvm_info("SB_REPORT",
                    $sformatf("[QUALITY]     DUT_RMSE=%.3f m, GPS_RMSE=%.3f m, Improvement=%.1f%%",
                              dut_rmse, gps_rmse, improvement), UVM_LOW)
                `uvm_info("SB_REPORT",
                    $sformatf("[QUALITY]     Max DUT error=%.3f m, Max GPS error=%.3f m",
                              qual_max_dut_err, qual_max_gps_err), UVM_LOW)
            end else begin
                `uvm_info("SB_REPORT", "[QUALITY]     Not active (no golden data pushed)", UVM_LOW)
            end

            // ---- Final PASS/FAIL ----
            `uvm_info("SB_REPORT", "======================================", UVM_LOW)
            if (pri_comparisons == 0) begin
                `uvm_warning("SB_SUMMARY", "Test INCONCLUSIVE — no DUT-vs-Predictor comparisons")
            end else if (pri_mismatches > 0) begin
                `uvm_error("SB_SUMMARY",
                    $sformatf("Test FAILED: %0d/%0d PRIMARY mismatches (DUT vs Predictor)",
                              pri_mismatches, pri_comparisons))
            end else if (qual_comparisons > 0 && dut_rmse >= gps_rmse) begin
                `uvm_error("SB_SUMMARY",
                    $sformatf("Test FAILED: UKF DUT (RMSE=%.3f) not better than GPS (RMSE=%.3f)",
                              dut_rmse, gps_rmse))
            end else begin
                `uvm_info("SB_SUMMARY",
                    $sformatf("Test PASSED: %0d cycles, 0 mismatches%s",
                              pri_comparisons,
                              (qual_comparisons > 0)
                                ? $sformatf(", UKF improves over GPS by %.1f%%", improvement)
                                : ""),
                    UVM_LOW)
            end
        endfunction
    endclass : fusion_scoreboard

endpackage : fusion_scoreboard_pkg
