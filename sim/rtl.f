// RTL File List for Fusion IP
// Contains all RTL sources for the DUT (Device Under Test)

// Parameter definitions (must be first)
${FUSION_IP_RTL_PATH}/params.vh

// Core RTL modules (in dependency order)  [FP32 only — cordic.sv removed]
${FUSION_IP_RTL_PATH}/cordic_fp32.sv
${FUSION_IP_RTL_PATH}/sync_fifo.sv

${FUSION_IP_RTL_PATH}/state_mem_reg.sv
${FUSION_IP_RTL_PATH}/pe_mul.sv
${FUSION_IP_RTL_PATH}/ukf_fp_add_reduce_tree.sv
${FUSION_IP_RTL_PATH}/sensor_input_block.sv
${FUSION_IP_RTL_PATH}/sigma_point_generator.sv
${FUSION_IP_RTL_PATH}/predict_block.sv
${FUSION_IP_RTL_PATH}/update_block.sv

// Top-level controllers
${FUSION_IP_RTL_PATH}/ukf_controller.sv

// DUT Top Module (must be last)
${FUSION_IP_RTL_PATH}/fusion_ip_top.sv

