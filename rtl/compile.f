// =====================================================================
// RTL Compilation Filelist - Fusion IP Design
// =====================================================================
// Usage: vlog -sv -f compile.f
// Run from: rtl/ directory (or reference with ../rtl/compile.f)
// Purpose: Standalone RTL compilation
// =====================================================================

+incdir+.
+incdir+../

// Include files (parameters, macros, type definitions)
params.vh

// Core CORDIC (use cordic_fp32.sv for current FP32 flow; cordic.sv if present)
cordic_fp32.sv

// Memory and FIFO elements
sync_fifo.sv
state_mem_reg.sv

// Matrix and algorithm computation
sigma_point_generator.sv

// Filter blocks (prediction and update)
predict_block.sv
update_block.sv

// I/O and sensor signal conditioning
sensor_input_block.sv

// State machine and top-level controller
ukf_controller.sv

// Top-level design wrapper (DUT)
fusion_ip_top.sv

// =====================================================================
// End of RTL Filelist
// =====================================================================

