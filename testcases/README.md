# TESTCASES - Test Definitions

This directory contains specific test case classes for Fusion IP verification.

## Available Tests

### T1 - Sanity Test
**File:** fusion_sanity_test.sv  
**Purpose:** Basic smoke test - verify DUT responds to simple stimulus  
**Duration:** 1 cycle  
**Run:** `make test-sanity`

### T2 - Multi-Cycle Test  
**File:** fusion_multi_cycle_test.sv  
**Purpose:** Extended operation with multi-cycle measurements  
**Duration:** 100+ cycles  
**Run:** `make test-multi`

### T3 - Missing GPS Test
**File:** fusion_missing_gps_test.sv  
**Purpose:** Verify graceful degradation when GPS unavailable  
**Run:** `make test-missing-gps`

### T4 - IRQ Status Test  
**File:** fusion_irq_status_test.sv  
**Purpose:** Verify interrupt signaling and status registers  
**Run:** `make test-irq`

### T5 - Soft Reset Test
**File:** fusion_soft_reset_test.sv  
**Purpose:** Test reset sequence and register initialization  
**Run:** `make test-reset`

### T6 - RAL Bit Bash Test
**File:** fusion_ral_bit_bash_test.sv  
**Purpose:** Register-level verification using RAL model  
**Run:** `make test-ral`

### T7 - Scoreboard Reference Test
**File:** fusion_scoreboard_ref_test.sv  
**Purpose:** Full end-to-end verification with reference model  
**Run:** `make test-sb`

### T8 - CSV Route Test
**File:** fusion_csv_route_test.sv  
**Purpose:** AIS golden stimulus (`golden_stimulus.csv` / `golden_expected.csv`) and scoreboard checks  
**Prepare:** `python scripts/generate_golden.py --case N` (see `scripts/README.md`)  
**Run:** `cd sim && make test-csv`

## Creating New Tests

```systemverilog
class my_new_test extends fusion_base_test;
    `uvm_component_utils(my_new_test)
    
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction
    
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        // Test-specific config
    endfunction
    
    task run_phase(uvm_phase phase);
        // Test sequence
    endtask
endclass
```

## Integration with Regression

Add to sim/regress.cfg:
```
my_new_test , run_times=1 , run_opts=+SEED=1 ;
```

Then run:
```bash
make regress
```

## Test Naming Convention

Format: `fusion_<feature>_test.sv`

Examples:
- fusion_sanity_test.sv
- fusion_gps_loss_test.sv
- fusion_multi_rate_test.sv

## Notes

- All tests inherit from fusion_base_test
- Tests run independently
- Each test has unique random seed
- Coverage files merged automatically with `make coverage`

