# Fusion IP UVM Build Guide - Linux Workflow

Hướng dẫn đầy đủ build, compile, run, và regression trên Linux.

## Workflow Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                    Fusion IP Verification Flow                   │
├─────────────────────────────────────────────────────────────────┤
│                                                                   │
│  1. SETUP                                                         │
│     ├─ bash setup.sh          (detect tools, create dirs)        │
│     └─ source project_env.bash (set environment)                 │
│                                                                   │
│  2. BUILD (Compilation)                                          │
│     ├─ make build            (vlog compile RTL + TB)             │
│     └─ rm -rf work/          (if rebuild needed)                 │
│                                                                   │
│  3. RUN (Simulation)                                              │
│     ├─ make test-X            (run single test)                  │
│     ├─ make test-all          (run T1-T8 sequential)             │
│     └─ perl regress.pl        (run regression)                   │
│                                                                   │
│  4. ANALYZE                                                       │
│     ├─ cat log/run.log        (check log)                        │
│     ├─ make wave              (view waveform)                    │
│     └─ cat regress.rpt        (regression report)                │
│                                                                   │
└─────────────────────────────────────────────────────────────────┘
```

## Complete Step-by-Step Guide

### Step 1: Initial Setup

```bash
# 1a. Navigate to sim directory
cd /path/to/Fusion_IP/sim

# 1b. Run setup script (one time)
bash setup.sh

# 1c. Setup environment (every new shell session)
source ./project_env.bash

# Verify:
echo "UVM_HOME: $UVM_HOME"
echo "FUSION_IP_VERIF_PATH: $FUSION_IP_VERIF_PATH"
```

**Expected output:**
```
============================================
Fusion IP UVM Verification Environment
============================================
UVM Home:               /opt/questasim_10.8b/verilog_src/uvm-1.2
Fusion IP Verif Path:   /path/to/Fusion_IP
...
============================================
```

### Step 2: Compilation

```bash
# Clean previous build (if any)
make clean

# Compile RTL + TB
make build

# or with verbose output
make build VERBOSITY=UVM_HIGH
```

**What happens:**
1. `vlib work` - Create ModelSim library
2. `vlog -f compile.f` - Compile all sources
3. Sources included: RTL, UVM packages, environments, tests

**Expected output:**
```
[BUILD] Compiling with questa...
[VLOG] Compiling RTL and TB sources from compile.f...
[BUILD] Compilation successful
```

**Troubleshooting:**
```bash
# If compile error, check:
make clean
make build 2>&1 | head -50     # Show first 50 lines

# Check file syntax
vlog -sv rtl.f tb.f            # Manual compile to see errors
```

### Step 3: Run Single Test

#### Option A: Using Makefile

```bash
# Sanity test (T1)
make test-sanity

# Or specific test
make run TESTNAME=fusion_multi_cycle_test SEED=42

# With waveform
make run TESTNAME=fusion_sanity_test DUMP_WAVES=1

# High verbosity
make debug TESTNAME=fusion_sanity_test SEED=1
```

#### Option B: Using Quick Runner Script

```bash
# Simple
./run.sh sanity

# With options
./run.sh multi --seed 42 -w

# Get help
./run.sh -h
```

#### Option C: Manual Make

```bash
make run TESTNAME=fusion_sanity_test SEED=1 VERBOSITY=UVM_HIGH
```

**Expected output:**
```
[RUN] Starting simulation: fusion_sanity_test with SEED=1
...
UVM_INFO @ 10000ns: root|run_phase [TEST PASSED]
...
[RUN] Simulation complete - log: log/fusion_sanity_test_1_20260402_120000.log
```

### Step 4: Run All Tests (T1-T8)

```bash
# Sequential run (takes ~2-5 minutes)
make test-all

# Or quick runner
for test in sanity multi missing-gps irq reset ral sb csv; do
    ./run.sh $test --seed 1
done
```

**What it runs:**
- T1: Sanity (1 cycle)
- T2: Multi-cycle (5 cycles)
- T3: Missing GPS (error handling)
- T4: Interrupt (IRQ test)
- T5: Soft Reset (reset mechanism)
- T6: RAL Bit Bash (register access)
- T7: Scoreboard Ref (prediction check)
- T8: CSV Route (timeline test)

### Step 5: Regression Testing

```bash
# Full regression (uses all settings in regress.cfg)
perl regress.pl

# With verbose output
perl regress.pl -v

# Parallel runs (4 tests at once)
perl regress.pl -j 4

# Custom config
perl regress.pl -f my_regress.cfg

# Report only (from existing logs)
perl regress.pl -r
```

**Output:**
- `regress.rpt` - Comprehensive report with pass/fail/time
- Logs in `log/` folder for each test run
- Summary statistics

### Step 6: Analyze Results

#### Check Test Log

```bash
# View latest log
cat log/run.log

# Or specific test
cat log/fusion_sanity_test_42_*.log

# Search for errors
grep -i error log/run.log
grep -i fail log/run.log

# View end of log
tail -50 log/run.log
```

#### View Waveform (if captured)

```bash
# Open waveform viewer
make wave

# Or manually
qwave waves/fusion_sanity_test_1.wlf &

# View with other tools
gtkwave waves/fusion_sanity_test_1.fsdb        # If VCS dump
```

#### Check Regression Report

```bash
# View regression report
cat regress.rpt

# Or tail (last 50 lines)
tail -50 regress.rpt

# Search results
grep -E "PASS|FAIL|Error" regress.rpt
```

## Common Build Scenarios

### Scenario 1: Fresh Build & Test

```bash
cd sim
source ./project_env.bash
make clean              # Remove old artifacts
make build              # Fresh compile
make test-sanity       # Run one test
```

### Scenario 2: Rebuild After RTL Change

```bash
# Edit RTL file, then:
make build              # Recompile
make test-sanity       # Run test
```

### Scenario 3: Multiple Seeds (Stress Test)

```bash
# Run same test multiple times with different seeds
for seed in 1 42 123 999 54321; do
    make run TESTNAME=fusion_sanity_test SEED=$seed
done

# View results
ls -la log/fusion_sanity_test_*.log
grep -c PASS log/fusion_sanity_test_*.log
```

### Scenario 4: Debug Single Test

```bash
# Run with full debugging
make debug TESTNAME=fusion_irq_status_test SEED=1

# Or with waveform
make debug-wave TESTNAME=fusion_irq_status_test

# Then view log & waves
cat log/run.log
make wave
```

### Scenario 5: Coverage Analysis

```bash
# Run with coverage
make coverage TESTNAME=fusion_sanity_test

# Merge multiple coverage runs
make cov_merge

# View coverage GUI
make cov_gui
```

## File Structure After Build

```
sim/
├── work/                       # ModelSim library (generated)
│   ├── _info
│   ├── _lib1_0.so
│   └── ...
│
├── log/                        # Test logs (generated)
│   ├── fusion_sanity_test_1_20260402_120000.log
│   ├── run.log                 # Symlink to latest
│   └── ...
│
├── waves/                      # Waveform files (if DUMP_WAVES=1)
│   ├── fusion_sanity_test_1.wlf
│   └── ...
│
├── coverage/                   # Coverage DB (if COV=ON)
│   ├── fusion_sanity_test_1.ucdb
│   └── ...
│
└── *.f, *.bash, Makefile, ...  # Config files
```

## Makefile Variable Reference

| Variable | Default | Values | Example |
|----------|---------|--------|---------|
| SIMULATOR | questa | questa \| vcs \| xcelium | `SIMULATOR=vcs` |
| TESTNAME | fusion_sanity_test | Test class name | `TESTNAME=fusion_multi_cycle_test` |
| SEED | 1 | Integer or `random` | `SEED=42` |
| VERBOSITY | UVM_MEDIUM | UVM_HIGH \| MED \| LOW | `VERBOSITY=UVM_HIGH` |
| DUMP_WAVES | 0 | 0 \| 1 | `DUMP_WAVES=1` |
| DEBUG_MODE | OFF | ON \| OFF | `DEBUG_MODE=ON` |
| COV | OFF | ON \| OFF | `COV=ON` |
| RUNARG | (empty) | Plusargs | `RUNARG='+opt1+opt2'` |

## Performance & Resource Tips

### Speed Up Compilation

```bash
# Parallel compilation (if supported)
make build -j 4              # Use 4 CPU cores

# Incremental compilation (change only affected files)
# Just recompile changed module
vlog -sv path/to/changed.sv work
```

### Speed Up Simulation

```bash
# Disable waveform capture (faster)
make run DUMP_WAVES=0

# Disable coverage (faster)
COV=OFF (default)

# Lower verbosity (less output)
make run VERBOSITY=UVM_LOW
```

### Clean Up Space

```bash
# Remove logs only
./clean.sh -l

# Remove waveforms only  
./clean.sh --waves

# Full clean
./clean.sh -a
```

## Automation & CI/CD

### Simple Bash Script

```bash
#!/bin/bash
# run_all_tests.sh

cd sim
source ./project_env.bash
make clean
make build

for test in sanity multi missing-gps irq reset ral sb; do
    echo "Running $test..."
    make run TESTNAME=fusion_${test}_test
done

echo "All tests complete - check logs:"
ls -la log/
```

### Makefile Recipe

```makefile
# Add to Makefile
nightly:
	@echo "[NIGHTLY] Starting nightly regression..."
	perl regress.pl -j 4
	@echo "[NIGHTLY] Complete - report:"
	@cat regress.rpt | tail -20
```

Run with:
```bash
make nightly
```

## Troubleshooting Build Issues

| Error | Cause | Solution |
|-------|-------|----------|
| `vlog: command not found` | Tool not in PATH | `source project_env.bash` |
| Variable `${...}` not expanded | Missing source | `source ./project_env.bash` |
| Compilation timeout | Large design | Reduce verbosity, check syntax |
| Simulation hang | DUT loop | Check RTL, set timeout |
| Waveform empty | Not enabled | `DUMP_WAVES=1` |
| Log size large | Verbose output | Lower `VERBOSITY` |

## Next Steps

1. ✓ Understand the workflow above
2. → Follow "Quick Start" section
3. → Customize test list in `regress.cfg`
4. → Integrate into your CI/CD pipeline
5. → Add custom tests

---

**Build Guide Complete!** 🎉 Ready to simulate your verification.

