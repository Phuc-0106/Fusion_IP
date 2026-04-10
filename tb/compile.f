// =====================================================================
// Testbench Compilation Filelist - Fusion IP UVM
// =====================================================================
// Usage: vlog -sv -f compile.f
// Run from: tb/ directory (or reference with ../tb/compile.f)
// Purpose: Testbench and UVM environment compilation
// =====================================================================

+incdir+.
+incdir+../tb
+incdir+../rtl
+incdir+../sequences
+incdir+../agents
+incdir+../

// =====================================================================
// UVM Package Definitions (MUST compile before environment/testbench)
// =====================================================================
// Order matters: base packages first, then dependent packages
fusion_vif.sv
fusion_pkg.sv
fusion_ral_pkg.sv
fusion_axi_pkg.sv
fusion_sensor_pkg.sv
ukf_predictor.sv
fusion_scoreboard.sv

// =====================================================================
// UVM Environment Components
// =====================================================================
// Environment class (instantiates agents, scoreboards, config)
fusion_env.sv

// Base test class (must be after fusion_env_pkg)
fusion_base_test.sv

// Concrete UVM tests
../testcases/fusion_tests.sv

// =====================================================================
// Top-Level Testbench Module
// =====================================================================
tb_fusion_ip.sv

// =====================================================================
// Supporting UVM Classes (already included in packages)
// =====================================================================
// - fusion_scoreboard.sv (package fusion_scoreboard_pkg)
// - fusion_coverage_model.sv → future enhancement
// - fusion_ref_model.sv → in fusion_predictor_pkg.sv
// - fusion_predictor.sv → in fusion_predictor_pkg.sv

// =====================================================================
// Note: Test cases are selected at runtime via +UVM_TESTNAME
// No need to compile them here - they are included dynamically
// =====================================================================

