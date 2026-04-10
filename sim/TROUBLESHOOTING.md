# Fusion IP Troubleshooting Guide

Giải pháp các lỗi phổ biến khi build, compile, và run verification trên Linux.

## Troubleshooting Categories

1. **Environment Issues** - Setup, paths, environment variables
2. **Compilation Errors** - vlog errors, syntax issues
3. **Simulation Errors** - Runtime, timeout, assertion failures
4. **Regression Issues** - Test failures, missing logs
5. **Tool Issues** - Missing simulators, license problems

---

## 1. Environment Issues

### Problem 1.1: `command not found: vlog`

**Error:**
```
bash: vlog: command not found
```

**Cause:** Questa/ModelSim not in PATH

**Solution:**
```bash
# Check if setup.sh detected tool
bash setup.sh

# If not found, manually add to project_env.bash:
export PATH=/opt/questasim_10.8b/bin:$PATH

# Then source it
source ./project_env.bash

# Verify
which vlog
vlog -version
```

---

### Problem 1.2: `${UVM_HOME} not set` or UVM not found

**Error:**
```
vlog: Error: Cannot find UVM files in ${UVM_HOME}
```

**Cause:** UVM library not installed or wrong path

**Solution:**

**Option A: Using standard installation locations**
```bash
# Common locations for UVM:
# - /opt/questasim_10.8b/verilog_src/uvm-1.2
# - /opt/synopsys/vcs/etc/uvm-1.2
# - $HOME/uvm-1.2

bash setup.sh  # Auto-detect UVM

# Verify detection:
echo $UVM_HOME
ls $UVM_HOME/src/uvm.sv
```

**Option B: Manual UVM installation**
```bash
# Download UVM 1.2 from Accellera
wget https://www.accellera.org/.../UVM-1.2.tar.gz

# Extract
tar xzf UVM-1.2.tar.gz -C /opt/

# Update project_env.bash:
export UVM_HOME=/opt/UVM-1.2

source ./project_env.bash
```

**Option C: Check existing tools**
```bash
# List installed simulators and UVM versions
vlib -version
which vlog

# Questa integrated UVM
ls /opt/questasim_*/verilog_src/uvm-*/
```

---

### Problem 1.3: `FUSION_IP_*_PATH` variables not set

**Error:**
```
Error: Cannot find file ${FUSION_IP_TB_PATH}/fusion_pkg.sv
```

**Cause:** `project_env.bash` not sourced or wrong paths

**Solution:**
```bash
# Always source FIRST in new shell
source ./project_env.bash

# Verify paths
echo "FUSION_IP_VERIF_PATH: $FUSION_IP_VERIF_PATH"
echo "FUSION_IP_TB_PATH: $FUSION_IP_TB_PATH"
echo "FUSION_IP_RTL_PATH: $FUSION_IP_RTL_PATH"

# Check if files exist
ls $FUSION_IP_TB_PATH
ls $FUSION_IP_RTL_PATH

# If paths wrong, edit project_env.bash manually:
# FUSION_IP_VERIF_PATH=/actual/path/to/Fusion_IP
# FUSION_IP_TB_PATH=${FUSION_IP_VERIF_PATH}/uvm/...
# etc.
```

---

### Problem 1.4: "permission denied" on scripts

**Error:**
```
bash: ./setup.sh: Permission denied
```

**Solution:**
```bash
# Make scripts executable
chmod +x setup.sh clean.sh run.sh regress.pl

# Verify
ls -la *.sh *.pl

# All should have 'x' permission:
# -rwxr-xr-x  1 user  group
```

---

## 2. Compilation Errors

### Problem 2.1: Verilog syntax error in .f file

**Error:**
```
vlog -f compile.f
** Error: compile.f, line 42: near ";;;": syntax error
```

**Cause:** Malformed compile.f or tb.f

**Solution:**
```bash
# Check the actual file line
sed -n '42p' compile.f

# Common issues:
# - Trailing semicolon: /path/to/file.sv;
# - Double slash in path: //path/to/file.sv
# - Windows line endings (CRLF)

# Fix Windows line endings:
dos2unix compile.f
dos2unix rtl.f
dos2unix tb.f

# Re-check
cat compile.f | head -50
```

---

### Problem 2.2: Cannot find include file

**Error:**
```
Error: Cannot find file '../params.vh'
```

**Cause:** 
- Include path not expanded
- File doesn't exist

**Solution:**
```bash
# Check if file exists
ls -la ../params.vh

# Check if compile.f is using correct paths
cat rtl.f | head -20

# Verify environment expansion
grep "FUSION_IP" rtl.f

# If using variables, verify they are exported
echo $FUSION_IP_RTL_PATH
ls $FUSION_IP_RTL_PATH/params.vh
```

---

### Problem 2.3: Cannot find module / undefined reference

**Error:**
```
Error: Cannot find module (cordic)
```

**Cause:**
- Module not compiled
- Wrong file order in tb.f

**Solution:**
```bash
# Check if cordic.sv in rtl.f
grep cordic rtl.f

# Verify file exists
find . -name "cordic.sv"

# Check compile order (RTL before TB)
cat compile.f

# Should be:
# -f rtl.f
# -f tb.f

# If order wrong, edit compile.f
```

---

### Problem 2.4: Compilation timeout

**Error:**
```
Error: Compilation timed out after 300 seconds
```

**Cause:**
- Large design taking too long
- Infinite loop in elaboration

**Solution:**
```bash
# Break compilation into steps
vlib work
vlog -f rtl.f           # Compile RTL only first
vlog -f tb.f            # Then TB

# Or compile per-module
vlog params.vh
vlog cordic.sv
vlog fp_sqrt.sv
# ... etc

# Or use parallel compilation
make build -j 4

# Check for infinite loops in RTL
grep -r "always @*" *.sv | grep -v "always @(posedge"
# May cause issues in elaboration
```

---

## 3. Simulation Errors

### Problem 3.1: Test hangs / simulation not terminating

**Error:**
```
Simulation started...
[waiting indefinitely - process never completes]
```

**Cause:**
- DUT deadlock
- Testbench infinite wait
- Insufficient timeout

**Solution:**
```bash
# Kill stuck simulation
pkill -9 vsim
pkill -9 questa

# Check testbench log for where it hangs
tail -100 log/run.log

# Look for last message
grep -B5 "^$" log/run.log | tail -10

# Run with shorter timeout
timeout 60 make run TESTNAME=fusion_sanity_test

# Or manually set vsim timeout
make run TESTNAME=... RUNARG="+UVM_TIMEOUT=60"

# Debug: check RTL for infinite loops
grep -r "always @*" uvm/
# Or check reset sequencing
```

---

### Problem 3.2: Assertion failure in UVM

**Error:**
```
UVM_ERROR @ 10000ns: root|end_of_elaboration [ASSERTION FAILED]
```

**Cause:**
- Configuration not set
- Missing interface connection
- RAL not initialized

**Solution:**
```bash
# Check logs for detailed error
grep "ASSERTION" log/run.log -A5 -B5

# Common assertion failures:
# - Virtual interface not set: Check fusion_tb_top.sv line where uif is set
# - RAL block not configured: Check env config phase
# - Missing agent configuration

# Re-run with increased verbosity
make run VERBOSITY=UVM_HIGH TESTNAME=...

# Check setup in env
grep -n "virtual_interfaces" uvm/environment/fusion_env.sv
```

---

### Problem 3.3: "Object not found" error

**Error:**
```
UVM_FATAL @ 0ns: root [OBSFAC]
Object not found in factory: fusion_sanity_test
```

**Cause:**
- Test class not registered `uvm_component_utils` macro
- Test class not in TB filelists
- Wrong test name

**Solution:**
```bash
# Verify test class name
grep "class fusion_sanity_test" uvm/tests/fusion_tests.sv

# Verify it has registration macro
grep -A2 "class fusion_sanity_test" uvm/tests/fusion_tests.sv
# Should have: `uvm_component_utils(fusion_sanity_test)

# Check if tb.f includes fusion_tests.sv
grep fusion_tests uvm/tb.f

# Verify test name in Makefile is correct
grep "TESTNAME" Makefile | head -5

# Try exact class name
make run TESTNAME=fusion_sanity_test
# or
make run TESTNAME=fusion_multi_cycle_test
```

---

### UKF scoreboard debug plusargs (`fusion_scoreboard`)

Run with extra UVM info to isolate **sigma generation**, **predict**, and **covariance update** mismatch (DUT FP32 vs reference `real`):

```bash
make run TESTNAME=fusion_multi_cycle_test RUNARG="+UKF_DEBUG_SIGMA +UKF_DEBUG_PPRED"
# Optional: P matrix dump after each PRIMARY compare
# RUNARG="+UKF_DEBUG_SIGMA +UKF_DEBUG_PPRED +UKF_DEBUG_P"
```

| Plusarg | Log tag | Meaning |
|--------|---------|--------|
| `+UKF_DEBUG_SIGMA` | `UKF_DBG_SIGMA` | `max \|χ_RM − χ_DUT\|` where χ_RM = `gen_sigma` using **χ_dut[0]** as prior mean `x` + **latched** `ADDR_P` vs full `ADDR_SIGMA`. Also logs `max \|χ_dut[0] − latched_x\|` (should be ~0 if ADDR_X matches σ row 0 when peeked). |
| `+UKF_DEBUG_PPRED` | `UKF_DBG_PPRED` | Recompute `P_pred` from DUT χ @ `ADDR_SIGMA` + Q + dt vs `ADDR_PPRED`. Large → predict or layout; small if σ matches. |
| `+UKF_DEBUG_P` | `UKF_DBG` | Predictor `P` vs DUT `ADDR_P` after `step()`; LDL raw diagonals. |
| `+UKF_FULL_UKF_UPDATE` | — | Reference `update()` uses full 11-point S/T (textbook UKF) instead of linear **H** (`S≈HPH'+R`, `T≈PH'`) like `update_block`. Default is linear H for better PRIMARY alignment with DUT. |

**Reading results:** If SIGMA and PPRED are small but PRIMARY still drifts, check float vs FP32 and predict-step (CTRV) vs DUT. The reference **update** path uses linear **H** plus **Joseph**, aligned with `rtl/update_block.sv`.

**PRIMARY resync:** After each output compare, the scoreboard **latches** `ADDR_X`/`ADDR_P` and calls `predictor.apply_dut_posterior_xP()` so the next cycle’s `step()` starts from **DUT RAM** (not a free-running float chain). Without this, cycle 2+ `step()` ran **before** the latch from the previous cycle could correct drift, so `P_RM` stayed diagonal while DUT `P` gained cross-terms.

**`|χ₀ − peek ADDR_X|` at compare:** `ADDR_X` is usually already the **posterior** after the UKF that just finished, while `χ₀` in `ADDR_SIGMA` is the **prior mean** frozen at sigma generation — so this difference can be **O(innovation)**, not a latch bug. Use **`|χ₀ − latched_x|`** (latched = prior at σ time) for consistency checks; expect ~ULP if DUT and TB agree on timing.

---

### Problem 3.4: Empty log file

**Error:**
```
cat log/run.log
[Empty or truncated output]
```

**Cause:**
- Simulation crashed/segfaulted
- Log not flushed
- vsim error before logging started

**Solution:**
```bash
# Run with verbose output to console
make run TESTNAME=... VERBOSITY=UVM_HIGH | tee run_output.txt

# Or check any error logs
ls -la log/

# Run manually to see errors
cd work
vsim -do 'run -all; quit' fusion_tb_top -sv_seed random

# Check for vsim crashes
tail -50 .vsim_crash* 2>/dev/null

# Try minimal test
make build
make test-sanity VERBOSITY=UVM_MEDIUM 2>&1 | head -100
```

---

### Problem 3.5: RAL/Register access timeout

**Error:**
```
UVM_ERROR @ 50000ns: uvm_test_top|env|axi_ag|drv [SEQ]
Read operation timed out after 10000ns
```

**Cause:**
- DUT not responding to AXI reads
- RTL not connected to AXI interface
- AXI protocol violation

**Solution:**
```bash
# Check DUT connectivity in fusion_tb_top.sv
grep -A10 "fusion_ip_top" uvm/fusion_tb_top.sv

# Verify AXI interface in DUT
grep -n "axi_" uvm/../fusion_ip_top.sv | head -10

# Increase timeout in test
# In fusion_tests.sv, modify read timeout:
# base_axi_sequence: add `#(uvm_sequence_item) seq;`
# and change:
#     seq.timeout = 50000;  // Increase from default

# Check waveform to see if AXI transactions happening
make run TESTNAME=fusion_ral_bit_bash_test DUMP_WAVES=1
make wave
# Look for axi_wready, axi_rvalid toggle

# Manual AXI write test
make debug TESTNAME=fusion_ral_bit_bash_test
# Then in vsim: wave *
# look for axi_* signal activity
```

---

## 4. Regression Issues

### Problem 4.1: `regress.pl: command not found`

**Error:**
```
bash: regress.pl: command not found
```

**Solution:**
```bash
# Make it executable
chmod +x regress.pl

# Run correctly
perl regress.pl
# Not: ./regress.pl

# Or if Perl not found:
which perl
perl --version

# On Linux, install Perl if missing
apt-get install perl          # Debian/Ubuntu
yum install perl              # RHEL/CentOS
```

---

### Problem 4.2: Regression not finding tests

**Error:**
```
regress.pl: No tests configured in regress.cfg
Summary: 0 tests run, 0 passed, 0 failed
```

**Cause:**
- regress.cfg malformed
- Test names wrong

**Solution:**
```bash
# Check regress.cfg format
cat regress.cfg

# Correct format:
# test_name , run_times=N , run_opts=+opt1+opt2 ;

# Example (in regress.cfg):
# fusion_sanity_test , run_times=1 , run_opts= ;
# fusion_multi_cycle_test , run_times=2 , run_opts= ;

# Verify file syntax
perl -c regress.pl            # Check Perl syntax

# Try parsing manually
grep -v "^#" regress.cfg | grep -v "^$" | wc -l
# Should show number of tests

# Run with verbose to see parsing
perl regress.pl -v 2>&1 | head -50
```

---

### Problem 4.3: Some tests fail in regression

**Error:**
```
regress.rpt:
Test: fusion_irq_status_test ... FAIL
```

**Cause:**
- Flaky test (intermittent)
- SEED-dependent failure
- Resource contention (parallel runs)

**Solution:**
```bash
# Re-run single failing test with same SEED
grep "fusion_irq_status_test" regress.cfg
# Note the SEED from regress.rpt

# Run standalone
make run TESTNAME=fusion_irq_status_test SEED=<seed_from_rpt>

# Check logs
cat log/fusion_irq_status_test_<seed>_*.log | grep -i "error\|fail"

# If due to parallel runs, run sequentially
perl regress.pl -j 1        # Force sequential

# If still flaky, mark as intermittent and skip
# Edit regress.cfg: Comment out line
# #fusion_irq_status_test , run_times=1 , run_opts= ;
```

---

## 5. Tool Issues

### Problem 5.1: License issue

**Error:**
```
Error: FlexLM license error: ...
License server not responding
```

**Cause:**
- License server down
- License file invalid
- Tool license expired

**Solution:**
```bash
# Check license
lmutil lmstat -a 2>/dev/null | head -20

# Or for specific tool
vlog -license

# Set license path
export LM_LICENSE_FILE=/opt/license.dat
export QUESTA_LMHOSTS=server.example.com

# Check Questa specifically
vsim -license

# Contact IT for license issues
# Temporary workaround: Use open-source simulator (if RTL compatible)
# - Icarus Verilog
# - Verilator (faster, for fixed simulation)
```

---

### Problem 5.2: Simulator version mismatch

**Error:**
```
Expected Questa 10.8, but found version 10.4
```

**Cause:**
- Multiple simulators installed
- Wrong PATH order

**Solution:**
```bash
# Check which simulator is active
which vlog
vlog -version

# May need to update PATH
# Edit project_env.bash:
export PATH=/opt/questasim_10.8b/bin:$PATH

# Reload
source ./project_env.bash
vlog -version

# Should show correct version
```

---

### Problem 5.3: Verilog 2008/SystemVerilog not supported

**Error:**
```
Error: Unsupported language feature (interface)
```

**Cause:**
- Tool too old
- Not compiling as SystemVerilog (-sv flag)

**Solution:**
```bash
# Check Makefile has -sv flag
grep "\-sv" Makefile

# Should have:
# VLOG_OPTS = -sv

# If using older simulator, may need:
# vlog -sv2012 ... (if available)

# Or upgrade simulator
vlog -upgrade    # Check if available
```

---

## 6. Common Quick Fixes

| Problem | Quick Fix |
|---------|-----------|
| Environment not set | `source ./project_env.bash` |
| Permission denied | `chmod +x *.sh *.pl` |
| Compilation failed | `make clean && make build` |
| Test hung | `pkill -9 vsim` + check RTL |
| Empty log | `make run VERBOSITY=UVM_HIGH` |
| Test not found | Verify test name in `fusion_tests.sv` |
| Wrong UVM | Run `bash setup.sh` to auto-detect |
| License error | Check `lmutil lmstat` |
| Tool not found | Add to PATH: `export PATH=/opt/tool/bin:$PATH` |

---

## 7. Debug Workflow

### Level 1: Basic Check

```bash
# Verify setup
source ./project_env.bash
which vlog vsim perl
vlog -version
ls $UVM_HOME

# Verify files
ls uvm/*.sv
ls log/
```

### Level 2: Compilation Debug

```bash
# Compile with verbose
make clean
vlib work
vlog -sv -f compile.f -v 2>&1 | head -50

# Check specific file
vlog -sv uvm/base/fusion_pkg.sv -v
```

### Level 3: Simulation Debug

```bash
# Run single test with verbosity
make run TESTNAME=fusion_sanity_test VERBOSITY=UVM_HIGH | tee debug.log

# Check logs
tail -100 log/run.log

# View waveforms
make wave
```

### Level 4: Deep Investigation

```bash
# Run in GUI
cd work
vsim -gui &

# Type commands:
# run -all
# wave *
# write wave.file wave

# Or use batch mode with logging
vsim -batch -do 'run -all; write waves.vcd; quit' -l sim.log
```

---

## 8. Getting Help

### Check Documentation

```bash
cat README.md          # Overview
cat BUILD_GUIDE.md     # Build process
cat INSTALLATION.md    # Installation
cat QUICK_START.md     # Quick reference
```

### Check Logs

```bash
# Latest log
cat log/run.log

# All logs for pattern
grep "ERROR" log/*.log

# Regression report
cat regress.rpt
```

### Manual Investigation

```bash
# Check RTL
grep -n "always @*" *.sv

# Check TB
grep -n "uvm_" uvm/**/*.sv | head -20

# Check for warnings
make build 2>&1 | grep Warning
```

---

## 9. Support Resources

- **UVM Documentation**: See `$UVM_HOME/docs/`
- **Questa Help**: `vsim -h` or `vlog -h`
- **Perl Debugging**: `perl -d regress.pl`
- **Verilog Syntax**: Check IEEE 1364/1800 standards
- **Linux Commands**: `man make`, `man perl`, etc.

---

**Troubleshooting complete!** 🔧 For additional help, check the logs and documentation above.

