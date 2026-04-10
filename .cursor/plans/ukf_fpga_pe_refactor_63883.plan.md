---
name: UKF FPGA PE refactor (63883 aligned, 5-state)
overview: Refactor sigma_gen, predict, và update theo kiến trúc khối trong Soh & Wu (63883) — trisolve (LDL/Cholesky + right-divide), matrix multiply-add PE, mean/covariance PE — nhưng với vector state cố định N_STATE=5 và công thức UKF không augmented (Q/R tách, không đưa nhiễu vào state). Dùng Xilinx FP IP + PE FMA như đã chọn.
todos:
  - id: baseline-doc
    content: Ghi bản đối chiếu paper Fig 5/6/7/8/9/10 vs RTL hiện tại (sigma_gen, predict, update) — kích thước và luồng dữ liệu
    status: completed
  - id: fp-ip-pe
    content: Tạo Xilinx FP IP wrappers + khối PE FMA (+FIFO) + demux/scheduler theo paper Section 3.1
    status: completed
  - id: sigma-paper-shape
    content: sigma_point_generator theo Fig 5–6–7 nhưng P 5×5, không P_a; trisolve + matmul-add sigma; giữ 2N+1 sigma Fusion
    status: completed
  - id: predict-paper-shape
    content: predict_block theo Fig 8–9 mean/cov PE path; CTRV f(.) vẫn application-specific; cộng Q sau như hiện tại
    status: completed
  - id: update-paper-shape
    content: update_block theo Fig 10; S, Pxz, K, cập nhật x/P — không augmented noise state
    status: completed
  - id: integrate-top-uvm
    content: fusion_ip_top nối datapath; compile.f; UVM timeout + regression
    status: completed
isProject: false
---

# Refactor sigma / predict / update theo 63883 (5 state, không augmented)

## Nguồn: Soh & Wu, chương "A Scalable, FPGA-Based Implementation of the UKF"

Đã đọc lại **Section 3** trong [63883.pdf](d:\Fusion_IP\63883.pdf). Cấu trúc logic ba phần trong **IP core** của bài báo:


| Bước          | Mục paper                                                             | Module / hình                                                                                                                                                       |
| ------------- | --------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Sigma gen** | Căn bậc hai ma trận hiệp phương sai + nhân–cộng cột để tạo sigma      | **Fig 5**: prefetch → **trisolve** → **matrix multiply-add** → ghi buffer; **Fig 6** trisolve (LDL, right divide, PE+FMA+FIFO); **Fig 7** matmul-add (PE song song) |
| **Predict**   | Sigma đã biến đổi qua mô hình → trung bình + hiệp phương sai a priori | **Fig 8**: prefetch → mean → residual → covariance; **Fig 9** mean/cov (MAC, PE, FIFO bỏ nhân đầu cho mean)                                                         |
| **Update**    | Quan sát, S, Pxz, K, cập nhật x và P                                  | **Fig 10**: prefetch → mean/residual quan sát → S → cross-cov với residual predict → K → matmul-add cập nhật                                                        |


**Lưu ý quan trọng từ paper (khác Fusion):** mục **3.2** nói rõ *"augmented state vector and covariance"* và Eq. (8)–(9) dùng \chi^w (noise trong sigma). **Yêu cầu của bạn:** **không** triển khai augmented UKF; **chỉ 5 biến state** như hiện tại (`x, y, v, ψ, ψ̇`); **nhiễu quá trình / đo** là **Q, R** (và cộng Q trong predict / R trong update), **không** mở rộng vector state với biến nhiễu.

## Đối chiếu nhanh: RTL hiện tại (trước refactor)

- **[sigma_point_generator.sv](d:\Fusion_IP\rtl\sigma_point_generator.sv):** LDLᵀ trên **P 5×5** trong RAM, scale \gamma\sqrt{D}, ghi sigma — **đúng hướng trisolve + tái hợp L1**, nhưng **chưa** tách prefetch/serializer/matmul-add như Fig 5–7; toán FP **chưa synthesis-friendly** ([fp32_math.svh](d:\Fusion_IP\rtl\fp32_math.svh)).
- **[predict_block.sv](d:\Fusion_IP\rtl\predict_block.sv):** CTRV từng sigma point, rồi weighted mean + weighted outer sum + Q + symmetrize — **đúng chức năng Fig 8–9**, nhưng **một FSM tích hợp**, không có lớp "calculate mean/covariance" PE như Fig 9; CORDIC **sim-only**.
- **[update_block.sv](d:\Fusion_IP\rtl\update_block.sv):** Cập nhật tuần tự GPS/IMU/odom (innovation, S, K, x, P) — **tương đương một phần Fig 10**, nhưng **không** bản sao prefetch/parallel buffer/paper; FP **sim-only**.

## Hướng refactor (theo paper, ràng buộc 5-state)

### 1. Sigma gen (Fig 5–6–7, không augmented)

- **Đầu vào:** `x` (5), `P` (5×5) — **không** `x^a`, `P^a`.
- **Trisolve (Fig 6):** giữ ý **LDLᵀ + sqrt trên D + scale cột** (đã có trong thuật toán hiện tại); triển khai lại bằng **PE FMA + FIFO + demux** + **Xilinx div/sqrt**, tách khỏi vòng `for` tổ hợp một clock.
- **Matrix multiply-add (Fig 7):** bước paper “nhân hệ số sigma + cộng mean theo cột” — map sang **UKF Fusion**: tạo \chi từ cột đã scale + `x` (giữ **2N+1 = 11** điểm và trọng số **Van der Merwe** như [params.vh](d:\Fusion_IP\rtl\params.vh), **không** bắt buộc chuyển sang spherical simplex M+2 của paper trừ khi có yêu cầu riêng).
- **Prefetch / serializer:** nếu bộ nhớ vẫn một cổng/nối tiếp — thêm lớp tương đương paper để nuôi **PE song song** (số PE = tham số).

### 2. Predict (Fig 8–9)

- **Mô hình `f`:** vẫn **CTRV trong PL** (application-specific), không đưa vào “IP generic” của paper — đúng tinh thần HW/SW codesign (paper để `f`/`h` phần mềm; Fusion đặt CTRV trong RTL — giữ như hiện tại trừ khi đổi partition).
- **Mean (Eq. 25 dạng cột):** \hat{x}^- = \sum_i W_i^m \chi_i — **MAC theo cột**, PE như Fig 9 (FIFO skip nhân đầu cho nhánh mean nếu áp dụng cùng trick paper).
- **Covariance (Eq. 27–28):** residual \tilde{\chi}_i = \chi_i - \hat{x}^-, rồi P^- = \sum_i W_i^c \tilde{\chi}_i \tilde{\chi}_i^T — **PE + hàng song song** như Fig 9.
- **Q:** cộng vào P^- **sau** bước covariance (như [predict_block](d:\Fusion_IP\rtl\predict_block.sv) hiện tại) — **không** dùng state nhiễu augmented.

### 3. Update (Fig 10)

- Luồng paper: quan sát → mean/residual không gian đo → **S** → kết hợp residual predict để **Pxz** → **K** → cập nhật **x, P** bằng matmul-add.
- **Fusion:** GPS/IMU/odom tuần tự; map từng pass vào **cùng họ PE** (matmul-add, trisolve/right-divide cho S^{-1}) với kích thước **2×2 / 1×1** tùy sensor — vẫn **5 state**, **R** là nhiễu đo, không mở rộng state.

### 4. Phân vùng HW/SW so với bài báo

- Paper: **PS** chạy `f`, `h` và đổ sigma đã transform vào buffer. Fusion hiện tại: **f** (predict) trong PL. Kế hoạch refactor **chỉ** đổi **kiến trúc khối + PE + FP IP** trong sigma/predict/update; **không** bắt buộc chuyển CTRV lên PS (có thể ghi chú follow-up).

## Ràng buộc thiết kế (tóm tắt)

- **N_STATE = 5** cố định; **không** augmented vector (không \chi^w trong state).
- **Q, R** như ma trận nhiễu hiện tại; cộng **Q** sau predict; **R** trong update.
- **Giữ** số sigma **11** và UKF \lambda,\gamma,W hiện tại trừ khi quyết định đổi formulation.
- **Xilinx Floating-Point IP**; Questa có thể **behavioral fallback** (`ifdef`) khi không nạp model Xilinx.

## Thứ tự thực hiện đề xuất

1. Bảng đối chiếu chi tiết (tín hiệu, địa chỉ RAM, số chu kỳ) — Fig 5–10 ↔ file RTL.
2. Wrapper IP + **PE FMA** + scheduler/demux tối thiểu.
3. Refactor **sigma_gen** (trisolve + matmul-add).
4. Refactor **predict** (mean/cov module + CTRV).
5. Refactor **update** (Fig 10 pipeline).
6. Top + UVM (timeout, regression).

## Rủi ro

- Tăng độ trễ chu kỳ UKF → chỉnh poll TB.
- Predictor `real` trong TB có thể lệch bit với FP IP — tolerance hoặc model làm tròn sau.

## Thực thi (trạng thái)

**Execute bị chặn trong Plan mode:** Cursor chỉ cho phép sửa markdown khi Plan mode bật. Để agent tạo/sửa file `.sv`, hãy **tắt Plan mode** hoặc chuyển sang **Agent mode**, rồi nhắn lại *execute the plan* (hoặc *implement*).

Các file dự kiến tạo đầu tiên: `rtl/ukf_fp_pkg.svh`, `rtl/ukf_fp_engine.sv`, `rtl/ukf_fmac_pe.sv`; sau đó refactor `sigma_point_generator.sv`, `predict_block.sv`, `update_block.sv`; cập nhật `sim/compile.f` và `tb/fusion_env.sv` (POLL_TO).