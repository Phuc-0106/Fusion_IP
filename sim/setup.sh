#!/bin/bash
# Initial Setup Script for Fusion IP UVM Build Environment

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "=========================================="
echo "Fusion IP UVM Verification - Setup"
echo "=========================================="
echo ""

# Check for required tools
echo "[CHECK] Verifying required tools..."

for tool in perl make vlog vsim; do
    if command -v $tool &> /dev/null; then
        VERSION=$($tool --version 2>&1 | head -1)
        echo "  ✓ $tool found"
    else
        echo "  ✗ $tool not found - please install or add to PATH"
    fi
done

echo ""

# Detect UVM_HOME
echo "[DETECT] Searching for UVM library..."

UVM_CANDIDATES=(
    "/opt/questasim/verilog_src/uvm-1.2"
    "/opt/questasim_10.8b/verilog_src/uvm-1.2"
    "/opt/questasim_10.8/verilog_src/uvm-1.2"
    "/usr/local/uvm-1.2"
    "$HOME/tools/uvm-1.2"
)

UVM_HOME=""
for candidate in "${UVM_CANDIDATES[@]}"; do
    if [ -f "$candidate/src/uvm.sv" ]; then
        UVM_HOME=$candidate
        echo "  Found UVM at: $UVM_HOME"
        break
    fi
done

if [ -z "$UVM_HOME" ]; then
    echo "  WARNING: UVM not found in standard locations"
    echo "  Please set UVM_HOME manually in project_env.bash"
    UVM_HOME="/path/to/uvm-1.2"
else
    # Update project_env.bash
    sed -i "s|export UVM_HOME=.*|export UVM_HOME=$UVM_HOME|" project_env.bash
    echo "  Updated project_env.bash"
fi

echo ""

# Create directories
echo "[CREATE] Creating required directories..."

for dir in log waves coverage build; do
    if [ ! -d "$dir" ]; then
        mkdir -p "$dir"
        echo "  Created $dir/"
    fi
done

echo ""

# Make scripts executable
echo "[CHMOD] Making scripts executable..."

for script in run.sh clean.sh setup.sh regress.pl; do
    if [ -f "$script" ]; then
        chmod +x "$script"
        echo "  chmod +x $script"
    fi
done

echo ""

# Summary
echo "=========================================="
echo "Setup Summary"
echo "=========================================="
echo "Project directory:  $SCRIPT_DIR"
echo "UVM home:           $UVM_HOME"
echo ""

# Check if ready to go
if [ -d "$UVM_HOME" ]; then
    echo "✓ Ready to use!"
    echo ""
    echo "Next steps:"
    echo "  1. source ./project_env.bash"
    echo "  2. make test-sanity"
    echo ""
else
    echo "⚠ NOT READY - UVM_HOME not found"
    echo ""
    echo "Next steps:"
    echo "  1. Edit project_env.bash and set UVM_HOME"
    echo "  2. source ./project_env.bash"
    echo "  3. make test-sanity"
    echo ""
fi

