# UKF RTL ↔ Soh & Wu (63883) crosswalk

Fixed **N_STATE = 5**, **non-augmented** UKF: process/measurement noise via **Q** and **R** only (no noise state in σ-points).

## Figure 5 — Sigma prefetch / high-level sigma path

| Paper concept | Fusion RTL | Notes |
|---------------|------------|--------|
| Prefetch x, P | `sigma_point_generator`: `SG_LOAD_X`, `SG_LOAD_P` | Single memory port; serialized reads from `ADDR_X`, `ADDR_P`. |
| Trisolve (LDL) | `SG_LDJ_*`, `SG_LDI_*` | LDLᵀ on 5×5 **P** in `L_mat` / `D_vec`; FP via `ukf_fp_engine`. |
| Sqrt / scale columns | `SG_SC_*` | √D, γ scaling, lower-triangular column writes. |
| Matrix multiply–add (σ from L + mean) | `SG_WX0`, `SG_WP_*`, `SG_WM_*` | χ₀ = x̂; χᵢ = x̂ ± scaled column; **11** σ-points, Van der Merwe weights in `params.vh`. |

## Figure 6 — Trisolve PE (LDL, right-divide)

| Paper | RTL |
|-------|-----|
| PE + FMA + FIFO | `ukf_fp_engine` (mul/add/sub/div/sqrt/recip/FMA); `ukf_fmac_pe` (MAC chain); `ukf_pe_stream_slice` (optional 1-deep operand register). |
| Div / sqrt | `UKF_FP_DIV`, `UKF_FP_SQRT`, `UKF_FP_RECIP` in `ukf_fp_engine` (sim: `fp32_math.svh`; synth: Xilinx FP IP via `UKF_SYNTH_XILINX_FP`). |

## Figure 7 — Matmul-add for σ assembly

| Paper | RTL |
|-------|-----|
| Column × γ√D + add mean | Implemented as explicit column writes plus `SG_WX0` / positive / negative σ rows (not a separate parallel PE array; N=5 fixed). |

## Figure 8 — Predict dataflow

| Paper | RTL |
|-------|-----|
| Transform σ through f | `predict_block`: load σ → CORDIC(ψ) → `ukf_fp_engine` for ψ+ψ̇·dt → CORDIC(ψ+ψ̇·dt) → CTRV micro-sequence (`PB_CTRV_ISS`/`CAP`) → write `ADDR_SP`. |
| Mean / residual / covariance | `PB_MEAN_*` (weighted mean MAC), `PB_COV_*` (diff + weighted outer product), then **+Q** (`PB_LOAD_Q`/`PB_ADD_Q`), symmetrize (`PB_SYM_*`). |

## Figure 9 — Mean / covariance PE

| Paper | RTL |
|-------|-----|
| Column-wise mean MAC | `PB_MEAN_MUL` / `PB_MEAN_MULW` / `PB_MEAN_ADD` / `PB_MEAN_ADDW` with `wm0`/`wmi`. |
| Covariance (residual outer sum) | `PB_COV_*`: `SUB` for residual, then `MUL`×`MUL`×`ADD` into `pp_acc`. |

## Figure 10 — Update path

| Paper | RTL |
|-------|-----|
| Innovation ν | `UB_INN_*`: `SUB` via `ukf_fp_engine`. |
| S, S⁻¹ | `UB_S_*`: build S with `ADD`/`SUB`/`MUL`; 2×2 `inv2x2` as `UB_INV_*` micro-sequence; 1×1 uses `RECIP`. |
| Cross-cov / K | `UB_CROSS_COV` (copy **P** columns, no FP); `UB_KG_*` matmul with FE. |
| State / covariance update | `UB_XU_*` (x += Kν); `UB_PJ_*` Joseph form with sequential FE (IKH, T1, T2, KRK, symmetrize). |

## Memory map (UKF buffers)

| Symbol | `params.vh` macro | Role |
|--------|-------------------|------|
| x̂, P | `ADDR_X`, `ADDR_P` | Prior state / covariance |
| σ | `ADDR_SIGMA` | Sigma points |
| χ⁻ (predicted σ) | `ADDR_SP` | After CTRV |
| x̂⁻, P⁻ | `ADDR_XPRED`, `ADDR_PPRED` | Predict outputs |
| Q | `ADDR_Q` | Process noise diagonal/block read in predict |

## Simulation vs synthesis

| Mode | Define | Behavior |
|------|--------|----------|
| Questa / behavioral (default) | *(none)* | `ukf_fp_engine` includes `fp32_math.svh` and implements ops in RTL. |
| Xilinx placeholder | `UKF_SYNTH_XILINX_FP` | Stub result path in `ukf_fp_engine` — replace with generated Floating-Point Operator IP. |

## PE / scheduler RTL

| File | Role |
|------|------|
| `ukf_fmac_pe.sv` | FMA chain (FMA_CLR / FMA_ACC). |
| `ukf_pe_stream_slice.sv` | 1-deep operand register slice. |
| `ukf_fp_sched_mux.sv` | 2:1 command mux to a shared engine (optional in `fusion_ip_top`). |

## UVM

| Item | Location |
|------|----------|
| STATUS poll budget | `fusion_env_pkg::fusion_env_config::poll_timeout` (default **200_000** cycles; override `+timeout=` / `+POLL_TO=` per test). |
