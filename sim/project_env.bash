#!/bin/bash
# Project Environment Setup for Fusion IP UVM Verification
# Source this script before running Makefile: source ./project_env.bash

# =====================================================================
# UVM Library Setup
# =====================================================================

# Set UVM_HOME to your UVM installation directory
# Example paths:
#   - Questa: /opt/questasim/verilog_src/uvm-1.2
#   - System install: /usr/local/uvm-1.2
#   - Local copy: $(pwd)/../uvm_lib

export UVM_HOME=${UVM_HOME:-/opt/questasim/verilog_src/uvm-1.2}

# Verify UVM_HOME exists
if [ ! -f "$UVM_HOME/src/uvm.sv" ]; then
    echo "WARNING: UVM_HOME not found at $UVM_HOME/src/uvm.sv"
    echo "Please set UVM_HOME to correct path:"
    echo "  export UVM_HOME=/path/to/uvm-1.2"
    echo "  source ./project_env.bash"
fi

# =====================================================================
# Fusion IP Verification Paths
# =====================================================================

# Root of entire verification project (where this script is)
export FUSION_IP_VERIF_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Subdirectories of verification
export FUSION_IP_TB_PATH="${FUSION_IP_VERIF_PATH}/uvm/testbench"
export FUSION_IP_TESTS_PATH="${FUSION_IP_VERIF_PATH}/uvm/tests"
export FUSION_IP_ENV_PATH="${FUSION_IP_VERIF_PATH}/uvm/environment"
export FUSION_IP_AGENTS_PATH="${FUSION_IP_VERIF_PATH}/uvm/agents"
export FUSION_IP_BASE_PATH="${FUSION_IP_VERIF_PATH}/uvm/base"
export FUSION_IP_REF_PATH="${FUSION_IP_VERIF_PATH}/uvm/ref_model"

# RTL source path
export FUSION_IP_RTL_PATH="${FUSION_IP_VERIF_PATH}"

# =====================================================================
# Standard VIP Paths (if using separate VIP)
# =====================================================================

# If you have external VIP (e.g., AXI VIP, sensor simulator), set paths here
# export AXI_VIP_ROOT="${FUSION_IP_VERIF_PATH}/vip/axi_vip"
# export SENSOR_VIP_ROOT="${FUSION_IP_VERIF_PATH}/vip/sensor_vip"

# =====================================================================
# Tool Configuration
# =====================================================================

# Questa/ModelSim tool path (set if not in standard PATH)
# export PATH="/opt/questasim/bin:$PATH"

# VHDL/Verilog standard
export VERILOG_STANDARD="sv2017"

# Questa library name
export QUESTA_LIB="work"

# =====================================================================
# Simulation Defaults
# =====================================================================

# Default simulator behavior
export SIMULATOR="questa"
export TESTCASE="fusion_sanity_test"
export SEED="1"
export VERBOSITY="UVM_MEDIUM"
export DUMP_WAVES="0"

# =====================================================================
# Print Environment Summary
# =====================================================================

echo "=============================================="
echo "Fusion IP UVM Verification Environment"
echo "=============================================="
echo "UVM Home:               $UVM_HOME"
echo "Fusion IP Verif Path:   $FUSION_IP_VERIF_PATH"
echo "RTL Path:               $FUSION_IP_RTL_PATH"
echo "Testbench Path:         $FUSION_IP_TB_PATH"
echo "Tests Path:             $FUSION_IP_TESTS_PATH"
echo "Environment Path:       $FUSION_IP_ENV_PATH"
echo ""
echo "Simulator:              $SIMULATOR"
echo "Default Test:           $TESTCASE"
echo "Default Seed:           $SEED"
echo "Verbosity:              $VERBOSITY"
echo "=============================================="
echo ""

# =====================================================================
# Verify Tools in PATH
# =====================================================================

if ! command -v vlog &> /dev/null; then
    echo "WARNING: 'vlog' not found in PATH"
    echo "Ensure Questa/ModelSim is installed and in PATH"
fi

if ! command -v vsim &> /dev/null; then
    echo "WARNING: 'vsim' not found in PATH"
    echo "Ensure Questa/ModelSim is installed and in PATH"
fi

if ! command -v perl &> /dev/null; then
    echo "WARNING: 'perl' not found in PATH"
    echo "Regression script requires Perl"
fi

# =====================================================================
# Local Functions (optional)
# =====================================================================

# Function to quickly clean build
clean_build() {
    echo "Cleaning build artifacts..."
    rm -rf work *.wlf *.log *.ucdb *.shm
}

# Function to setup fresh workspace
fresh_setup() {
    echo "Setting up fresh workspace..."
    clean_build
    mkdir -p build sim_log
}

export -f clean_build fresh_setup

echo "Environment setup complete!"
echo ""
echo "To use: cd sim && make [target]"
echo "For help: make help"
echo ""

