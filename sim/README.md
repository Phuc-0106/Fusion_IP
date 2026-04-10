# Fusion IP UVM Testbench - Simulation Build & Regression Guide

Linux-optimized build environment untuk Fusion IP UVM verification.

## Cấu Trúc File trong `sim/`

```
sim/
├── Makefile              # Main build script (Questa/VCS/Xcelium)
├── compile.f             # Master compilation filelist
├── rtl.f                 # RTL sources (DUT)
├── tb.f                  # Testbench sources (VIP, UVM, TB)
├── project_env.bash      # Environment setup script
├── regress.cfg           # Regression test configuration
├── regress.pl            # Perl regression runner
├── README.md             # This file
└── log/                  # Test logs (created during run)
```

## Khởi Động Nhanh

### 1. Setup Môi Trường

```bash
cd sim
source ./project_env.bash
```

**Lưu ý:** Kiểm tra `UVM_HOME` có trỏ tới đúng thư mục:
```bash
# Kiểm tra
ls -la $UVM_HOME/src/uvm.sv

# Nếu không tìm thấy, cập nhật trong project_env.bash:
# export UVM_HOME=/path/to/uvm-1.2
```

### 2. Compile & Chạy Single Test

```bash
# Compile RTL + TB
make build

# Chạy sanity test (T1)
make run TESTNAME=fusion_sanity_test

# Hoặc shortcut
make test-sanity

# Chạy với seed cụ thể
make run TESTNAME=fusion_multi_cycle_test SEED=42

# Xem waveform (nếu dump được)
make wave
```

### 3. Chạy Toàn Bộ Test Suite

```bash
# Chạy T1-T8 tuần tự
make test-all

# Hoặc dùng regression script
perl regress.pl
```

## Biến Makefile Quan Trọng

| Biến | Mặc định | Mô Tả |
|------|----------|-------|
| `SIMULATOR` | `questa` | Simulator: questa \| vcs \| xcelium |
| `TESTNAME` | `fusion_sanity_test` | Tên class test UVM |
| `SEED` | `1` | Random seed |
| `VERBOSITY` | `UVM_MEDIUM` | UVM_HIGH \| UVM_MEDIUM \| UVM_LOW |
| `DUMP_WAVES` | `0` | 1 để capture waveform |
| `COV` | `OFF` | ON để enable coverage |
| `DEBUG_MODE` | `OFF` | ON để debug mode |

## Các Lệnh Make Thường Dùng

### Build & Run

```bash
make all                           # Build + run sanity test
make build                         # Compile only
make run TESTNAME=...              # Run specific test
make elaborate SIMULATOR=vcs       # Elaborate (VCS/Xcelium)
make clean                         # Remove all artifacts
make clean-logs                    # Remove logs only
```

### Test Shortcuts

```bash
make test-sanity                   # T1 - Sanity (1 cycle)
make test-multi                    # T2 - Multi-cycle (5 cycles)
make test-missing-gps              # T3 - Missing GPS
make test-irq                      # T4 - Interrupt
make test-reset                    # T5 - Soft reset
make test-ral                      # T6 - RAL bit bash
make test-sb                       # T7 - Scoreboard reference
make test-csv                      # T8 - CSV route (skeleton)
make test-all                      # T1-T8 sequentially
```

### Debug & Analysis

```bash
make debug                         # High verbosity + debug
make debug-wave                    # Debug + waveform
make coverage                      # Enable coverage
make cov_gui                       # Open coverage GUI
make cov_merge                     # Merge coverage DBs
make wave                          # Open waveform
```

### Regression

```bash
perl regress.pl                    # Full regression from regress.cfg
perl regress.pl -f custom.cfg      # Use custom config
perl regress.pl -r                 # Report only (no new tests)
perl regress.pl -v                 # Verbose mode
perl regress.pl -j 4               # 4 parallel jobs
```

## Project Environment (project_env.bash)

Script này set các biến môi trường quan trọng:

- **`UVM_HOME`**: Thư mục UVM library
- **`FUSION_IP_VERIF_PATH`**: Root của verification project
- **`FUSION_IP_*_PATH`**: Các đường dẫn con (TB, tests, agents, env, etc.)
- **`FUSION_IP_RTL_PATH`**: Đường dẫn RTL

**Cập nhật cho máy của bạn:**

```bash
# 1. Mở project_env.bash
vi project_env.bash

# 2. Tìm UVM_HOME và cập nhật path:
export UVM_HOME=/opt/questasim/questasim_10.8b/verilog_src/uvm-1.2
# hoặc
export UVM_HOME=/usr/local/uvm-1.2

# 3. Save & source lại
source ./project_env.bash
```

## File Lists (compile.f, rtl.f, tb.f)

### compile.f
Master filelist - chỉ include hai filelist khác:
```
-f rtl.f
-f tb.f
```

### rtl.f
RTL sources của DUT (Fusion IP), sử dụng biến `${FUSION_IP_RTL_PATH}`:
```
${FUSION_IP_RTL_PATH}/params.vh
${FUSION_IP_RTL_PATH}/cordic.sv
...
${FUSION_IP_RTL_PATH}/fusion_ip_top.sv
```

**Để thêm file RTL mới:** cập nhật rtl.f

### tb.f
All testbench sources (UVM packages, VIP, environments, tests), sử dụng:
- `${UVM_HOME}` - UVM library
- `${FUSION_IP_*_PATH}` - TB paths
- Include directories: `+incdir+...`

**Thứ tự compile quan trọng:**
1. UVM library
2. Base packages (fusion_pkg, fusion_vif, fusion_ral)
3. Agents (axi_agent, sensor_agent)
4. Reference model (ukf_predictor)
5. Scoreboard & Environment
6. Tests
7. Testbench top (cuối cùng)

## Regression Configuration (regress.cfg)

Định nghĩa danh sách test case cho regression:

```
pass_key_word = "PASS - TEST COMPLETED WITHOUT ERRORS";
fail_key_word = "FAILED|ERROR|TIMEOUT";

tc_list {
    fusion_sanity_test , run_times=1 , run_opts= ;
    fusion_multi_cycle_test , run_times=2 , run_opts= ;
    fusion_irq_status_test , run_times=1 , run_opts= ;
    ...
};
```

| Trường | Mô Tả |
|-------|-------|
| `pass_key_word` | Regex pattern để detect pass |
| `fail_key_word` | Regex pattern để detect fail |
| `run_times=N` | Chạy test này N lần (mỗi lần seed ngẫu nhiên) |
| `run_opts=+opt1+opt2` | Plusargs (+ sẽ convert thành space) |

**Thêm test mới vào regression:**
1. Mở `regress.cfg`
2. Thêm dòng vào `tc_list {...}`
3. Format: `test_name , run_times=N , run_opts=+opts ;`

## Regression Script (regress.pl)

Perl script để chạy regression:

```bash
perl regress.pl                    # Đọc regress.cfg, chạy tất cả test
perl regress.pl -f my.cfg          # Dùng custom config
perl regress.pl -r                 # Chỉ tạo report từ logs hiện có
perl regress.pl -v                 # Verbose output
perl regress.pl -j 4               # 4 parallel jobs
perl regress.pl -d log_alt         # Log dir khác
```

**Output:**
- `regress.rpt` - Regression report (pass/fail summary)
- Log files trong `log/` folder

## Simulation Logs

Test logs được lưu vào `log/` folder:

```
log/
├── fusion_sanity_test_1_20260402_120000.log
├── fusion_sanity_test_42_20260402_120030.log
├── run.log                           # Symlink to latest run
└── ...
```

**Tên file format:** `{TESTNAME}_{SEED}_{TIMESTAMP}.log`

## Debug Workflow

### Scenario 1: Test Fail, Cần Xem Log

```bash
# 1. Run test
make run TESTNAME=fusion_sanity_test SEED=42

# 2. Xem log
cat log/run.log
# hoặc
less log/fusion_sanity_test_42_*.log

# 3. Run với verbose
make debug TESTNAME=fusion_sanity_test SEED=42
```

### Scenario 2: Xem Waveform

```bash
# 1. Capture waves
make run TESTNAME=fusion_sanity_test DUMP_WAVES=1

# 2. Open GUI
make wave

# 3. Hoặc manually
qwave waves/fusion_sanity_test_1.wlf &
```

### Scenario 3: Coverage

```bash
# 1. Run with coverage
make coverage TESTNAME=fusion_sanity_test

# 2. Merge multiple runs
make cov_merge

# 3. Open coverage GUI
make cov_gui
```

## Cài Đặt Simulator Khác

### VCS
```bash
# Cập nhật project_env.bash
export PATH="/path/to/vcs/bin:$PATH"

# Run
make all SIMULATOR=vcs TESTNAME=fusion_sanity_test
```

### Xcelium (Cadence)
```bash
# Cập nhật project_env.bash
export PATH="/path/to/xcelium/bin:$PATH"

# Elaborate trước
make elaborate SIMULATOR=xcelium

# Run
make run SIMULATOR=xcelium TESTNAME=fusion_sanity_test
```

## Troubleshooting

| Vấn Đề | Giải Pháp |
|--------|-----------|
| `vlog: command not found` | Cài Questa/ModelSim, set PATH |
| `Cannot find UVM home` | Cập nhật `UVM_HOME` trong `project_env.bash` |
| Variable `${...}` not expanded | Kiểm tra `tb.f` syntax, likely missing `$` |
| Test timeout | Tăng `timeout` hoặc kiểm tra DUT |
| Waveform not found | Run with `DUMP_WAVES=1` |
| Compilation error | Kiểm tra RTL file list order trong `rtl.f` |

## Performance Tips

### Parallel Regression
```bash
perl regress.pl -j 4    # 4 parallel tests
```

### Skip Coverage (ngoài regression)
- Default: `COV=OFF` (nhanh)
- Enable coverage khi needed: `make coverage`

### Clean Build Cache
```bash
make clean
make build              # Fresh compile
```

## Extending the Framework

### Thêm Test Case Mới

1. Tạo test class trong `../uvm/tests/fusion_tests.sv`
2. Thêm vào regression `regress.cfg`:
   ```
   my_new_test , run_times=1 , run_opts= ;
   ```
3. Run:
   ```bash
   make run TESTNAME=my_new_test
   ```

### Thêm VIP Mới

1. Tạo file `.f` cho VIP
2. Cập nhật `tb.f` để include VIP
3. Update `project_env.bash` nếu cần path
4. Run compilation

### Custom Makefile Target

```makefile
# Thêm ke Makefile
my_target:
	@echo "Custom target"
	make run TESTNAME=... SEED=... RUNARG='+opt'
```

## Tham Khảo

- [Makefile Targets](Makefile) - Tất cả make targets và options
- [project_env.bash](project_env.bash) - Environment variables
- [regress.cfg](regress.cfg) - Regression configuration
- [../uvm/](../uvm/) - UVM framework files
- [../docs/UVM_TESTBENCH.md](../docs/UVM_TESTBENCH.md) - UVM design spec

---

**Ready to simulate! Chạy `make test-sanity` để bắt đầu!** 🚀

