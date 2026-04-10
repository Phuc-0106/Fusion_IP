# Thiết kế UVM testbench cho Fusion IP (UKF sensor fusion)

Tài liệu này mô tả **ngữ cảnh**, **cấu trúc**, **danh mục test** và **luồng thực thi** cho việc xây dựng testbench UVM xác minh `fusion_ip_top`.

---

## 1. Context

### 1.1 Device Under Test (DUT)

- **Module top:** `fusion_ip_top`
- **Chức năng:** Unscented Kalman Filter (UKF) hợp nhất đo từ **GPS** (2D vị trí), **IMU** (góc \(\psi\), tốc độ góc \(\dot\psi\)), **Odom** (vận tốc \(v\)).
- **Số học:** fixed-point **Q8.24** (32-bit signed) trên toàn datapath UKF.
- **Pipeline điều khiển:** `ukf_controller` — `READ_SENSORS` → `SIGMA_GEN` → `PREDICT` → `UPDATE` → `WRITEBACK`.

### 1.2 Giao diện cần verify

| Giao diện | Mô tả | Ghi chú verify |
|-----------|--------|----------------|
| **AXI4-Lite slave** | MMIO: `CTRL`, `STATUS`, thanh ghi đo (`GPS_X`…`ODOM_V`), đầu ra (`OUT_X`…`OUT_DOT`), `IRQ_CLR` | RAL (register map), bus functional model |
| **Sensor streaming** | `gps_data`/`gps_valid`, `imu_data`/`imu_valid`, `odom_data`/`odom_valid` | Agent riêng; đồng bộ với chu kỳ UKF |
| **Interrupt** | `irq` | Kiểm tra sau khi `STATUS.valid` / writeback |

### 1.3 Bộ nhớ trạng thái nội bộ

- **`state_mem_reg`:** 256×32-bit — chứa \(x\), \(P\), \(Q\), \(R\), sigma, \(x_{pred}\), \(P_{pred}\), …  
- **Không** xuất hiện trên map AXI cho phần mềm host. Trong verify có thể dùng **backdoor** (hierarchical) hoặc checker tách nếu cần so khớp sâu.

### 1.4 Mục tiêu testbench UVM

- Kiểm tra **đúng giao thức bus** và **đúng hành vi chức năng** (một hoặc nhiều chu kỳ UKF).
- So sánh **đầu ra** với **mô hình tham chiếu** (ref) khi có scenario có golden / ngưỡng.
- Hỗ trợ mở rộng: **route từ CSV** (AIS / sensor đã merge theo thời gian), **nhiễu đo**, **thiếu cảm biến**.

---

## 2. Cấu trúc test (UVM)

### 2.1 Sơ đồ phân cấp (khuyến nghị)

```
uvm_test
├── fusion_env_config      // timeout, ngưỡng scoreboard, đường dẫn file route, seed
└── fusion_env
    ├── fusion_reg_block   // RAL — chỉ map MMIO AXI
    ├── reg_adapter        // reg2bus / bus2reg cho AXI4-Lite
    ├── axi_agent          // sequencer, driver, monitor — AXI4-Lite master
    ├── sensor_agent       // sequencer, driver, monitor — GPS/IMU/Odom
    ├── predictor          // mô hình tham chiếu UKF (optional per test)
    └── scoreboard         // actual vs expected
```

### 2.2 Thành phần chính

| Thành phần | Vai trò |
|------------|---------|
| **`fusion_reg_block`** | `uvm_reg_block` mirror các thanh ghi byte-addressed như `fusion_ip_top` (0x00 `CTRL`, 0x04 `STATUS`, 0x08…0x18 đo, 0x20…0x30 OUT, 0x34 `IRQ_CLR`). |
| **`axi_agent`** | Tạo transaction write/read 32-bit; driver điều khiển `s_axi_*`; monitor thu transaction gửi scoreboard / cập nhật predictor. |
| **`sensor_agent`** | Sequence item: một “frame” đo \((x_{gps}, y_{gps}, \psi, \dot\psi, v)\) + có thể điều khiển `*_valid` để mô phỏng thiếu sensor. |
| **`predictor`** | Ref model: cùng input đo + (tùy chọn) khởi tạo \(x_0, P_0\) — double precision hoặc mô phỏng Q8.24 để khớp RTL. |
| **`scoreboard`** | Nhận **actual** (từ monitor đọc OUT hoặc từ analysis port) và **expected** từ predictor; so trong ngưỡng. |

### 2.3 Virtual interface & config

- **`virtual interface`** cho **AXI** và **sensor** (bundle các `logic` tương ứng `tb_fusion_ip`).
- **`fusion_env_config`** (`uvm_object`): `clk_period`, `poll_timeout`, `error_threshold`, `route_csv_path`, `noise_seed`, bật/tắt predictor.

### 2.4 Sequence / test layering

- **`fusion_base_test`:** build env, apply config, `phase.run_phase` gọi virtual sequence mặc định.
- **`fusion_sanity_vseq`:** một chu kỳ — inject đo → AXI write `CTRL[0]=1` → poll `STATUS[1]` → đọc OUT.
- **`fusion_route_vseq`:** lặp N bước từ file đã merge (hoặc từ DPI đọc CSV).

---

## 3. Các test cần thực hiện

| ID | Tên (gợi ý) | Mục đích |
|----|-------------|----------|
| **T1** | `fusion_sanity` | Reset, một chu kỳ UKF, đo cố định, poll `STATUS.valid`, đọc `OUT_*`, không lỗi. |
| **T2** | `fusion_multi_cycle` | Nhiều chu kỳ liên tiếp; state RAM nối tiếp (không reset giữa chu kỳ trừ khi scenario yêu cầu). |
| **T3** | `fusion_missing_gps` | `gps_valid=0` hoặc map sensor tắt GPS — pipeline skip GPS, kiểm tra `STATUS` / hành vi hợp lệ. |
| **T4** | `fusion_irq_status` | Sau khi hoàn thành, kiểm tra `irq` và xóa qua `IRQ_CLR`. |
| **T5** | `fusion_soft_reset` | Ghi `CTRL[1]` trong lúc busy; `STATUS[0]` về 0 (hành vi như TB hiện tại). |
| **T6** | `fusion_ral_bit_bash` | (Tùy chọn) walk qua RAL frontdoor, đọc lại default/mirror. |
| **T7** | `fusion_scoreboard_ref` | Cùng input với predictor; so OUT với ref (ngưỡng). |
| **T8** | `fusion_csv_route` | Timeline merge từ CSV (GPS/IMU/Odom đã căn timestamp); nhiều `start`; so RMSE hoặc pass/fail theo ngưỡng. |

*Bảng có thể mở rộng thêm test AXI protocol (exclusive access, stray byte — nếu DUT hỗ trợ).*

---

## 4. Luồng thực thi test (run flow)

### 4.1 Luồng tổng quát (mọi test)

1. **Build phase:** tạo env, agent, RAL, adapter; kết nối virtual interface từ `uvm_config_db`.
2. **End of elaboration:** map RAL với DUT (nếu dùng frontdoor); đăng ký scoreboard với monitor.
3. **Run phase:**
   - Reset DUT (task reset đồng bộ `rst_n`).
   - (Tùy chọn) backdoor init \(P\), \(Q\), \(R\) trong RAM — giống `tb_fusion_ip` initial block nếu cần prior hợp lệ.
   - Chạy **virtual sequence** tương ứng test.
4. **Report phase:** `uvm_info` tổng kết; scoreboard báo số mismatch.

### 4.2 Luồng một chu kỳ UKF (trong sequence)

```
1. Driver sensor: đặt gps_data / imu_data / odom_data, pulse *_valid (theo scenario).
2. (Optional) AXI write các thanh ghi đo — đồng bộ với cách TB hiện tại.
3. AXI write CTRL = 1 (start).
4. Loop poll STATUS qua AXI read cho đến khi STATUS[1]==1 hoặc STATUS[2]==1 (error) hoặc timeout.
5. Nếu success: AXI read OUT_X … OUT_DOT; đẩy actual tới scoreboard.
6. (Optional) AXI write IRQ_CLR để xóa irq.
7. Predictor (nếu bật): tính expected cùng bước; scoreboard compare.
```

### 4.3 Luồng test route CSV (T8)

1. **Offline:** pipeline `tracking_ship` → `ukf_results_caseN.csv` và các `*_measurement.csv`; sau đó `scripts/generate_golden.py` sinh `tb/golden/golden_stimulus.csv`, `tb/golden/golden_expected.csv`, và cập nhật `tb/state_mem_init.memh` (xem `scripts/README.md`).
2. **Simulation:** `fusion_csv_route_vseq` đọc từng dòng stimulus; ghi `REG_DT` (0x1C); lặp **4.2** cho mỗi chu kỳ.
3. Scoreboard: DUT vs predictor; hiệu chuẩn vs golden Python; metric chất lượng vs ground truth (AIS).

### 4.4 Sơ đồ luồng dữ liệu (kiểm tra)

```
[Sequence] → sensor_driver → DUT ports
           → axi_driver    → DUT AXI
[Monitor]  ← DUT           → analysis_port → [Scoreboard]
[Predictor] ← same inputs (từ sequence/ref) → expected → Scoreboard
```

---

## 5. Phụ thuộc công cụ

- Simulator hỗ trợ **SystemVerilog + UVM** (Questa, VCS, Xcelium, …).
- Filelist: RTL `fusion_ip_top` và dependencies + UVM package + testbench top bọc DUT + `uvm_test`.

---

## 6. Tham chiếu mã nguồn trong repo

| Nội dung | File |
|----------|------|
| Map AXI / thanh ghi | `fusion_ip_top.sv` (comment đầu file) |
| Test không-UVM (tham khảo timing) | `tb_fusion_ip.sv` |
| Tham số UKF / địa chỉ RAM | `params.vh` |

---

*Tài liệu này mô tả thiết kế mục tiêu; triển khai file `.sv` UVM là bước riêng sau khi thêm UVM vào flow build.*

2. Luồng từ Scripts → Golden Model → Scoreboard
Đây là kiến trúc tổng thể:

┌─────────────────────────────────────────────────────────────────┐
│  OFFLINE (chạy 1 lần trước simulation)                         │
│                                                                 │
│  generate_golden.py  ──→  state_mem_init.memh  (P, Q, R hex)   │
│  (Python UKF engine)  ──→  golden_stimulus.csv (sensor inputs)  │
│                       ──→  golden_expected.csv (expected output) │
└─────────────────────────────────────────────────────────────────┘
          │                          │
          │ $readmemh                │ T8 CSV test reads this
          ▼                          ▼
┌─────────────────────────────────────────────────────────────────┐
│  SIMULATION (UVM testbench)                                     │
│                                                                 │
│  ┌──────────┐    sensor_vif     ┌────────────────┐              │
│  │ Test Seq │──────────────────→│  DUT           │              │
│  │ (T1-T7)  │  drive_sensor_   │  fusion_ip_top │              │
│  │          │  frame()         │                │              │
│  └──────────┘                   └───────┬────────┘              │
│       │                                 │ AXI reads             │
│       │                                 ▼                       │
│       │  ┌──────────────┐    ┌──────────────────┐               │
│       │  │sensor_monitor│    │  axi_monitor     │               │
│       │  │ watches VIF  │    │  watches VIF     │               │
│       │  └──────┬───────┘    └────────┬─────────┘               │
│       │         │ analysis_port       │ analysis_port            │
│       │         ▼                     ▼                         │
│       │  ┌─────────────────────────────────────┐                │
│       │  │         SCOREBOARD                   │                │
│       │  │                                     │                │
│       │  │  write_sensor(m) ──→ predictor.step()│                │
│       │  │  (sensor data)      (SV UKF engine)  │                │
│       │  │                         │            │                │
│       │  │  write_axi(t) ──→ collect 5 regs     │                │
│       │  │  (AXI reads)    ──→ compare_outputs()│                │
│       │  │                         │            │                │
│       │  │              DUT output vs Predictor  │                │
│       │  │              RMSE, max_err → PASS/FAIL│                │
│       │  └─────────────────────────────────────┘                │
└─────────────────────────────────────────────────────────────────┘
Tóm tắt 3 con đường:

generate_golden.py → state_mem_init.memh — khởi tạo bộ nhớ DUT với P=I, Q=0.01I, R=0.1I (Q8.24 hex). Đã verify: P[0][0]=0x01000000 (1.0) OK.

ukf_predictor.sv (SV reference model) — cùng thuật toán UKF, cùng parameters (alpha=1, dt=0.04). Chạy song song trong scoreboard. Mỗi khi sensor data đến, predictor tính expected output.

Scoreboard — so sánh: DUT output (đọc qua AXI register 0x20-0x30) vs predictor output. Tính RMSE, max_err, báo MATCH/MISMATCH.