# Fusion IP - Linux Compilation Guide

## 🐧 Running on Linux Environment

**Status:** compile.f files updated for Linux ✅

---

## 📋 Prerequisites

```bash
# Verify Questa is installed
which vlog
which vsim

# Verify Python (for CSV processing)
python3 --version

# Verify environment setup
source project_env.bash
echo $UVM_HOME
```

---

## 🔨 Compilation Steps

### Step 1: Clean Previous Build

```bash
cd sim
make clean

# Or manually:
rm -rf work
rm -rf *.wlf *.shm *.fsdb
rm transcript modelsim.ini
```

### Step 2: Create Work Directory

```bash
cd sim
vlib work
vmap work work
```

### Step 3: Compile RTL + Testbench

**Option A: Using Makefile (Recommended)**

```bash
make build      # Automatic compilation
```

**Option B: Manual Compilation**

```bash
cd sim
vlog -sv +define+SIMULATION -f compile.f
```

### Step 4: Verify Compilation

```bash
# Check for errors
ls -la work/

# Should see multiple .o files (compiled objects)
ls work/
```

---

## ✅ Compilation Verification

```bash
# Run simple test
make test-sanity

# Check log
tail -50 log/run.log

# Should see: "TEST PASSED"
```

---

## 🔧 Troubleshooting Linux Compilation

### Error: "File not found: params.vh"

**Cause:** Include paths not set correctly

**Solution:**
```bash
# Verify file exists
ls -la rtl/params.vh

# Check compile.f has +incdir+
grep "+incdir+" compile.f

# Re-run compilation
make clean && make build
```

### Error: "Cannot find library"

**Solution:**
```bash
cd sim

# Rebuild library
vlib work
vmap work work

# Recompile
make build
```

### Error: "UVM classes not found"

**Solution:**
```bash
# Set UVM_HOME
export UVM_HOME=/opt/questasim/verilog_src/uvm-1.2

# Or source environment
source project_env.bash

# Recompile
make clean && make build
```

### Path Issues on Linux

**Common mistakes:**
```bash
# ❌ WRONG - Windows style
-f ..\rtl\compile.f

# ✅ CORRECT - Unix style
-f ../rtl/compile.f
```

**Fix:** All compile.f files use forward slashes `/` (already done ✅)

---

## 🏃 Running Tests

### After successful compilation:

```bash
# Sanity test
make test-sanity

# Multi-cycle test
make test-multi

# All tests
make test-all

# CSV test (after processing data)
python3 ../scripts/csv_processor.py \
  --gps ../scripts/example_data/gps_scenario_1.csv \
  --imu ../scripts/example_data/imu_scenario_1.csv \
  --odom ../scripts/example_data/odom_scenario_1.csv \
  -o ../scripts/fused_timeline.csv

make test-csv CSV_FILE=../scripts/fused_timeline.csv
```

---

## 📊 Compilation Order Reference

**RTL Modules (Bottom-up dependency):**

```
1. params.vh          (parameters, no dependencies)
2. cordic.sv          (uses params.vh)
3. fp_sqrt.sv         (uses params.vh)
4. sync_fifo.sv       (uses params.vh)
5. state_mem_reg.sv   (uses params.vh)
6. matrix_math_core.sv (uses cordic, fp_sqrt)
7. sigma_point_generator.sv (uses matrix_math_core)
8. predict_block.sv   (uses matrix_math_core)
9. update_block.sv    (uses matrix_math_core)
10. sensor_input_block.sv (converts sensor input)
11. ukf_controller.sv  (top-level controller)
12. fusion_ip_top.sv   (wrapper, uses all)
```

**TB + UVM:**

```
1. tb_fusion_ip.sv        (instantiates DUT)
2. fusion_env.sv          (UVM environment)
3. fusion_base_test.sv    (base test class)
4. Test cases             (loaded dynamically)
```

---

## 🚀 Quick Linux Build Script

Create `build.sh`:

```bash
#!/bin/bash
set -e

echo "Cleaning previous build..."
cd sim
make clean
echo "✓ Cleaned"

echo "Building design..."
make build
echo "✓ Built successfully"

echo "Running sanity test..."
make test-sanity
echo "✓ Sanity test passed"

echo "All done! ✅"
```

Run it:
```bash
chmod +x build.sh
./build.sh
```

---

## 📝 compile.f File Structure

### sim/compile.f (Master)
- Sets all +incdir+ paths
- Includes all RTL files directly
- Includes testbench files
- Platform: Linux-compatible

### rtl/compile.f (Standalone RTL)
- Includes only RTL files
- Can compile RTL independently
- Uses relative paths

### tb/compile.f (Standalone TB)
- Includes only testbench files
- Can compile TB independently
- References RTL via +incdir+

---

## ✨ Linux-Specific Optimizations

```bash
# Use faster compilation
vlog -sv +incdir+../rtl +incdir+../tb -f compile.f

# Compile with optimization
vlog -sv +define+SIMULATION -O5 -f compile.f

# Parallel compilation (if supported)
vlog -sv +define+SIMULATION -j 4 -f compile.f

# Verbose output for debugging
vlog -sv +define+SIMULATION -v -f compile.f
```

---

## 📚 Useful Linux Commands

```bash
# Check compilation status
ls -la work/

# Count compiled objects
ls work/ | wc -l

# Check for errors in log
grep -i error sim/log/*.log

# View compilation time
time vlog -sv -f compile.f

# Find missing files
find . -name "*.vh" -o -name "*.sv"

# Verify paths (Linux)
readlink -f rtl/params.vh
```

---

## ✅ Verification Checklist

After compilation on Linux:

- [ ] `make build` completes without errors
- [ ] `work/` directory exists with .o files
- [ ] `make test-sanity` passes
- [ ] LogFile shows "TEST PASSED"
- [ ] No warnings about missing includes
- [ ] CSV processor works: `python3 csv_processor.py --help`
- [ ] `make test-csv` runs successfully

---

## 🎯 Typical Session

```bash
# Terminal Session Example

$ cd ~/Fusion_IP/sim
$ source project_env.bash
$ make clean
$ make build
$ make test-sanity

# Expected output:
# ✓ Build successful
# ✓ TEST PASSED
```

---

## 📞 Common Issues & Solutions

| Issue | Solution |
|-------|----------|
| "File not found" | Add to +incdir+, check spelling |
| "UVM not found" | source project_env.bash |
| "Compilation slow" | Use -j option for parallel |
| "Path issues" | Use forward slashes / |
| "Permission denied" | chmod +x script.sh |

---

**Linux compilation ready! Run `make build` to start.** 🚀
