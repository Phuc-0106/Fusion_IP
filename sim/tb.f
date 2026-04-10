// Testbench File List for Fusion IP UVM Verification
// Include paths, UVM library, VIP, and TB sources

// =====================================================================
// Standard Includes and Paths
// =====================================================================

// Timescale definition
-timescale 1ns/1ps

// Include directories for synthesis/include files
+incdir+${UVM_HOME}/src
+incdir+${FUSION_IP_BASE_PATH}
+incdir+${FUSION_IP_AGENTS_PATH}/axi
+incdir+${FUSION_IP_AGENTS_PATH}/sensor
+incdir+${FUSION_IP_ENV_PATH}
+incdir+${FUSION_IP_TESTS_PATH}
+incdir+${FUSION_IP_REF_PATH}

// =====================================================================
// UVM Library (required first)
// =====================================================================

${UVM_HOME}/src/uvm.sv

// =====================================================================
// Fusion IP UVM Packages (in dependency order)
// =====================================================================

// 1. Base packages (no dependencies on others)
${FUSION_IP_BASE_PATH}/fusion_vif.sv
${FUSION_IP_BASE_PATH}/fusion_pkg.sv
${FUSION_IP_BASE_PATH}/fusion_ral.sv

// 2. Agents (depend on fusion_pkg)
${FUSION_IP_AGENTS_PATH}/axi/axi_agent.sv
${FUSION_IP_AGENTS_PATH}/sensor/sensor_agent.sv

// 3. Reference Model
${FUSION_IP_REF_PATH}/ukf_predictor.sv

// 4. Scoreboards and Environment (depend on agents + predictor)
${FUSION_IP_ENV_PATH}/fusion_scoreboard.sv
${FUSION_IP_ENV_PATH}/fusion_env.sv

// 5. Test Cases (depend on environment)
${FUSION_IP_TESTS_PATH}/fusion_tests.sv

// =====================================================================
// Testbench Module (must be last)
// =====================================================================

${FUSION_IP_VERIF_PATH}/uvm/fusion_tb_top.sv

