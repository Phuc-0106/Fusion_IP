# Quick Start Guide - Fusion IP UVM Simulation

Hướng dẫn nhanh chạy verification trên Linux.

## 5 Phút Setup

### 1. Check Yêu Cầu

```bash
which vlog vsim perl make
# Output should show paths to all tools
```

Nếu thiếu tool nào:
- **Questa/ModelSim**: Cài từ mentor.com hoặc phân phối Linux
- **Perl**: `sudo apt-get install perl` (Ubuntu/Debian)

### 2. Setup Environment

```bash
cd uvm/sim
bash setup.sh
source ./project_env.bash
```

Script `setup.sh` sẽ:
- Tìm kiếm UVM library
- Tạo directories cần thiết (log, waves, coverage)
- Cập nhật `project_env.bash`

### 3. Run First Test

```bash
make test-sanity
```

**Nếu thành công:** Bạn sẽ thấy:
```
[BUILD] Compilation successful
[RUN] Starting simulation: fusion_sanity_test with SEED=1
...
[RUN] Simulation complete - log: log/fusion_sanity_test_1_*.log
```

---

## Những Lệnh Hay Dùng

### Chạy Một Test

```bash
# Shortcut
./run.sh sanity                    # T1
./run.sh multi --seed 42 -w        # T2 + waveform

# Hoặc make
make run TESTNAME=fusion_sanity_test SEED=1
make test-multi
```

### Chạy Toàn Bộ

```bash
# Sequential
make test-all

# Hoặc regression
perl regress.pl
```

### Debug

```bash
# High verbosity
make debug TESTNAME=fusion_sanity_test

# With waveform
./run.sh sanity -w
make wave
```

### Clean

```bash
./clean.sh -a         # All
./clean.sh -l         # Logs only
make clean
```

---

## File Structure

```
sim/
├── Makefile              # All build/run commands
├── compile.f             # Master filelist
├── rtl.f                 # RTL sources
├── tb.f                  # TB sources
├── project_env.bash      # Environment (EDIT UVM_HOME HERE)
├── regress.cfg           # Test list for regression
├── regress.pl            # Regression runner
├── run.sh                # Quick test runner
├── clean.sh              # Quick clean
├── setup.sh              # Initial setup
├── README.md             # Full documentation
└── log/                  # Test logs (auto-created)
```

---

## Common Issues & Solutions

| Issue | Solution |
|-------|----------|
| `vlog: command not found` | Make sure Questa is in PATH: `export PATH="/opt/questasim/bin:$PATH"` |
| `Cannot find UVM home` | Edit `project_env.bash`, set `UVM_HOME` correctly, then `source ./project_env.bash` |
| Test timeout | DUT might hang - check simulation log `cat log/run.log` |
| Waveform empty | Run with `DUMP_WAVES=1`: `make run TESTNAME=... DUMP_WAVES=1` |
| Permission denied on `.sh` | `chmod +x *.sh` |

---

## What's in Each File

| File | Purpose | Edit When |
|------|---------|-----------|
| **compile.f** | Master list (-f rtl.f -f tb.f) | Almost never |
| **rtl.f** | RTL sources | Add RTL files |
| **tb.f** | TB/VIP/UVM sources | Add TB files, change UVM path |
| **project_env.bash** | Environment vars | Set UVM_HOME first time |
| **regress.cfg** | Test case list | Add tests to regression |
| **regress.pl** | Regression script | Usually as-is |
| **run.sh** | Quick runner | Use for convenience |
| **clean.sh** | Quick cleaner | Use to cleanup |
| **Makefile** | Main commands | Rarely edit |

---

## Editing project_env.bash

**The most important step!**

```bash
# Open it
vi project_env.bash

# Find this line (around line 17):
export UVM_HOME=${UVM_HOME:-/opt/questasim/verilog_src/uvm-1.2}

# Change to your actual path, e.g.:
export UVM_HOME=/opt/questasim_10.8b/verilog_src/uvm-1.2

# Verify
source ./project_env.bash
ls $UVM_HOME/src/uvm.sv    # Should exist
```

---

## Editing RTL/TB File Lists

### Add New RTL File

1. Open `rtl.f`
2. Add line: `${FUSION_IP_RTL_PATH}/myfile.sv`
3. Recompile: `make clean && make build`

### Add New TB File

1. Open `tb.f`
2. Add line in right spot (respecting dependencies)
3. Example:
   ```
   // After other env files:
   ${FUSION_IP_ENV_PATH}/my_env.sv
   ```
4. Recompile: `make build`

---

## Adding Test to Regression

1. Make sure class exists in UVM (`uvm/tests/fusion_tests.sv`)
2. Edit `regress.cfg`, add line:
   ```
   my_test_name , run_times=2 , run_opts= ;
   ```
3. Run regression:
   ```bash
   perl regress.pl
   ```

---

## Viewing Results

### Log Files

```bash
# Latest run
cat log/run.log

# Specific test
cat log/fusion_sanity_test_42_*.log

# Follow in real-time
tail -f log/run.log
```

### Waveform (if captured with DUMP_WAVES=1)

```bash
# Open GUI
make wave

# Or manually
qwave waves/fusion_sanity_test_1.wlf &
```

### Regression Report

```bash
# After running regress.pl
cat regress.rpt

# Or run with -r flag (report only)
perl regress.pl -r
```

---

## Next Steps

1. ✓ Run first test: `make test-sanity`
2. ✓ Verify output passes
3. → Run all tests: `make test-all`
4. → Setup regression: `perl regress.pl`
5. → Add your own test cases

---

## Getting Help

```bash
# Makefile help
make help

# Regress script help
perl regress.pl -h

# Run script help
./run.sh -h

# Full documentation
cat README.md
```

---

**Happy Testing!** 🎉

