# Hướng dẫn chạy verification (dựa trên flow `sim/`)

Tài liệu này mô tả cách dự án UART verification được biên dịch, chạy simulation và regression, để bạn có thể **tái sử dụng cùng kiểu script/Makefile** cho một IP khác.

---

## 1. Công cụ và giả định

| Thành phần | Vai trò |
|------------|---------|
| **Questa / ModelSim** (`vlog`, `vsim`, `vlib`, `vmap`) | Biên dịch SystemVerilog/UVM và chạy testbench |
| **UVM 1.2** | Thư viện testbench (`UVM_HOME`) |
| **GNU Make** | Điều phối `build` / `run` |
| **Perl** (tùy chọn) | Script regression `regress.pl` |
| **Shell kiểu Unix** | `project_env.bash`, Makefile dùng `mkdir -p`, `mv`, `ln -sf` — trên Windows nên dùng **WSL**, **Git Bash**, hoặc MSYS2 |

Makefile gọi trực tiếp `vlog`/`vsim` (không bọc `vsim` trong lệnh `questasim`). Đường dẫn công cụ phải có trong `PATH`.

---

## 2. Sơ đồ file trong `sim/`

```
sim/
├── Makefile          # build (vlog), run (vsim), clean, wave, coverage
├── compile.f         # gom rtl.f + tb.f
├── rtl.f             # danh sách file RTL của DUT
├── tb.f              # VIP, env, testcase, testbench — dùng biến môi trường ${...}
├── project_env.bash  # export UVM_HOME, UART_IP_VERIF_PATH, *_VIP_ROOT
├── regress.cfg       # cấu hình danh sách testcase cho regress.pl
├── regress.pl        # Perl: make build rồi lặp make run theo cfg, sinh regress.rpt
├── modelsim.ini      # (nếu có) cấu hình tool
└── log/              # log và waveform copy từ lần chạy (Makefile tạo)
```

**Chuỗi compile:** `compile.f` chỉ chứa:

```text
-f rtl.f
-f tb.f
```

Toàn bộ đường dẫn nguồn TB/VIP nằm trong `tb.f` thông qua biến như `${UART_IP_VERIF_PATH}`, `${UART_VIP_ROOT}`, `${AHB_VIP_ROOT}`.

---

## 3. Thiết lập môi trường (`project_env.bash`)

Trước khi `make`, cần `source` (hoặc chỉnh tay tương đương):

- **`UVM_HOME`**: thư mục chứa `src/uvm.sv` (UVM 1.2 trong ví dụ gốc).
- **`UART_IP_VERIF_PATH`**: thư mục gốc của **toàn bộ** verification (cha của `tb/`, `testcases/`, `vip/`, …). Trong repo mẫu: `export UART_IP_VERIF_PATH=./..` khi đứng trong `sim/` (tức một cấp lên root dự án).
- **`UART_VIP_ROOT`**, **`AHB_VIP_ROOT`**: đường dẫn tới từng VIP (file `.f` của VIP được include từ `tb.f`).

**Khi chuyển sang IP mới:** đổi tên biến cho đúng (ví dụ `MYIP_VERIF_PATH`, `MYIP_VIP_ROOT`) và cập nhật mọi chỗ trong `tb.f`, `Makefile` (nếu hard-code), và bản sao `project_env.bash`.

---

## 4. Makefile — hành vi chính

Các biến quan trọng (có thể ghi đè trên dòng lệnh):

| Biến | Mặc định | Ý nghĩa |
|------|----------|---------|
| `TB_NAME` | `testbench` | Tên **module** top SV (phải khớp `module testbench` trong `tb/testbench.sv`) |
| `TESTNAME` | `uart_base_test` | Tên class UVM test (`+UVM_TESTNAME=`) |
| `VERBOSITY` | `UVM_HIGH` | `+UVM_VERBOSITY=` |
| `SEED` | `1` | Seed simulation; đặt `SEED=random` để dùng timestamp (`date +%s`) |
| `RUNARG` | (rỗng) | Plusargs bổ sung truyền cho `vsim` |
| `COV` | `OFF` | `ON` để bật tùy chọn coverage trên `vlog`/`vsim` |

**Targets:**

- `make build` — `vlib work`, `vmap`, rồi `vlog -f compile.f` (+ define UVM, timescale, v.v.).
- `make run` — `vsim` với `-c` (batch), `+UVM_TESTNAME=$(TESTNAME)`, log tên `$(TESTNAME)_$(SEED).log`, sau đó chuyển log vào `./log/` và symlink `run.log`.
- `make all` — `build` rồi `run`.
- `make clean` — xóa `work`, log, wlf, ucdb, v.v.
- `make wave` / `make cov_gui` / `make cov_merge` — mở waveform/coverage (khi đã có file tương ứng).

**Ví dụ chạy một testcase:**

```bash
cd sim
source ./project_env.bash   # chỉnh UVM_HOME và path cho đúng máy bạn
make all TESTNAME=full_9600_none_parity SEED=42
```

---

## 5. `rtl.f` và `tb.f` — ranh giới DUT / TB

- **`rtl.f`**: liệt kê file RTL (`.v`, `.vp`, …) của IP. IP mới: thay toàn bộ danh sách file và đường dẫn tới DUT.
- **`tb.f`**: `+incdir` cho sequences, testcases, tb, regmodel; include các file `.f` của VIP; rồi compile package/env/test_pkg/testbench theo thứ tự phụ thuộc.

Để verification IP khác hoạt động tương tự:

1. Thay nội dung `rtl.f` theo RTL mới.
2. Sửa `tb.f` cho khớp cấu trúc thư mục mới (VIP, env, regmodel, `testbench.sv`).
3. Đảm bảo top module trong SV (`TB_NAME`) và `+UVM_TESTNAME` trỏ đúng class test đã đăng ký trong `test_pkg`.

---

## 6. Regression (`regress.pl` + `regress.cfg`)

**`regress.cfg`** (ví dụ):

- `pass_key_word` / `fail_key_word`: chuỗi tìm trong file `log/*.log` để xác định pass/fail (ví dụ `"TEST PASSED"`, `"TEST FAILED"`).
- Khối `tc_list { ... }`: mỗi dòng một testcase, định dạng:

  `tên_testcase , run_times=N , run_opts=+plusarg1+plusarg2 ;`

  - `run_times`: số lần chạy (mỗi lần seed random trong khoảng).
  - `run_opts`: plusargs (script tách bằng dấu `+`).

**Chạy:**

```bash
cd sim
source ./project_env.bash
perl regress.pl          # mặc định đọc regress.cfg
perl regress.pl -f my.cfg
perl regress.pl -r         # chỉ tạo lại báo cáo từ log hiện có
```

Flow: `make build` một lần, sau đó với mỗi dòng testcase: `make run TESTNAME=... SEED=<random> RUNARG=<run_opts>`.

**Lưu ý:** Báo cáo regression dựa trên `grep` log trên môi trường Unix (`grep`, `wc`). Trên Windows cần shell tương thích.

---

## 7. Checklist port flow này sang IP verification khác

1. **Toolchain**: Cài Questa/ModelSim (hoặc chỉnh Makefile nếu dùng simulator khác — sẽ khác cú pháp compile/sim).
2. **`project_env.bash`**: `UVM_HOME`, đường dẫn gốc verification, mọi `*_VIP_ROOT` / `*_VERIF_PATH`.
3. **`sim/rtl.f`**: chỉ file RTL của DUT mới.
4. **`sim/tb.f`**: VIP, packages, `testbench.sv`, thứ tự compile đúng dependency.
5. **`tb/testbench.sv`**: instantiate DUT, clock/reset, `uvm_config_db` cho interface, `run_test()`.
6. **`Makefile`**: nếu đổi tên module top, sửa `TB_NAME`; giữ nguyên pattern `+UVM_TESTNAME` nếu vẫn dùng UVM.
7. **`regress.cfg`**: điền đúng tên class test đã có trong `test_pkg` (hoặc package tương đương), và từ khóa pass/fail khớp với `uvm_info`/`$display` trong TB.
8. **Chạy thử**: `make clean && make all TESTNAME=<base_test>` trước khi chạy full regression.

---

## 8. Tham chiếu nhanh file gốc

| File | Nội dung chính |
|------|----------------|
| `sim/Makefile` | `vlog`/`vsim`, `TESTNAME`, `SEED`, coverage |
| `sim/compile.f` | `-f rtl.f` và `-f tb.f` |
| `sim/project_env.bash` | `UVM_HOME`, `UART_IP_VERIF_PATH`, VIP roots |
| `sim/regress.cfg` | `tc_list`, pass/fail keywords |
| `tb/testbench.sv` | Module `testbench`, DUT `uart_top`, interfaces |

---

*Tài liệu được suy ra từ cấu trúc repo UART-Verification; khi đổi simulator hoặc hệ điều hành, cần điều chỉnh lệnh trong Makefile và khả năng chạy `regress.pl` tương ứng.*
