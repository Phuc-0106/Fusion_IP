// =====================================================================
// Fusion IP - Master Compilation Filelist
// =====================================================================
// Usage: vlog -sv +define+SIMULATION -f compile.f
// Run from: sim/ directory
// Platform: Linux/Unix
// =====================================================================

// =====================================================================
// Include Directory Paths
// =====================================================================
+incdir+../rtl
+incdir+../tb
+incdir+../sequences
+incdir+../agents
+incdir+../regmodel
+incdir+../

// =====================================================================
// RTL Design Files (Device Under Test)
// =====================================================================
// Include parameters first (used by all modules)
../rtl/params.vh

// Core CORDIC and Math (FP32 only — cordic.sv removed)
../rtl/cordic_fp32.sv

// Dataflow elements
../rtl/sync_fifo.sv
../rtl/state_mem_reg.sv

// Computational blocks
../rtl/pe_mul.sv
../rtl/ukf_fp_add_reduce_tree.sv
../rtl/ukf_fp_engine.sv
../rtl/ukf_fmac_pe.sv
../rtl/sigma_point_generator.sv

// Filter stages
../rtl/predict_block.sv
../rtl/update_block.sv

// I/O and control
../rtl/sensor_input_block.sv
../rtl/ukf_controller.sv

// Top-level wrapper (DUT)
../rtl/fusion_ip_top.sv

// =====================================================================
// UVM Package Definitions (MUST compile before environment/testbench)
// =====================================================================
// Order matters: base packages first, then dependent packages
../tb/fusion_vif.sv
../tb/fusion_pkg.sv
../tb/fusion_ral_pkg.sv
../tb/fusion_axi_pkg.sv
../tb/fusion_sensor_pkg.sv
../tb/ukf_predictor.sv
../tb/ukf_mem_backdoor.sv
../tb/fusion_scoreboard.sv

// =====================================================================
// UVM Testbench Files
// =====================================================================

// UVM Environment (agents, scoreboard, configuration)
../tb/fusion_env.sv

// Base test class (must be after fusion_env_pkg)
../tb/fusion_base_test.sv

// Concrete UVM tests (fusion_csv_route_test, etc.)
../testcases/fusion_tests.sv

// Top-level testbench instantiation
../tb/tb_fusion_ip.sv

// =====================================================================
// Test Cases (loaded dynamically via factory)
// =====================================================================
// Test cases are NOT listed here - they are dynamically selected by +UVM_TESTNAME
// Actual test files:
// ../testcases/fusion_sanity_test.sv
// ../testcases/fusion_multi_cycle_test.sv
// ../testcases/fusion_csv_route_test.sv
// etc.
//
// To include specific tests, uncomment below:
// ../testcases/fusion_sanity_test.sv
// ../testcases/fusion_multi_cycle_test.sv
// ../testcases/fusion_missing_gps_test.sv
// ../testcases/fusion_irq_status_test.sv
// ../testcases/fusion_soft_reset_test.sv
// ../testcases/fusion_ral_bit_bash_test.sv
// ../testcases/fusion_scoreboard_ref_test.sv
// ../testcases/fusion_csv_route_test.sv

// =====================================================================
// Verification Components (Agents, Sequences)
// =====================================================================
// These are instantiated via UVM factory in fusion_env
// Explicit includes for compilation if needed:
// ../agents/sensor_agent/*.sv
// ../agents/axi_agent/*.sv
// ../sequences/*.sv

// =====================================================================
// Notes
// =====================================================================
// - All paths are relative to sim/ directory
// - Use forward slashes for portability (Linux/Unix/Windows)
// - HDL include files (.vh) found via +incdir+ paths
// - Tests selected at runtime via +UVM_TESTNAME=<test_class>
// - Define SIMULATION for testbench-specific code
// =====================================================================


