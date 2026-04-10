# Fusion IP Regression Testing Guide

Complete guide to running, analyzing, and managing regression tests for Fusion IP verification.

## What is Regression Testing?

**Definition:** Running all tests together to ensure that changes to the RTL or testbench don't break existing functionality.

**Why Important:**
- Catches unintended side effects of changes
- Maintains code quality
- Documents expected behavior
- Provides confidence before release

---

## Table of Contents

1. [Quick Start](#quick-start)
2. [Configuration](#configuration)
3. [Running Regression](#running-regression)
4. [Analyzing Results](#analyzing-results)
5. [Continuous Integration](#continuous-integration)
6. [Advanced Topics](#advanced-topics)

---

## Quick Start

### Run Your First Regression

```bash
# Step 1: Navigate to sim directory
cd /path/to/Fusion_IP/sim

# Step 2: Source environment
source ./project_env.bash

# Step 3: Build (if not built)
make build

# Step 4: Run regression
perl regress.pl

# Expected output:
# Regression report written to: regress.rpt
```

### Check Results

```bash
# View summary
cat regress.rpt | tail -30

# View details
grep -E "PASS|FAIL" regress.rpt

# View logs
ls -la log/*.log
```

---

## Configuration

### Understanding regress.cfg

```bash
# Location
cat regress.cfg

# Format
# test_name , run_times=N , run_opts=opt1+opt2 ;

# Example
fusion_sanity_test , run_times=1 , run_opts= ;
fusion_multi_cycle_test , run_times=2 , run_opts= ;
fusion_irq_status_test , run_times=1 , run_opts= ;
```

### Configuration Fields

| Field | Meaning | Example |
|-------|---------|---------|
| `test_name` | UVM test class name | `fusion_sanity_test` |
| `run_times` | How many runs for this test | `1` = once, `3` = three times |
| `run_opts` | Additional plusargs | `+opt1+opt2` or empty |

### Common Options

```bash
# UVM Verbosity
+UVM_VERBOSITY=UVM_LOW
+UVM_VERBOSITY=UVM_MEDIUM        # Default
+UVM_VERBOSITY=UVM_HIGH

# Coverage
+cov_edge
+cov_toggle

# Disable waveform (faster)
+accel

# Custom seed
+UVM_SEED=12345
```

---

### Creating Custom Configuration

#### Example 1: Quick Smoke Test

```bash
# Save as: quick_smoke.cfg
# Run: perl regress.pl -f quick_smoke.cfg

fusion_sanity_test , run_times=1 , run_opts= ;
```

**Usage:**
```bash
perl regress.pl -f quick_smoke.cfg
# Runs 1 test, completes in ~30 seconds
```

#### Example 2: Full Regression with Coverage

```bash
# Save as: full_cov.cfg

fusion_sanity_test , run_times= , run_opts=+cov_edge+cov_toggle ;
fusion_multi_cycle_test , run_times= , run_opts=+cov_edge+cov_toggle ;
fusion_missing_gps_test , run_times= , run_opts=+cov_edge+cov_toggle ;
fusion_irq_status_test , run_times= , run_opts=+cov_edge ;
fusion_soft_reset_test , run_times= , run_opts=+cov_edge ;
fusion_ral_bit_bash_test , run_times= , run_opts= ;
fusion_scoreboard_predic_test , run_times= , run_opts= ;
fusion_csv_route_test , run_times= , run_opts= ;
```

**Usage:**
```bash
perl regress.pl -f full_cov.cfg -j 4
# Runs all tests with coverage collection
# Parallel execution with 4 jobs
```

#### Example 3: Stress Testing

```bash
# Save as: stress.cfg
# Run each test multiple times with different seeds

fusion_sanity_test , run_times=10 , run_opts= ;
fusion_multi_cycle_test , run_times=10 , run_opts= ;
```

**Usage:**
```bash
perl regress.pl -f stress.cfg -j 4
# Each test runs 10 times = 20 total runs
# With 4 parallel jobs takes ~5-10 minutes
```

---

## Running Regression

### Basic Run

```bash
# Standard regression (uses regress.cfg)
perl regress.pl

# With verbose output
perl regress.pl -v

# With very verbose output
perl regress.pl -vv
```

### Parallel Execution

```bash
# Run tests in parallel (faster)
perl regress.pl -j 4              # 4 jobs at a time
perl regress.pl -j 8              # 8 jobs at a time

# Speed comparison:
# Sequential (-j 1): 8 tests × 1 min = 8 min
# Parallel (-j 4): 8 tests / 4 = 2 min (+10% overhead)
```

### Custom Configuration

```bash
# Use specific config file
perl regress.pl -f custom.cfg

# Run specific test only
# Option 1: Edit regress.cfg, comment out others
# Option 2: Create temp.cfg with just that test
echo "fusion_sanity_test , run_times=1 , run_opts= ;" > temp.cfg
perl regress.pl -f temp.cfg
```

### Report Generation

```bash
# Generate report from existing logs only (no simulation)
perl regress.pl -r

# This creates regress.rpt from log/ directory
# Useful if you want report without re-running tests
```

---

## Analyzing Results

### Report Format

```
regress.rpt:

================================================
           REGRESSION REPORT
================================================

Test Configuration:
  Config file:    regress.cfg
  Run date:       2024-04-02 14:23:45
  Total tests:    8
  Run mode:       Sequential

Test Results:
================================================
Test Number │ Test Name                    │ Status │ Time
────────────┼──────────────────────────────┼────────┼──────────
1           │ fusion_sanity_test           │ PASS   │ 0.45 min
2           │ fusion_multi_cycle_test      │ PASS   │ 0.52 min
3           │ fusion_missing_gps_test      │ PASS   │ 0.38 min
4           │ fusion_irq_status_test       │ FAIL   │ 0.61 min
5           │ fusion_soft_reset_test       │ PASS   │ 0.39 min
6           │ fusion_ral_bit_bash_test     │ PASS   │ 0.51 min
7           │ fusion_scoreboard_predic_test│ PASS   │ 0.48 min
8           │ fusion_csv_route_test        │ PASS   │ 0.43 min

================================================
SUMMARY
================================================
Total run time:         3.77 minutes
Tests passed:           7 / 8
Tests failed:           1 / 8
Success rate:           87.5%
Status:                 REGRESSION FAILED ❌

Failed tests:
  - Test 4: fusion_irq_status_test
    Log: log/fusion_irq_status_test_42_20240402_142345.log
    Failure: Expected IRQ pulse not observed
```

### Quick Analysis

```bash
# Count pass/fail
grep "PASS\|FAIL" regress.rpt | wc -l

# Show only failures
grep "FAIL" regress.rpt

# Show summary
tail -20 regress.rpt

# Show timing
grep -E "min|second" regress.rpt | tail -10

# Full report
cat regress.rpt
```

### Detailed Analysis

#### Step 1: Identify Failed Tests

```bash
grep "FAIL" regress.rpt

# Output:
# Test 4: fusion_irq_status_test    FAIL
```

#### Step 2: Find Log File

```bash
grep "fusion_irq_status_test" regress.rpt | grep "Log:"

# Note the log filename
# Example: log/fusion_irq_status_test_42_20240402_142345.log
```

#### Step 3: Examine Log

```bash
# View end of log where failure occurred
tail -100 log/fusion_irq_status_test_42_20240402_142345.log

# Search for error
grep -i "error\|fail" log/fusion_irq_status_test_42_20240402_142345.log

# Get context
grep -B10 -A10 "IRQ" log/fusion_irq_status_test_42_20240402_142345.log
```

#### Step 4: View Waveform (if available)

```bash
# Check if waveforms captured
ls waves/fusion_irq_status_test*.wlf

# Open in viewer
qwave waves/fusion_irq_status_test_42.wlf &

# Look for IRQ signal
# Zoom to time of failure
# Compare with expected behavior
```

#### Step 5: Root Cause Analysis

| Symptom | Likely Cause | Solution |
|---------|------------|----------|
| `Expected IRQ pulse not observed` | DUT IRQ generation broken | Check DUT RTL, review changes |
| `Timeout waiting for response` | DUT hang or protocol issue | Check protocol compliance |
| `Assertion failure in scoreboard` | Prediction incorrect | Check reference model |
| `Read/write corruption` | AXI protocol violation | Check AXI agent, DUT interface |

---

## Continuous Integration

### Nightly Regression Script

```bash
#!/bin/bash
# nightly_regression.sh

set -e

WORKSPACE="/path/to/Fusion_IP"
SIM_DIR="${WORKSPACE}/sim"
TODAY=$(date +%Y%m%d_%H%M%S)
RESULTS_DIR="${SIM_DIR}/results"

mkdir -p $RESULTS_DIR

echo "🔄 Starting nightly regression at $(date)"

# Change to sim directory
cd $SIM_DIR

# Source environment
source ./project_env.bash

# Clean old logs
rm -f log/*.log

# Build
echo "🔨 Building..."
make clean
make build 2>&1 | tee $RESULTS_DIR/build_$TODAY.log

if [ $? -ne 0 ]; then
  echo "❌ Build failed"
  exit 1
fi

# Run regression
echo "🏃 Running regression..."
perl regress.pl -j 4 2>&1 | tee $RESULTS_DIR/regress_run_$TODAY.log

# Check results
if grep -q "FAIL" regress.rpt; then
  STATUS="FAILED"
  COLOR="❌"
else
  STATUS="PASSED"
  COLOR="✅"
fi

# Create summary
echo "$COLOR Regression $STATUS at $(date)" > $RESULTS_DIR/summary_$TODAY.txt
cat regress.rpt >> $RESULTS_DIR/summary_$TODAY.txt

# Archive results
tar czf $RESULTS_DIR/logs_$TODAY.tar.gz log/

# Send email (optional)
mail -s "Fusion IP Regression $STATUS - $TODAY" team@example.com < $RESULTS_DIR/summary_$TODAY.txt

echo "✅ Nightly regression complete"
```

### Run from Cron

```bash
# Edit crontab
crontab -e

# Add line to run daily at 2 AM
0 2 * * * /path/to/nightly_regression.sh

# View scheduled jobs
crontab -l
```

---

### CI/CD Integration (GitLab)

```yaml
# .gitlab-ci.yml example

stages:
  - build
  - test
  - report

build:
  stage: build
  script:
    - cd sim
    - source ./project_env.bash
    - make clean
    - make build
  artifacts:
    paths:
      - sim/work
    expire_in: 1 day

regression:
  stage: test
  script:
    - cd sim
    - source ./project_env.bash
    - perl regress.pl -j 4
  artifacts:
    paths:
      - sim/regress.rpt
      - sim/log/
  when: on_success

report:
  stage: report
  script:
    - cd sim
    - cat regress.rpt | grep -E "PASS|FAIL|Summary"
  only:
    - merge_requests
```

---

## Advanced Topics

### Multi-Seed Testing

**Purpose:** Find seed-dependent bugs (intermittent failures)

```bash
# Create config with random seeds
cat > multi_seed.cfg << EOF
# Each test runs with different seed
fusion_sanity_test , run_times=5 , run_opts=+UVM_SEED=random ;
fusion_multi_cycle_test , run_times=5 , run_opts=+UVM_SEED=random ;
EOF

# Run
perl regress.pl -f multi_seed.cfg -j 4

# Analyze
grep -c PASS regress.rpt
grep -c FAIL regress.rpt

# If any failed, rerun with same seed to debug:
SEED=$(grep FAIL regress.rpt | head -1 | awk '{print $NF}')
make run TESTNAME=... SEED=$SEED
```

### Coverage Collection

```bash
# Enable coverage in regress.cfg
cat > coverage.cfg << EOF
fusion_sanity_test , run_times=1 , run_opts=+cov_edge+cov_toggle ;
fusion_multi_cycle_test , run_times=1 , run_opts=+cov_edge+cov_toggle ;
EOF

# Run with coverage
perl regress.pl -f coverage.cfg

# Merge coverage databases
cd sim && vcover merge -o merged.ucdb coverage/*.ucdb

# Generate coverage report
vcover report -html merged.ucdb
```

### Performance Profiling

```bash
# Run regression with timing
perl regress.pl -v 2>&1 | tee regress_timing.log

# Extract timing
grep "Test.*:" regress_timing.log | awk '{print $1, $NF}'

# Identify slowest tests
sort -k2 regress_timing.log | tail -5

# Optimize those tests
# - Lower verbosity
# - Reduce simulation time
# - Remove unnecessary waveform capture
```

### Flaky Test Handling

**Problem:** Test passes sometimes, fails sometimes (seed-dependent)

**Solution:**

```bash
# 1. Run test multiple times
for i in {1..10}; do
  echo "Run $i:"
  make run TESTNAME=fusion_irq_status_test SEED=$i 2>&1 | grep -i "pass\|fail"
done

# 2. Collect failing seeds
failing_seeds=()
for i in {1..10}; do
  result=$(make run ... SEED=$i 2>&1 | grep FAIL)
  if [ ! -z "$result" ]; then
    failing_seeds+=($i)
  fi
done

# 3. Debug with those seeds
for seed in "${failing_seeds[@]}"; do
  make run TESTNAME=... SEED=$seed DUMP_WAVES=1
  # Review waveforms
done

# 4. Fix root cause
# - Add constraints to sequence
# - Fix race condition in RTL
# - Add synchronization

# 5. Verify fix
for i in {1..20}; do
  make run TESTNAME=... SEED=$i | grep "PASS\|FAIL"
done | sort | uniq -c
# Should all be PASS now
```

---

## Regression Statistics

### Understanding Results

```
Success Rate = (Tests Passed) / (Total Tests) × 100%

Example:
- 7 passed, 1 failed, 8 total
- Success rate = 7/8 = 87.5%
- ❌ FAIL (should be 100%)

- 8 passed, 0 failed, 8 total  
- Success rate = 8/8 = 100%
- ✅ PASS
```

### Trending (Over Time)

```bash
# Store results
for i in {1..5}; do
  perl regress.pl > regress_run_$i.rpt
  echo "Run $i: $(tail -1 regress_run_$i.rpt | grep -o '[0-9]*%')"
done

# Track success rate:
# Run 1: 100%
# Run 2: 100%
# Run 3: 87.5%  ← degradation!
# Run 4: 75%    ← worsening!
# Run 5: 75%

# Action: Investigate commits between Run 2 and 3
git log --oneline HEAD~5..HEAD
```

---

## Troubleshooting Regression Issues

### Problem: Tests not running

```bash
# Check regress.cfg exists
ls regress.cfg

# Check format
cat regress.cfg | head -5

# Test single run
make run TESTNAME=fusion_sanity_test
```

### Problem: Regression hangs

```bash
# Kill hanging process
pkill -9 vsim

# Check if tests are stuck in make
ps aux | grep make | grep -v grep

# Reduce parallelism
perl regress.pl -j 1

# Or set timeout per test
# Add to regress.cfg: run_opts=+UVM_TIMEOUT=60
```

### Problem: Inconsistent failures

```bash
# Re-run failed tests with same seed
SEED=42
make run TESTNAME=... SEED=$SEED

# Compare logs
diff log/run_1.log log/run_2.log

# If seeds truly random, try fixed seed
perl regress.pl -j 1         # Sequential, removes parallelism effects
```

---

## Best Practices

1. **Run regularly** - Daily/weekly regression catches issues early
2. **Keep config clean** - Only test actively developed features
3. **Archive results** - Save regression reports for trending
4. **Investigate failures** - Fix immediately, don't let stack up
5. **Seed variety** - Use different seeds to find edge cases
6. **Performance monitoring** - Track execution time trends
7. **Document failures** - Note why tests were added/skipped

---

## Quick Reference Commands

```bash
# Standard regression
perl regress.pl

# Fast parallel regression
perl regress.pl -j 4

# Custom config
perl regress.pl -f custom.cfg

# Verbose output
perl regress.pl -v

# Report only (from existing logs)
perl regress.pl -r

# Run specific test
echo "fusion_sanity_test , run_times=1 , run_opts= ;" > temp.cfg
perl regress.pl -f temp.cfg

# View results
cat regress.rpt | tail -30
grep -E "PASS|FAIL" regress.rpt
ls -lhS log/*.log
```

---

**Regression Testing Guide Complete!** 🎯 Full regression workflow mastered.

