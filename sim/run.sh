#!/bin/bash
# Quick Test Runner for Fusion IP UVM Testbench

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Source environment
if [ -f ./project_env.bash ]; then
    source ./project_env.bash
else
    echo "ERROR: project_env.bash not found"
    exit 1
fi

# Default values
TEST="fusion_sanity_test"
SEED="1"
VERBOSE="UVM_MEDIUM"
WAVES=0
HELP=0

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -t|--test)
            TEST="$2"
            shift 2
            ;;
        --seed)
            SEED="$2"
            shift 2
            ;;
        -v|--verbosity)
            VERBOSE="$2"
            shift 2
            ;;
        -w|--waves)
            WAVES=1
            shift
            ;;
        -h|--help)
            HELP=1
            shift
            ;;
        *)
            TEST="$1"
            shift
            ;;
    esac
done

if [ $HELP -eq 1 ]; then
    echo "Fusion IP UVM Quick Test Runner"
    echo ""
    echo "Usage: ./run.sh [test] [options]"
    echo ""
    echo "Tests (shortcuts):"
    echo "  sanity       T1 - Sanity test"
    echo "  multi        T2 - Multi-cycle"
    echo "  missing-gps  T3 - Missing GPS"
    echo "  irq          T4 - Interrupt"
    echo "  reset        T5 - Soft reset"
    echo "  ral          T6 - RAL bit bash"
    echo "  sb           T7 - Scoreboard ref"
    echo "  csv          T8 - CSV route"
    echo ""
    echo "Options:"
    echo "  --seed N             Random seed [default: 1]"
    echo "  -v, --verbosity LVL  UVM_HIGH | UVM_MEDIUM | UVM_LOW"
    echo "  -w, --waves          Enable waveform dump"
    echo "  -h, --help           Show this help"
    echo ""
    echo "Examples:"
    echo "  ./run.sh sanity"
    echo "  ./run.sh multi --seed 42 -w"
    echo "  ./run.sh -t fusion_multi_cycle_test -v UVM_HIGH"
    exit 0
fi

# Map shortcuts
case $TEST in
    sanity)
        TEST="fusion_sanity_test"
        ;;
    multi)
        TEST="fusion_multi_cycle_test"
        ;;
    missing-gps)
        TEST="fusion_missing_gps_test"
        ;;
    irq)
        TEST="fusion_irq_status_test"
        ;;
    reset)
        TEST="fusion_soft_reset_test"
        ;;
    ral)
        TEST="fusion_ral_bit_bash_test"
        ;;
    sb)
        TEST="fusion_scoreboard_ref_test"
        ;;
    csv)
        TEST="fusion_csv_route_test"
        ;;
esac

# Build make command
MAKE_CMD="make run TESTNAME=$TEST SEED=$SEED VERBOSITY=$VERBOSE"

if [ $WAVES -eq 1 ]; then
    MAKE_CMD="$MAKE_CMD DUMP_WAVES=1"
fi

# Print info
echo "=========================================="
echo "Fusion IP UVM Test Runner"
echo "=========================================="
echo "Test:       $TEST"
echo "Seed:       $SEED"
echo "Verbosity:  $VERBOSE"
echo "Waves:      $([ $WAVES -eq 1 ] && echo 'YES' || echo 'NO')"
echo "=========================================="
echo ""

# Run test
eval $MAKE_CMD

