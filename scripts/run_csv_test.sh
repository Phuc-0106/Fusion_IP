#!/bin/bash
#
# Fusion IP CSV Route Test - Automated Workflow Script
#
# This script automates the complete pipeline:
# 1. Generate example CSV data
# 2. Process with csv_processor.py
# 3. Run test in simulation
#
# Usage:
#   bash run_csv_test.sh                          # Use defaults
#   bash run_csv_test.sh --gps gps.csv --imu imu.csv --odom odom.csv
#   bash run_csv_test.sh --hz 50 --output custom_fused.csv

set -e  # Exit on error

# ============================================================================
# Configuration
# ============================================================================

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
ROOT_DIR="$( cd "$SCRIPT_DIR/.." && pwd )"
SIM_DIR="$ROOT_DIR/sim"

# Defaults
GPS_FILE="${SCRIPT_DIR}/example_data/gps_scenario_1.csv"
IMU_FILE="${SCRIPT_DIR}/example_data/imu_scenario_1.csv"
ODOM_FILE="${SCRIPT_DIR}/example_data/odom_scenario_1.csv"
OUTPUT_CSV="${SCRIPT_DIR}/fused_timeline.csv"
OUTPUT_HEX="${SCRIPT_DIR}/fused_timeline.hex"
BASE_HZ=25
REF_LAT=0.0
REF_LON=0.0
ENABLE_TEST=1
VERBOSE=0

# ============================================================================
# Functions
# ============================================================================

print_usage() {
    cat << EOF
Usage: bash run_csv_test.sh [OPTIONS]

Automated CSV route test pipeline for Fusion IP UVM verification.

Options:
    --gps FILE          GPS CSV file (default: example_data/gps_scenario_1.csv)
    --imu FILE          IMU CSV file (default: example_data/imu_scenario_1.csv)
    --odom FILE         Odometry CSV file (default: example_data/odom_scenario_1.csv)
    
    --output FILE       Output CSV filename (default: fused_timeline.csv)
    --hex FILE          Output HEX filename (default: fused_timeline.hex)
    
    --hz FREQ           Output frequency in Hz (default: 25)
    --ref-lat LAT       Reference latitude for coordinate conversion (default: 0.0)
    --ref-lon LON       Reference longitude for coordinate conversion (default: 0.0)
    
    --no-test           Skip simulation test (only process CSV)
    --generate-only     Generate example data only, then exit
    
    -v, --verbose       Verbose output
    -h, --help          Show this help message

Examples:
    # Default: generate example data, process, and run test
    bash run_csv_test.sh
    
    # Use your own CSV files
    bash run_csv_test.sh --gps my_gps.csv --imu my_imu.csv --odom my_odom.csv
    
    # Only process, don't run test
    bash run_csv_test.sh --no-test
    
    # Different output frequency
    bash run_csv_test.sh --hz 50

EOF
}

log_info() {
    local msg="$1"
    echo -e "\033[1;32m[INFO]\033[0m $msg"
}

log_warn() {
    local msg="$1"
    echo -e "\033[1;33m[WARN]\033[0m $msg"
}

log_error() {
    local msg="$1"
    echo -e "\033[1;31m[ERROR]\033[0m $msg"
}

log_step() {
    local step="$1"
    echo ""
    echo "============================================================================"
    echo "  $step"
    echo "============================================================================"
}

# ============================================================================
# Parse Arguments
# ============================================================================

while [[ $# -gt 0 ]]; do
    case $1 in
        --gps)
            GPS_FILE="$2"
            shift 2
            ;;
        --imu)
            IMU_FILE="$2"
            shift 2
            ;;
        --odom)
            ODOM_FILE="$2"
            shift 2
            ;;
        --output)
            OUTPUT_CSV="$2"
            shift 2
            ;;
        --hex)
            OUTPUT_HEX="$2"
            shift 2
            ;;
        --hz)
            BASE_HZ="$2"
            shift 2
            ;;
        --ref-lat)
            REF_LAT="$2"
            shift 2
            ;;
        --ref-lon)
            REF_LON="$2"
            shift 2
            ;;
        --no-test)
            ENABLE_TEST=0
            shift
            ;;
        --generate-only)
            GENERATE_ONLY=1
            shift
            ;;
        -v|--verbose)
            VERBOSE=1
            shift
            ;;
        -h|--help)
            print_usage
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            print_usage
            exit 1
            ;;
    esac
done

# ============================================================================
# Step 1: Generate Example Data (if not present)
# ============================================================================

log_step "Step 1: Generate Example Data"

if [ ! -f "$GPS_FILE" ] || [ ! -f "$IMU_FILE" ] || [ ! -f "$ODOM_FILE" ]; then
    log_info "Example data not found, generating..."
    
    if ! python3 "${SCRIPT_DIR}/generate_example_csv.py"; then
        log_error "Failed to generate example data"
        exit 1
    fi
    
    log_info "✓ Example data generated"
else
    log_info "Example data already exists:"
    log_info "  GPS:  $GPS_FILE"
    log_info "  IMU:  $IMU_FILE"
    log_info "  Odom: $ODOM_FILE"
fi

if [ "$GENERATE_ONLY" == "1" ]; then
    log_info "✓ Data generation complete (--generate-only)"
    exit 0
fi

# ============================================================================
# Step 2: Process CSV Files
# ============================================================================

log_step "Step 2: Process CSV Files"

log_info "Running csv_processor.py..."

CMD="python3 \"${SCRIPT_DIR}/csv_processor.py\" \
    --gps \"$GPS_FILE\" \
    --imu \"$IMU_FILE\" \
    --odom \"$ODOM_FILE\" \
    --output \"$OUTPUT_CSV\" \
    --hex \"$OUTPUT_HEX\" \
    --hz $BASE_HZ \
    --ref-lat $REF_LAT \
    --ref-lon $REF_LON"

if [ "$VERBOSE" == "1" ]; then
    log_info "Command: $CMD"
fi

if ! eval "$CMD"; then
    log_error "CSV processing failed"
    exit 1
fi

log_info "✓ CSV processing complete"
log_info "  Output CSV: $OUTPUT_CSV"
log_info "  Output HEX: $OUTPUT_HEX"

# Display file stats
if [ -f "$OUTPUT_CSV" ]; then
    LINES=$(wc -l < "$OUTPUT_CSV")
    SIZE=$(ls -lh "$OUTPUT_CSV" | awk '{print $5}')
    log_info "  CSV stats: $LINES lines, $SIZE"
fi

# ============================================================================
# Step 3: Run Simulation Test (Optional)
# ============================================================================

if [ "$ENABLE_TEST" == "1" ]; then
    
    log_step "Step 3: Run Simulation Test"
    
    log_info "Checking simulation environment..."
    
    if [ ! -d "$SIM_DIR" ]; then
        log_error "Simulation directory not found: $SIM_DIR"
        exit 1
    fi
    
    if [ ! -f "$SIM_DIR/Makefile" ]; then
        log_error "Makefile not found in sim directory"
        exit 1
    fi
    
    # Check if environment is set up
    if [ ! -f "$SIM_DIR/project_env.bash" ]; then
        log_error "project_env.bash not found - first run setup.sh in sim directory"
        exit 1
    fi
    
    log_info "Setting up environment..."
    cd "$SIM_DIR"
    source ./project_env.bash
    
    # Verify tools
    if ! command -v vlog &> /dev/null; then
        log_error "Questa/ModelSim not found in PATH"
        log_info "Run: source $SIM_DIR/project_env.bash"
        exit 1
    fi
    
    log_info "Building project..."
    
    # Check if already built
    if [ ! -d work ] || [ ! -f work/_info ]; then
        if ! make build > /tmp/csv_test_build.log 2>&1; then
            log_error "Build failed (see /tmp/csv_test_build.log)"
            cat /tmp/csv_test_build.log
            exit 1
        fi
    fi
    
    log_info "Running CSV route test..."
    
    # Get absolute path for CSV file
    ABS_CSV_FILE=$(cd "$(dirname "$OUTPUT_CSV")" && pwd)/$(basename "$OUTPUT_CSV")
    
    if ! make run TESTNAME=fusion_csv_route_test CSV_FILE="$ABS_CSV_FILE" CSV_HZ="$BASE_HZ" \
            > /tmp/csv_test_run.log 2>&1; then
        log_error "Test failed (see /tmp/csv_test_run.log)"
        tail -50 /tmp/csv_test_run.log
        exit 1
    fi
    
    log_info "✓ Test execution complete"
    
    # Show results
    if [ -f log/run.log ]; then
        log_info ""
        log_info "Test Results:"
        tail -20 log/run.log
    fi
    
else
    log_info "Skipping simulation (--no-test)"
fi

# ============================================================================
# Summary
# ============================================================================

log_step "Summary"

echo ""
log_info "✓ CSV Route Test Pipeline Complete!"
echo ""
echo "Generated files:"
echo "  CSV:  $OUTPUT_CSV"
echo "  HEX:  $OUTPUT_HEX"
echo ""

if [ "$ENABLE_TEST" == "1" ]; then
    echo "Test results:"
    echo "  See: $SIM_DIR/log/run.log"
    echo "  Or:  $SIM_DIR/regress.rpt (if using regression)"
fi

echo ""
echo "Next steps:"
if [ "$ENABLE_TEST" == "0" ]; then
    echo "  1. Run simulation:"
    echo "     cd $SIM_DIR"
    echo "     source ./project_env.bash"
    echo "     make test-csv CSV_FILE=$ABS_CSV_FILE"
fi
echo "  2. Modify CSV files for different scenarios"
echo "  3. Include in regression: perl regress.pl"
echo ""

exit 0
