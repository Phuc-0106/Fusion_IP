# Fusion IP - Restructured Directory Layout

## 📂 New Folder Structure

```
Fusion_IP/
├── rtl/                    # RTL Design Files
│   ├── compile.f          # RTL compilation filelist
│   ├── params.vh          # Global parameters
│   ├── cordic.sv
│   ├── fp_sqrt.sv
│   ├── sync_fifo.sv
│   ├── state_mem_reg.sv
│   ├── matrix_math_core.sv
│   ├── sigma_point_generator.sv
│   ├── predict_block.sv
│   ├── update_block.sv
│   ├── sensor_input_block.sv
│   ├── ukf_controller.sv
│   └── fusion_ip_top.sv
│
├── regmodel/              # Register Abstraction Layer (RAL)
│   ├── fusion_reg_model.sv
│   ├── fusion_env_cfg.sv
│   └── README.md
│
├── agents/                # UVM Agents (Reusable)
│   ├── sensor_agent/
│   │   ├── sensor_driver.sv
│   │   ├── sensor_sequencer.sv
│   │   └── sensor_monitor.sv
│   ├── axi_agent/
│   └── README.md
│
├── sequences/             # UVM Sequences (Stimuli Generation)
│   ├── base_sequences.sv
│   ├── csv_route_sequence.sv
│   └── README.md
│
├── tb/                    # Testbench Top-Level
│   ├── compile.f         # TB compilation filelist
│   ├── tb_fusion_ip.sv   # Top-level TB
│   ├── fusion_env.sv     # UVM Environment
│   ├── fusion_base_test.sv
│   └── README.md
│
├── testcases/            # Specific Test Cases
│   ├── fusion_sanity_test.sv
│   ├── fusion_multi_cycle_test.sv
│   ├── fusion_missing_gps_test.sv
│   ├── fusion_irq_status_test.sv
│   ├── fusion_soft_reset_test.sv
│   ├── fusion_ral_bit_bash_test.sv
│   ├── fusion_scoreboard_ref_test.sv
│   ├── fusion_csv_route_test.sv
│   └── README.md
│
├── sim/                  # Simulation Infrastructure
│   ├── compile.f        # Master compilation filelist
│   ├── Makefile         # Build automation
│   ├── regress.pl       # Regression runner
│   ├── project_env.bash # Environment setup
│   └── README.md
│
├── scripts/             # Golden generation (AIS + UKF → UVM)
│   ├── generate_golden.py
│   ├── convert_stimulus.py
│   ├── requirements.txt
│   ├── README.md
│   ├── QUICK_REFERENCE.md
│   ├── INTEGRATION_GUIDE.md
│   └── (legacy: csv_processor.py, run_csv_test.sh, …)
│
├── docs/                # Documentation
│   ├── UVM_TESTBENCH.md
│   └── …
│
├── .git/
├── .gitignore
├── .vscode/
└── Makefile             # Top-level Makefile (optional)
```

---

## 🔄 Migration Planning

### Phase 1: Create New Directories (✅ DONE)
- ✅ Created: rtl/, regmodel/, agents/, sequences/, tb/, testcases/
- ✅ Created compile.f files for rtl/, tb/, sim/

### Phase 2: Move Files (TO DO - Manual)

**Move RTL files to rtl/:**
```bash
cd Fusion_IP
mv params.vh rtl/
mv cordic.sv rtl/
mv fp_sqrt.sv rtl/
mv sync_fifo.sv rtl/
mv state_mem_reg.sv rtl/
mv matrix_math_core.sv rtl/
mv sigma_point_generator.sv rtl/
mv predict_block.sv rtl/
mv update_block.sv rtl/
mv sensor_input_block.sv rtl/
mv ukf_controller.sv rtl/
mv fusion_ip_top.sv rtl/
```

**Move testbench to tb/:**
```bash
mv tb_fusion_ip.sv tb/
```

**Copy UVM structure from uvm/ to tb/ and other folders:**
```bash
# Move tests to testcases/
cp uvm/tests/*.sv testcases/

# Move agents to agents/ (if separate)
cp uvm/agents/*.sv agents/

# Move sequences to sequences/
cp uvm/sequences/*.sv sequences/

# Move base/environment to tb/
cp uvm/base/*.sv tb/
cp uvm/environment/*.sv tb/
```

**Move/Update compile.f:**
```bash
# rtl/compile.f and tb/compile.f are already created
# Update sim/compile.f (already done)
```

### Phase 3: Update Paths (✅ DONE)
- ✅ Updated sim/compile.f to reference ../rtl/, ../tb/
- ✅ Created rtl/compile.f and tb/compile.f with proper includes

### Phase 4: Test Build
```bash
cd sim
make clean
make build
```

---

## ✅ Quick Start After Migration

```bash
# 1. Copy files to new structure (see Phase 2 above)

# 2. Check paths are correct
cd sim
make build          # Should compile successfully

# 3. Run tests
make test-sanity

# 4. Run CSV test
python3 ../scripts/csv_processor.py \
  --gps ../scripts/example_data/gps_scenario_1.csv \
  --imu ../scripts/example_data/imu_scenario_1.csv \
  --odom ../scripts/example_data/odom_scenario_1.csv \
  -o ../scripts/fused_timeline.csv

make test-csv CSV_FILE=../scripts/fused_timeline.csv
```

---

## 📋 Benefits of New Structure

| Aspect | Benefit |
|--------|---------|
| **Scalability** | Easy to add more agents, sequences, testcases |
| **Reusability** | Agents can be packaged separately |
| **Maintainability** | Clear separation of concerns |
| **CI/CD Integration** | Each folder can be tested independently |
| **Documentation** | README in each folder explains purpose |
| **Modularity** | Add new verification easily |

---

## 📞 Final Steps

1. **Run the bash command sequence in Phase 2** to move files
2. **Update any custom includes** in your files if using full paths
3. **Test**: `cd sim && make build`
4. **Verify**: `make test-sanity`

**Questions?** See docs/ folder for detailed guides.

