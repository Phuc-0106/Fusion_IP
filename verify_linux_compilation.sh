#!/bin/bash
# =====================================================================
# Fusion IP Linux Compilation Verification Script
# =====================================================================
# Usage: bash verify_linux_compilation.sh
# =====================================================================

set -e

echo "=========================================="
echo "Fusion IP - Linux Compilation Verification"
echo "=========================================="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Counter
PASS=0
FAIL=0

# =====================================================================
# Helper Functions
# =====================================================================

check_file() {
    if [ -f "$1" ]; then
        echo -e "${GREEN}✓${NC} Found: $1"
        ((PASS++))
    else
        echo -e "${RED}✗${NC} Missing: $1"
        ((FAIL++))
    fi
}

check_dir() {
    if [ -d "$1" ]; then
        echo -e "${GREEN}✓${NC} Directory: $1"
        ((PASS++))
    else
        echo -e "${RED}✗${NC} Missing dir: $1"
        ((FAIL++))
    fi
}

check_tool() {
    if command -v "$1" &> /dev/null; then
        echo -e "${GREEN}✓${NC} Found tool: $1"
        ((PASS++))
    else
        echo -e "${RED}✗${NC} Tool not found: $1"
        ((FAIL++))
    fi
}

# =====================================================================
# 1. Environment Check
# =====================================================================
echo "1. Checking Environment Setup..."
check_tool "vlog"
check_tool "vsim"
check_tool "python3"

echo ""

# =====================================================================
# 2. Directory Structure Check
# =====================================================================
echo "2. Checking Directory Structure..."
check_dir "rtl"
check_dir "tb"
check_dir "sim"
check_dir "sequences"
check_dir "agents"
check_dir "testcases"
check_dir "scripts"
check_dir "docs"

echo ""

# =====================================================================
# 3. Essential Files Check
# =====================================================================
echo "3. Checking Essential Files..."

# RTL files
check_file "rtl/params.vh"
check_file "rtl/fusion_ip_top.sv"
check_file "rtl/compile.f"

# TB files
check_file "tb/tb_fusion_ip.sv"
check_file "tb/fusion_env.sv"
check_file "tb/compile.f"

# Sim files
check_file "sim/compile.f"
check_file "sim/Makefile"
check_file "sim/project_env.bash"

# Scripts
check_file "scripts/csv_processor.py"
check_file "scripts/requirements.txt"

echo ""

# =====================================================================
# 4. Compile File Content Check
# =====================================================================
echo "4. Checking compile.f Files..."

echo "   Checking sim/compile.f..."
if grep -q "+incdir+../rtl" sim/compile.f; then
    echo -e "${GREEN}✓${NC} sim/compile.f has RTL incdir"
    ((PASS++))
else
    echo -e "${RED}✗${NC} sim/compile.f missing RTL incdir"
    ((FAIL++))
fi

if grep -q "\.\./rtl/params\.vh" sim/compile.f; then
    echo -e "${GREEN}✓${NC} sim/compile.f includes params.vh"
    ((PASS++))
else
    echo -e "${RED}✗${NC} sim/compile.f missing params.vh"
    ((FAIL++))
fi

echo ""
echo "   Checking rtl/compile.f..."
if grep -q "params\.vh" rtl/compile.f; then
    echo -e "${GREEN}✓${NC} rtl/compile.f includes params.vh"
    ((PASS++))
else
    echo -e "${RED}✗${NC} rtl/compile.f missing params.vh"
    ((FAIL++))
fi

echo ""
echo "   Checking tb/compile.f..."
if grep -q "tb_fusion_ip\.sv" tb/compile.f; then
    echo -e "${GREEN}✓${NC} tb/compile.f includes tb_fusion_ip.sv"
    ((PASS++))
else
    echo -e "${RED}✗${NC} tb/compile.f missing tb_fusion_ip.sv"
    ((FAIL++))
fi

echo ""

# =====================================================================
# 5. Path Format Check (Linux compatibility)
# =====================================================================
echo "5. Checking Linux Path Compatibility..."

# Check for Windows-style paths
WINDOWS_PATHS=$(grep -r '\\' sim/compile.f tb/compile.f rtl/compile.f 2>/dev/null | wc -l || echo "0")

if [ "$WINDOWS_PATHS" -eq 0 ]; then
    echo -e "${GREEN}✓${NC} No Windows-style backslashes found"
    ((PASS++))
else
    echo -e "${RED}✗${NC} Found $WINDOWS_PATHS Windows-style paths"
    ((FAIL++))
fi

# Check for forward slashes
FORWARD_SLASHES=$(grep -c "\.\./rtl" sim/compile.f)
if [ "$FORWARD_SLASHES" -gt 0 ]; then
    echo -e "${GREEN}✓${NC} Found forward slashes in paths"
    ((PASS++))
else
    echo -e "${RED}✗${NC} No forward slashes found"
    ((FAIL++))
fi

echo ""

# =====================================================================
# 6. Optional: Compilation Test (if willing to wait)
# =====================================================================
echo "6. Compilation Test (Optional - Press Y to run ~30sec test):"
read -p "   Run compilation test? [y/N]: " -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "   Starting compilation (this may take 30-60 seconds)..."
    cd sim
    
    # Clean
    make clean > /dev/null 2>&1 || true
    
    # Try to build
    if make build > /tmp/fusion_build.log 2>&1; then
        echo -e "${GREEN}✓${NC} Compilation succeeded"
        ((PASS++))
        
        # Check for work directory
        if [ -d "work" ]; then
            echo -e "${GREEN}✓${NC} Work directory created"
            ((PASS++))
            
            # Count compiled objects
            OBJ_COUNT=$(ls work/ | wc -l)
            echo -e "${GREEN}✓${NC} Created $OBJ_COUNT compiled objects"
            ((PASS++))
        else
            echo -e "${RED}✗${NC} Work directory not found"
            ((FAIL++))
        fi
    else
        echo -e "${RED}✗${NC} Compilation failed"
        ((FAIL++))
        echo "      Error log:"
        tail -20 /tmp/fusion_build.log | sed 's/^/      /'
    fi
    
    cd - > /dev/null
else
    echo "   Skipping compilation test"
fi

echo ""

# =====================================================================
# Final Report
# =====================================================================
echo "=========================================="
echo "Verification Report"
echo "=========================================="
echo -e "Passed: ${GREEN}$PASS${NC}"
echo -e "Failed: ${RED}$FAIL${NC}"
echo "=========================================="

if [ $FAIL -eq 0 ]; then
    echo -e "${GREEN}✓ All checks passed! Ready for Linux compilation.${NC}"
    exit 0
else
    echo -e "${RED}✗ Some checks failed. See above for details.${NC}"
    exit 1
fi
