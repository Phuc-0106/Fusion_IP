# UVM integration — CSV route test (AIS golden)

## Test and sequence

- **Test:** `fusion_csv_route_test` (`fusion_tests_pkg` in `testcases/fusion_tests.sv`).
- **Virtual sequence:** `fusion_csv_route_vseq` reads CSVs via classes in `sequences/csv_route_sequence.sv` (`golden_stimulus_reader`, `golden_expected_reader`).

## Default files (relative to `sim/`)

| Variable | Default |
|----------|---------|
| Stimulus | `../tb/golden/golden_stimulus.csv` |
| Expected | `../tb/golden/golden_expected.csv` |

Override with plusargs:

```text
+STIM_FILE=<path>
+EXPECT_FILE=<path>
```

Other plusargs: `+POLL_TO=<cycles>`, `+MAX_CYCLES=<N>` (0 = all rows).

## DUT initialization

`tb/tb_fusion_ip.sv` loads **`../tb/state_mem_init.memh`** at time 0. It must be regenerated with **`generate_golden.py`** for the same **`--case`** as `ukf_results_caseN.csv`, or P/Q/R will not match the Python tuning case. From repo root, **`python scripts/check_golden_consistency.py --case N --datadir . --golden-dir tb/golden`** checks CSV merge assumptions (including that **`gps_measurement.csv` is not used** in `generate_golden`) and compares memh tuning to `get_tuning_matrices(N)`.

## Per-cycle behavior (T8)

1. Write **DT** register `0x1C` (FP32 `dt` from golden row `dt_hex`).
2. Call scoreboard **`set_dt()`** so the SV predictor uses the same `dt`.
3. **`push_golden()`** — GT, GPS, Python `est_*` (5-state), and the same **`dt_hex`** for optional `+UKF_DEBUG_DT` cross-check.
4. Drive **sensor_vif** (GPS / IMU / odom).
5. Start UKF, poll status, read outputs `0x20`–`0x30`, clear IRQ.

## Scoreboard

Configured in the environment as **`fusion_scoreboard`** (`tb/fusion_scoreboard.sv`): primary DUT vs predictor, optional calibration vs golden CSV, quality vs GT.

### Debug plusargs (`RUNARG` / `vsim`)

- **`+UKF_DEBUG_DT`** — each UKF cycle logs **dt** for: scoreboard latch (`set_dt`), SV `ukf_predictor.current_dt`, DUT **`reg_dt`** and **effective** dt (same rule as RTL: `0` → 1.0 s), and **golden** `dt_hex` from the CSV row (T8 passes it via `push_golden`). Emits **`UKF_DBG_DT`** warnings if any path disagrees (bit mismatch or float delta above about 1e-5).
- **`+UKF_DEBUG_P`**, **`+UKF_DEBUG_PPRED`**, **`+UKF_DEBUG_SIGMA`** — P / P_pred / sigma diagnostics (see scoreboard messages at time 0).

## Makefile note

`sim/Makefile` may pass `RUNARG` with legacy `+CSV_FILE=...`; the **current** T8 sequence uses **`STIM_FILE` / `EXPECT_FILE`** as above. Prefer generating golden files and running `make test-csv` without relying on `CSV_FILE`.

## Related RTL

- **REG_DT** at `0x1C` — sample period in Q8.24 (see `rtl/fusion_ip_top.sv`).
