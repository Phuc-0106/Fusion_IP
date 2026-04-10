# Fusion IP UVM Best Practices

Hướng dẫn các phương pháp tốt nhất khi phát triển và duy trì verification environment.

## Table of Contents

1. **Test Development** - Writing effective tests
2. **Code Organization** - Structuring test code
3. **Debugging Strategies** - Efficiently finding bugs
4. **Performance Tips** - Optimizing simulation speed
5. **Maintenance** - Keeping codebase clean
6. **Documentation** - Clear, maintainable docs
7. **Continuous Integration** - Automated workflows

---

## 1. Test Development Best Practices

### 1.1: Test Template Structure

When creating a new test, follow this pattern:

```systemverilog
// fusion_custom_test.sv
class fusion_custom_test extends fusion_base_test;
  `uvm_component_utils(fusion_custom_test)

  //--------- Constructor ---------
  function new(string name, uvm_component parent);
    super.new(name, parent);
    // Set test-specific configuration
    test_timeout = 100_000;
    expected_cycles = 50;
  endfunction

  //--------- Build Phase ---------
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    
    // Override configurations here
    // fusion_env::set_config_int("*", "param", value);
    
    // Create sequences
    vseq = new("vseq");
    
    uvm_config_db #(uvm_sequence #(uvm_sequence_item))::set(
      this, "vseq", "default_sequence", vseq);
  endfunction

  //--------- Connect Phase ---------
  virtual function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    
    // Connect analysis ports if custom scoreboard
    // env.intf_a.monitor.item_collected_port.connect(...);
  endfunction

  //--------- Run Phase (Main Test Logic) ---------
  virtual task run_phase(upm_phase phase);
    super.run_phase(phase);
    
    phase.raise_objection(this);
    
    // Your test sequence
    vseq.start(env.virt_seqr);
    
    // Wait for DUT response
    #(100_000);
    
    phase.drop_objection(this);
  endtask

  //--------- Report Phase ---------
  virtual function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    
    `uvm_info(get_type_name(), "Test complete", UVM_LOW)
    
    // Optional: Generate custom report
    // ...
  endfunction

endclass: fusion_custom_test

// Testbench instantiation
virtual fusion_custom_test vtest;
```

**Why this structure?**
- Follows UVM phase hierarchy
- Separates concerns (build/connect/run/report)
- Easy to override in derived classes
- Enables reuse through inheritance

---

### 1.2: Sequence Writing Guidelines

#### Good Sequence:

```systemverilog
class good_axi_write_seq extends uvm_sequence #(axi_transaction);
  `uvm_object_utils(good_axi_write_seq)

  // Customizable parameters
  rand int unsigned num_writes = 5;
  rand bit [31:0] write_addr_base = 32'h00;
  rand bit [31:0] write_data = 32'hDEADBEEF;
  
  constraint addr_range { write_addr_base >= 32'h00; write_addr_base <= 32'h100; }
  constraint data_range { write_data != 0; }

  function new(string name="good_axi_write_seq");
    super.new(name);
  endfunction

  virtual task body();
    repeat(num_writes) begin
      axi_transaction tr;
      
      tr = axi_transaction::type_id::create("tr");
      
      // Use constraint randomization
      assert(tr.randomize() with {
        addr == (write_addr_base + (num_writes-1) * 4);
        write_data == local::write_data;
        wr_en == 1'b1;
      })
      else begin
        `uvm_error(get_type_name(), "Randomization failed")
      end
      
      // Send transaction
      start_item(tr);
      finish_item(tr);
      
      // Log
      `uvm_info(get_type_name(), $sformatf("Wrote [0x%08x] = 0x%08x", 
        tr.addr, tr.write_data), UVM_MEDIUM)
    end
  endtask

endclass: good_axi_write_seq
```

#### Bad Sequence (avoid):

```systemverilog
// ❌ DON'T DO THIS

class bad_seq extends uvm_sequence #(item_t);
  virtual task body();
    // Hard-coded values - no reusability
    item_t tr = new();
    tr.addr = 32'h0;
    tr.data = 32'h12345678;
    start_item(tr);
    finish_item(tr);
    
    // No constraints - no stimulus variety
    // No logging - hard to debug
    // No error checking - failures silent
    // No documentation - unclear intent
  endtask
endclass
```

---

### 1.3: Test Naming Convention

```
fusion_[feature]_[variant]_test

Examples:
- fusion_sanity_test           (basic smoke test)
- fusion_multi_cycle_test      (multi-cycle operation)
- fusion_missing_gps_test      (error condition)
- fusion_irq_status_test       (interrupt handling)
- fusion_soft_reset_test       (reset mechanism)
- fusion_ral_bit_bash_test     (register access)
```

---

## 2. Code Organization Best Practices

### 2.1: File Structure

```
uvm/
├── base/
│   ├── fusion_pkg.sv           # Core types, functions, enums
│   └── fusion_ral.sv           # RAL register model
│
├── agents/
│   ├── axi/
│   │   └── axi_agent.sv        # AXI driver, monitor, sequencer
│   │
│   └── sensor/
│       └── sensor_agent.sv     # Sensor driver, monitor, sequencer
│
├── environment/
│   ├── fusion_env.sv           # Environment, base test, global sequences
│   ├── fusion_scoreboard.sv    # Scoreboard, prediction logic
│   └── fusion_coverage.sv      # Coverage model (optional)
│
├── ref_model/
│   └── ukf_predictor.sv        # Reference model for prediction
│
├── tests/
│   ├── fusion_tests.sv         # All test cases (T1-T8)
│   └── fusion_custom_test.sv   # User-defined tests
│
├── tb.f                        # Testbench file list
├── compile.f                   # Compilation include files
└── fusion_tb_top.sv            # Top-level testbench
```

**Why this structure?**
- Clear separation of concerns
- Scalable for adding new agents
- Easy to find specific components
- Follows UVM conventions

---

### 2.2: Header Comments

Every file should have:

```systemverilog
//=============================================================================
// File:         fusion_custom_module.sv
// Description:  [Brief description of purpose]
// Author:       [Your Name]
// Date:         [YYYY-MM-DD]
// Version:      1.0
//=============================================================================
// Revision History:
//=============================================================================
// Version | Date       | Author      | Changes
//---------|------------|-----------  |------------------------------------
// 1.0     | 2024-04-02 | John Doe    | Initial version
// 1.1     | 2024-04-05 | Jane Smith  | Added feature X
//=============================================================================

// ============================================================================
// IMPORTS & PARAMETERS
// ============================================================================
`include "uvm_macros.svh"
import uvm_pkg::*;
import fusion_pkg::*;

// ============================================================================
// CLASS DEFINITION
// ============================================================================
class my_class extends base_class;
  //...
endclass

// ============================================================================
// MODULE INSTANTIATION (if applicable)
// ============================================================================
module my_module(...);
  //...
endmodule

```

---

### 2.3: Code Organization Within Files

```systemverilog
class well_organized_class extends uvm_object;
  `uvm_object_utils(well_organized_class)

  //========== Class Properties ==========
  // Public
  string my_string;
  int    my_int;
  
  // Protected - inheritance only
  protected bit protected_flag;
  
  // Private - this class only
  local real local_value;

  //========== Constraints ==========
  constraint valid_range { my_int inside {[0:255]}; }

  //========== Constructor ==========
  function new(string name="well_organized_class");
    super.new(name);
  endfunction

  //========== Build/Config Methods ==========
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    // Build logic
  endfunction

  //========== Functional Methods ==========
  virtual task do_something();
    // Functional logic
  endtask

  //========== Analysis Methods ==========
  virtual function void analyze_result();
    // Analysis logic
  endfunction

endclass
```

---

## 3. Debugging Strategies

### 3.1: Effective Logging

```systemverilog
// ✓ GOOD: Informative logs
`uvm_info(get_type_name(), 
  $sformatf("Writing address=0x%08x, data=0x%08x", addr, data), 
  UVM_MEDIUM)

// ✗ BAD: Unhelpful logs
`uvm_info("TEST", "Write done", UVM_LOW)

// ✓ GOOD: Errors with context
`uvm_error(get_type_name(), 
  $sformatf("Timeout after %0d cycles waiting for VALID. Last data: 0x%08x", 
    timeout_cycles, last_data))

// ✗ BAD: Generic errors
`uvm_error("TEST", "Timeout occurred")
```

**Log Verbosity Guide:**
```
UVM_NO_VERBOSITY  = 0   - No output
UVM_LOW           = 100 - Critical failures only
UVM_MEDIUM        = 200 - Important events (default)
UVM_HIGH          = 300 - Detailed traces
UVM_FULL          = 400 - Debug-level detail
```

---

### 3.2: Assertions

```systemverilog
// ✓ GOOD: Clear assertions with messages
assert(transaction.addr inside {[0:0xFFFF]})
else `uvm_error(get_type_name(), 
  $sformatf("Address out of range: 0x%x", transaction.addr))

// ✓ Assert properties
assert(response_time <= MAX_RESPONSE_LATENCY)
else `uvm_warning(get_type_name(), 
  "Response latency exceeded expected maximum")

// ✗ BAD: Silent failures
if (transaction.addr > 0xFFFF) begin
  // Silent failure - test continues
end
```

---

### 3.3: Waveform Debugging

```bash
# Capture waveforms for specific test
make run TESTNAME=fusion_irq_status_test DUMP_WAVES=1

# View waveforms
make wave

# Or manually open
qwave waves/fusion_irq_status_test_1.wlf

# In waveform viewer:
# 1. Add signals of interest
# 2. Mark region of problem
# 3. Step through event by event
# 4. Compare with expected behavior
```

**Key signals to watch:**
```
DUT Inputs:
- clk, rst_n
- axi_awvalid, axi_wvalid, axi_arvalid
- sensor_gps_valid, sensor_imu_valid, sensor_odom_valid

DUT Outputs:
- axi_bvalid, axi_rvalid
- state_out, covariance_out
- irq_flag, error_flag
```

---

## 4. Performance Optimization Tips

### 4.1: Simulation Speed

```bash
# OPTION 1: Reduce verbosity (fastest)
make run TESTNAME=... VERBOSITY=UVM_LOW

# OPTION 2: No waveform dumping
make run TESTNAME=... DUMP_WAVES=0

# OPTION 3: No coverage collection
COV=OFF make run TESTNAME=...

# OPTION 4: Parallel compilation
make build -j 4

# OPTION 5: Combined (fastest)
COV=OFF make run TESTNAME=fusion_sanity_test VERBOSITY=UVM_LOW
```

**Performance ranking:**
1. UVM_LOW + No Waves + No Coverage = ~50% faster
2. UVM_MEDIUM + No Waves = ~30% faster
3. Default = baseline 100%

---

### 4.2: Reduce Simulation Time

```systemverilog
// ✓ GOOD: Efficient sequence
class fast_sequence extends uvm_sequence;
  virtual task body();
    // Use constraints for directed stimulus
    repeat(10) begin
      item_t tr;
      assert(tr.randomize() with {
        tr.delay > 0; TR.delay < 100; // Short delays
      })
      start_item(tr);
      finish_item(tr);
    end
  endtask
endclass

// ✗ AVOID: Long delays
class slow_sequence extends uvm_sequence;
  virtual task body();
    #(1_000_000);  // 1M cycles - test never finishes!
    repeat(100) begin
      item_t tr;
      tr.randomize();
      start_item(tr);
      finish_item(tr);
      #(10_000);    // Unnecessary delay between items
    end
  endtask
endclass
```

---

### 4.3: Smart Test Configuration

```bash
# Quick smoke test (< 1 second)
make run TESTNAME=fusion_sanity_test SEED=1 VERBOSITY=UVM_LOW

# Full regression run (< 5 minutes)
perl regress.pl -j 4                      # Parallel execution

# Coverage collection (slow)
COV=ON make run TESTNAME=... -v           # Verbose + coverage

# Baseline: ~500k cycle tests take 30-60 seconds
# Optimize non-critical tests for speed
```

---

## 5. Maintenance Best Practices

### 5.1: Test Maintenance

```bash
# Regular tasks:

# 1. Update tests after DUT changes
git diff HEAD~1 ../fusion_ip_top.sv
# Review register changes, port changes
# Update RAL model (fusion_ral.sv)
# Update test sequences

# 2. Rotate seed for nightly run
# Edit regress.cfg
# fusion_sanity_test , run_times=5 , run_opts=+UVM_TESTNAME=... ;
perl regress.pl -j 4

# 3. Monitor test results
cat regress.rpt | tail -20

# 4. Archive old logs
cd log
tar czf archive_20260402.tar.gz *.log
rm -f *.log

# 5. Update documentation
# Keep QUICK_START.md current
```

---

### 5.2: Regression Management

```bash
# Weekly regression checklist:

# 1. Full test run
perl regress.pl -v

# 2. Check results
if grep -q "FAIL" regress.rpt; then
  echo "❌ Regression FAILED"
  grep "FAIL" regress.rpt
else
  echo "✓ Regression PASSED"
fi

# 3. Archive results
cp regress.rpt reports/regress_20260402.rpt

# 4. Generate trend
tail -10 reports/regress_*.rpt | grep "Summary:"
```

---

## 6. Documentation Best Practices

### 6.1: Code Comments

```systemverilog
// ✓ GOOD: Purpose and rationale
// Wait for DUT to complete calculation before checking output.
// The DUT pipeline is 5 stages deep, so we need at least 50 cycles
// after asserting start to see valid output.
#(50 * CLOCK_PERIOD);

// ✗ BAD: Obvious comments
// Increment loop counter
i++;

// ✓ GOOD: Clarify constraints
constraint addr_aligned { addr % 4 == 0; }  // Must be 4-byte aligned per AXI spec

// ✗ BAD: No explanation
constraint { a < b; c > d; }  // Why these constraints?
```

---

### 6.2: Test Documentation

```bash
# For each test, document:
# 1. PURPOSE - what feature being tested
# 2. STIMULUS - what inputs generated
# 3. EXPECTED RESULT - what should happen
# 4. FAILURE CONDITION - what indicates failure

# Example: fusion_irq_status_test

# PURPOSE
# Verify IRQ generation when UKF state changes
# Test that interrupt occurs after measurement update

# STIMULUS
# 1. Send GPS/IMU/Odometry measurements
# 2. Each measurement triggers UKF calculation
# 3. Monitor interrupt flag

# EXPECTED RESULT
# 1. DUT irq_flag pulses high for 1 cycle
# 2. Can be cleared by writing to IRQ_CLR register

# FAILURE CONDITION
# 1. irq_flag never asserted
# 2. IRQ_CLR register write doesn't clear flag
```

---

## 7. Continuous Integration

### 7.1: Nightly Regression Script

```bash
#!/bin/bash
# nightly_regress.sh

set -e

cd /path/to/Fusion_IP/sim

# Source environment
source ./project_env.bash

# Setup
mkdir -p reports
DATE=$(date +%Y%m%d_%H%M%S)

# Run regression
echo "Starting nightly regression at $DATE"
perl regress.pl -j 4 -v 2>&1 | tee reports/run_$DATE.log

# Check result
if grep -q "FAIL" regress.rpt; then
  echo "❌ REGRESSION FAILED"
  cat regress.rpt
  mail -s "Fusion IP Regression Failed" team@example.com < regress.rpt
  exit 1
else
  echo "✓ REGRESSION PASSED"
  mail -s "Fusion IP Regression Passed" team@example.com < regress.rpt
fi

# Archive
cp regress.rpt reports/result_$DATE.rpt
tar czf reports/logs_$DATE.tar.gz log/

echo ✓ Complete
```

Schedule with cron:
```bash
# Run nightly at 2 AM
0 2 * * * /path/to/nightly_regress.sh
```

---

### 7.2: Git Workflow

```bash
# Before committing test changes:

# 1. Run full regression
perl regress.pl

# 2. Check no regressions
if grep -q "FAIL" regress.rpt; then
  echo "Fix failures before committing"
  exit 1
fi

# 3. Commit with clear message
git add uvm/tests/
git commit -m "Add fusion_custom_feature_test

- Tests new UKF mode switching functionality
- Verifies state machine transitions
- All existing tests pass
- Coverage: 15 new assertions"

# 4. Push
git push origin feature-branch

# 5. CI/CD runs regression automatically
```

---

## 8. Quick Reference Checklist

**When Adding a New Test:**
- [ ] Follow naming convention: `fusion_[feature]_test`
- [ ] Inherit from `fusion_base_test`
- [ ] Include UVM macros: `uvm_component_utils`
- [ ] Add header comment (purpose, author, date)
- [ ] Add detailed logging (UVM_INFO/ERROR/WARNING)
- [ ] Test passes individually: `make test-<name>`
- [ ] Test passes in regression: `perl regress.pl`
- [ ] Add to `regress.cfg`
- [ ] Document in `tests/README.md`

**When Modifying RTL:**
- [ ] Update `rtl.f` if files added
- [ ] Update `fusion_ral.sv` if registers changed
- [ ] Update test sequences if interface changed
- [ ] Run full regression: `perl regress.pl -j 4`
- [ ] Update `CHANGELOG.md`

**Before Committing:**
- [ ] Code follows naming conventions
- [ ] All tests pass (`perl regress.pl`)
- [ ] Logs are clean (no warnings/errors)
- [ ] Documentation is current
- [ ] No hardcoded values
- [ ] Clear comments on complex logic

---

## 9. Further Resources

- **UVM Cookbook**: `$UVM_HOME/docs/uvm_cookbook.html`
- **SystemVerilog LRM**: IEEE 1800-2017 standard
- **Verification Methodologies**: Look at industry references
- **Tool Manuals**: `vsim -help`, `vlog -help`

---

**Best Practices Guide Complete!** ✨ Follow these practices for maintainable, scalable, high-quality verification!

